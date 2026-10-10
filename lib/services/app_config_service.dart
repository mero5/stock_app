// ============================================================
// AppConfigService
// バックエンドの /app/config から、アプリの表示設定を取ってくる。
//
// 今は「どの画面を WebView 版（バックエンドのHTML）で開くか」だけを持つ。
// サーバー側（backend/config/web_screens.py）で切り替えられるので、
// Web版に不具合が出ても、デプロイだけでネイティブの画面に戻せる。
//
// 安全側に倒す：取得前・取得に失敗したとき・アプリのWeb版（kIsWeb）では、
// すべてネイティブの画面を使う。
// ============================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../config/timeouts.dart';
import 'api_client.dart';

/// WebView 版を用意している画面。名前は backend/config/web_screens.py のキーと同じにする
enum WebScreen {
  /// 設定 → お知らせ履歴（/web/notices）
  noticeHistory('notice_history');

  const WebScreen(this.key);

  /// /app/config の web_screens のキー
  final String key;
}

class AppConfigService {
  AppConfigService._();

  static Map<String, bool> _webScreens = {};

  /// /app/config を取り直す。失敗したら前の値のまま（最初はすべてネイティブ）
  static Future<void> load() async {
    try {
      final res = await ApiClient.get(
        Uri.parse('${Constants.backendUrl}/app/config'),
      ).timeout(AppTimeouts.api);
      if (res.statusCode != 200) {
        debugPrint('アプリ設定の取得エラー: HTTP ${res.statusCode}');
        return;
      }
      _webScreens = parseWebScreens(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (e) {
      debugPrint('アプリ設定の取得エラー: $e');
    }
  }

  /// /app/config のレスポンスから web_screens を取り出す。形が違う項目は無視する
  @visibleForTesting
  static Map<String, bool> parseWebScreens(Object? json) {
    if (json is! Map) return {};
    final screens = json['web_screens'];
    if (screens is! Map) return {};
    return {
      for (final entry in screens.entries)
        if (entry.key is String && entry.value is bool)
          entry.key as String: entry.value as bool,
    };
  }

  /// [screen] を WebView 版で開くなら true
  ///
  /// アプリのWeb版（ブラウザ・PRのプレビュー・E2E）は WebView が使えないので常に false
  static bool useWeb(WebScreen screen) =>
      !kIsWeb && (_webScreens[screen.key] ?? false);
}
