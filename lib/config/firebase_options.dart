// ============================================================
// FirebaseConfig
// プッシュ通知（Firebase Cloud Messaging：FCM）に使う Firebase の設定。
//
// 値は Firebase コンソール → プロジェクトの設定 → マイアプリ（iOS）の
// GoogleService-Info.plist に書かれているもの（API_KEY・GOOGLE_APP_ID・GCM_SENDER_ID・PROJECT_ID）。
// これらは秘密の値ではない（アプリの中に入って配られるもの。送信に使う秘密の鍵は
// バックエンドの SSM パラメータストアにある）。
//
// 空のままだとプッシュ通知の準備をしない（アプリはそれ以外いつもどおり動く）。
// Android・Web は今は対応しない（iPhone だけ）。
// ============================================================

import 'package:firebase_core/firebase_core.dart';

class FirebaseConfig {
  FirebaseConfig._();

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
    iosBundleId: 'com.example.StockAnalysisApp',
  );

  /// 値が入っていれば true（入っていなければプッシュ通知を使わない）
  static bool get isConfigured =>
      ios.apiKey.isNotEmpty && ios.appId.isNotEmpty && ios.projectId.isNotEmpty;
}
