// ============================================================
// SessionGuard
// ログインセッションの期限切れを検知して、
// ポップアップを出したうえでログイン画面へ戻す。
//
// Cognitoのリフレッシュトークンが切れると、Amplifyは
// Hub（Authチャンネル）に sessionExpired イベントを流す。
// これを1箇所で購読して処理する。
//
// 【重要】Amplifyのセッションは期限切れでも isSignedIn が true のままになる。
// （トークンのrefreshに失敗しても、保持している古いトークンがnullでないため）
// そのため isSignedIn だけでログイン状態を判定してはいけない。
// 起動時の判定には AuthService.hasValidSession() を使うこと。
// ============================================================

import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import '../screens/login_screen.dart';
import 'auth_service.dart';

class SessionGuard {
  /// アプリ全体のNavigator
  ///
  /// Hubのコールバックはウィジェットツリーの外から呼ばれるため、
  /// ダイアログ表示・画面遷移に使うNavigatorをここで保持する。
  /// main.dartのMaterialAppにこのkeyを渡している。
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// 処理中フラグ（ポップアップの多重表示を防ぐ）
  static bool _isHandling = false;

  /// セッション期限切れの監視を開始する
  ///
  /// main()でAmplifyの初期化が終わった後に一度だけ呼ぶ。
  static void start() {
    Amplify.Hub.listen(HubChannel.Auth, (AuthHubEvent event) {
      if (event.type == AuthHubEventType.sessionExpired) {
        handleExpired();
      }
    });
  }

  /// 期限切れを処理する（ポップアップ → ログアウト → ログイン画面）
  ///
  /// 複数の画面が同時にAPIを叩いて同時に期限切れになっても、
  /// ポップアップは1回だけ表示される。
  static void handleExpired() {
    if (_isHandling) return;
    _isHandling = true;

    // Hubのイベントは描画途中に飛んでくることがあるため、
    // 1フレーム待ってNavigatorが使える状態にしてから表示する
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navigator = navigatorKey.currentState;
      final dialogContext = navigatorKey.currentContext;
      if (navigator == null || dialogContext == null) {
        _isHandling = false;
        return;
      }

      await showDialog<void>(
        context: dialogContext,
        // 閉じるまで操作させない（期限切れのまま使わせないため）
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_clock, color: Colors.orange, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ログインの有効期限が切れました',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'セキュリティのため、一定期間が過ぎると自動的にログアウトされます。',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              SizedBox(height: 8),
              Text(
                'お手数ですが、もう一度ログインしてください。',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ログイン画面へ'),
            ),
          ],
        ),
      );

      // 古いトークンを確実に破棄する
      try {
        await AuthService.signOut();
      } catch (e) {
        // ログアウトに失敗しても画面は必ず戻す
        debugPrint('セッション期限切れ時のログアウトエラー: $e');
      }

      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      _isHandling = false;
    });
  }
}
