// ============================================================
// FirebaseConfig
// プッシュ通知（Firebase Cloud Messaging：FCM）に使う Firebase の設定。
//
// 値は Firebase コンソール → プロジェクトの設定 → マイアプリ（iOS）の
// GoogleService-Info.plist に書かれているもの（API_KEY・GOOGLE_APP_ID・GCM_SENDER_ID・PROJECT_ID）。
// これらは秘密の値ではない（アプリの中に入って配られるもの。送信に使う秘密の鍵は
// バックエンドの SSM パラメータストアにある）。
//
// 値を空にするとプッシュ通知の準備をしない（アプリはそれ以外いつもどおり動く）。
// プロジェクトは Web版プレビューと同じ stock-app-preview（2026-10-11 に iOS アプリを登録）。
// Android・Web は今は対応しない（iPhone だけ）。
// ============================================================

import 'package:firebase_core/firebase_core.dart';

class FirebaseConfig {
  FirebaseConfig._();

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA-AMIqlndCMHCDB0G7ENnIa7OF9whhJZY',
    appId: '1:289901141481:ios:2b840b24802d92ebe83f78',
    messagingSenderId: '289901141481',
    projectId: 'stock-app-preview',
    iosBundleId: 'com.example.StockAnalysisApp',
  );

  /// 値が入っていれば true（入っていなければプッシュ通知を使わない）
  static bool get isConfigured =>
      ios.apiKey.isNotEmpty && ios.appId.isNotEmpty && ios.projectId.isNotEmpty;
}
