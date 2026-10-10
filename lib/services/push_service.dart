// ============================================================
// PushService
// プッシュ通知（Firebase Cloud Messaging：FCM）の準備と、通知をタップしたときの処理。
//
// 流れ：
//   1. Firebase を初期化する（設定は lib/config/firebase_options.dart）
//   2. 通知の許可をもらう（iPhone は許可が無いと通知が出ない）
//   3. この端末の宛先（FCM トークン）をバックエンドの /push/token に送る
//      → バックエンドは株価アラートの条件を満たしたら、この宛先に送る
//   4. 通知をタップしてアプリが開いたら、その銘柄の詳細画面を開く
//
// ・iPhone だけ対応する。Web版（PRのプレビュー・E2E）と Android では何もしない
// ・許可のダイアログは、アラートを初めて登録したときに出す（起動直後にいきなり出さない）。
//   起動時は「もう許可されていれば」宛先を送り直すだけ（トークンは変わることがあるため）
// ============================================================

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../config/firebase_options.dart';
import '../config/timeouts.dart';
import '../utils/stock_code.dart';
import 'api_client.dart';

class PushService {
  PushService._();

  static bool _initialized = false;
  static String? _token;
  static StreamSubscription<String>? _tokenRefresh;

  /// 株価アラートの通知がタップされたときに呼ぶ処理（画面側が登録する。引数は表示用コードと銘柄名）。
  /// 通信の層（services）から画面を直接開かないよう、画面を開く処理は外から渡してもらう
  static void Function(String code, String name)? onOpenStock;

  /// 画面側の登録より先に通知がタップされた（アプリの起動直後）ときに、いったん覚えておく
  static (String, String)? _pendingOpen;

  /// この端末でプッシュ通知を使えるなら true（iPhone で、Firebase の設定が入っている）
  static bool get isSupported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      FirebaseConfig.isConfigured;

  /// Firebase の初期化と、通知をタップしたときの処理の登録（1回だけ）
  static Future<bool> _ensureInitialized() async {
    if (!isSupported) return false;
    if (_initialized) return true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: FirebaseConfig.ios);
      }
      final messaging = FirebaseMessaging.instance;
      // アプリを開いている間に届いた通知も、画面の上に出す（既定では出ない）
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onMessageOpenedApp.listen(_openFromNotification);
      // アプリが閉じていた状態で通知をタップして起動したとき
      final initial = await messaging.getInitialMessage();
      if (initial != null) _openFromNotification(initial);
      _initialized = true;
      return true;
    } catch (e) {
      debugPrint('プッシュ通知の初期化エラー: $e');
      return false;
    }
  }

  /// 起動時（ログイン後のホーム）に呼ぶ。すでに許可されていれば宛先を送り直す
  static Future<void> refreshIfAuthorized() async {
    if (!await _ensureInitialized()) return;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (_isAllowed(settings.authorizationStatus)) await _registerToken();
    } catch (e) {
      debugPrint('プッシュ通知の宛先の更新エラー: $e');
    }
  }

  /// 通知の許可をもらい（まだなら iPhone のダイアログが出る）、宛先を送る。
  /// 許可されたら true。使えない端末・拒否されたら false
  static Future<bool> requestPermissionAndRegister() async {
    if (!await _ensureInitialized()) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (!_isAllowed(settings.authorizationStatus)) return false;
      await _registerToken();
      return true;
    } catch (e) {
      debugPrint('通知の許可エラー: $e');
      return false;
    }
  }

  /// ログアウトの前に呼ぶ。この端末に、ログアウトしたユーザーの通知が届かないようにする
  static Future<void> unregister() async {
    final token = _token;
    if (token == null) return;
    try {
      await ApiClient.post(
        Uri.parse('${Constants.backendUrl}/push/token/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      ).timeout(AppTimeouts.api);
    } catch (e) {
      debugPrint('プッシュ通知の宛先の削除エラー: $e');
    }
    _token = null;
  }

  static bool _isAllowed(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  /// この端末の宛先（FCM トークン）をバックエンドに送る。変わったときも送り直す
  static Future<void> _registerToken() async {
    final messaging = FirebaseMessaging.instance;
    // iPhone は Apple の宛先（APNs トークン）が先に用意されていないと FCM トークンを取れない
    if (await messaging.getAPNSToken() == null) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    final token = await messaging.getToken();
    if (token != null) await _sendToken(token);
    _tokenRefresh ??= messaging.onTokenRefresh.listen(_sendToken);
  }

  static Future<void> _sendToken(String token) async {
    try {
      await ApiClient.post(
        Uri.parse('${Constants.backendUrl}/push/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'platform': 'ios'}),
      ).timeout(AppTimeouts.api);
      _token = token;
    } catch (e) {
      debugPrint('プッシュ通知の宛先の登録エラー: $e');
    }
  }

  /// 株価アラートの通知をタップしたら、その銘柄の詳細画面を開く
  static void _openFromNotification(RemoteMessage message) {
    final data = message.data;
    if (data['type'] != 'price_alert') return;
    final code = data['code'] as String?;
    if (code == null || code.isEmpty) return;
    final displayCode = StockCode.display(code);
    final name = data['name'] as String?;
    final target = (displayCode, (name == null || name.isEmpty) ? displayCode : name);
    final open = onOpenStock;
    if (open == null) {
      _pendingOpen = target;
      return;
    }
    open(target.$1, target.$2);
  }

  /// 画面側が onOpenStock を登録したあとに呼ぶ。起動直後にタップされた通知があれば開く
  static void openPending() {
    final pending = _pendingOpen;
    final open = onOpenStock;
    if (pending == null || open == null) return;
    _pendingOpen = null;
    open(pending.$1, pending.$2);
  }
}
