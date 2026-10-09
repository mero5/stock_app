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
//
// 【重要】Hubの sessionExpired だけでは期限切れを検知できない。
// このイベントは fetchAuthSession() がトークン更新に失敗したときにしか流れないが、
// バックエンドAPIはトークンを使わないため、普段の操作では
// fetchAuthSession() が呼ばれず、イベントが一度も流れないことがある。
// （その結果、期限切れのままホーム画面に留まり、ウォッチリストが空になっていた）
// そのため以下のタイミングでも能動的に確認する：
//   ・アプリがバックグラウンドから復帰したとき（didChangeAppLifecycleState）
//   ・ウォッチリストを読み込む前（HomeViewModel.loadFavorites）
//   ・認証系の例外を受け取ったとき（handleAuthError）
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
    // バックグラウンドからの復帰時にも期限切れを確認する
    WidgetsBinding.instance.addObserver(_LifecycleObserver());
  }

  /// 期限切れかどうかを確認し、切れていればログイン画面へ戻す
  ///
  /// 返り値：期限切れだった（＝ログイン画面へ戻す処理を始めた）ならtrue。
  /// 呼び出し側はtrueのとき、以降の処理（API呼び出し等）を中断すること。
  static Future<bool> checkAndHandle() async {
    if (_isHandling) return true;
    final expired = await AuthService.isSessionExpired();
    if (expired) handleExpired();
    return expired;
  }

  /// 例外が認証切れによるものならログイン画面へ戻す
  ///
  /// Amplify.Auth.getCurrentUser() などはセッション切れのとき
  /// SessionExpiredException / SignedOutException を投げる。
  /// これを握り潰すと「データが表示されないだけ」の状態になるため、
  /// catch した箇所でこのメソッドに渡す。
  ///
  /// 返り値：認証切れとして処理したならtrue
  static bool handleAuthError(Object e) {
    if (e is SessionExpiredException || e is SignedOutException) {
      handleExpired();
      return true;
    }
    return false;
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

/// アプリのライフサイクル（前面／背面）を監視する
///
/// アプリを長時間バックグラウンドに置いている間にリフレッシュトークンが
/// 切れることがある。復帰したタイミングで確認して、切れていれば
/// ログイン画面へ戻す。
class _LifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SessionGuard.checkAndHandle();
    }
  }
}
