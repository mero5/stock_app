// ============================================================
// WebView 版の画面の切り替え（AppConfigService）と、WebView で開いてよいURL（WebPageView）
//
// ・/app/config の形が違っても落ちず、その項目はネイティブのまま（安全側）
// ・取得前は、すべてネイティブの画面を使う
// ・WebView の中で開くのはバックエンドの /web/ の下だけ
// ============================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:stock_app/config/constants.dart';
import 'package:stock_app/services/app_config_service.dart';
import 'package:stock_app/widgets/web_page_view.dart';

void main() {
  group('AppConfigService.parseWebScreens', () {
    test('bool の項目だけを取り出す', () {
      final screens = AppConfigService.parseWebScreens({
        'web_screens': {'notice_history': true, 'market': false, 'bad': 'yes'},
      });
      expect(screens, {'notice_history': true, 'market': false});
    });

    test('形が違うときは空（全部ネイティブ）', () {
      expect(AppConfigService.parseWebScreens(null), isEmpty);
      expect(AppConfigService.parseWebScreens({'web_screens': []}), isEmpty);
      expect(AppConfigService.parseWebScreens('text'), isEmpty);
    });
  });

  test('設定を取る前は WebView 版を使わない', () {
    expect(AppConfigService.useWeb(WebScreen.noticeHistory), isFalse);
  });

  test('WebScreen のキーはバックエンドの web_screens と同じ名前', () {
    expect(WebScreen.noticeHistory.key, 'notice_history');
  });

  group('WebPageView.isAllowedUrl', () {
    test('バックエンドの /web/ の下は開く', () {
      expect(
        WebPageView.isAllowedUrl('${Constants.backendUrl}/web/notices'),
        isTrue,
      );
    });

    test('ほかのURL・バックエンドのAPIは開かない', () {
      expect(WebPageView.isAllowedUrl('https://example.com/web/notices'), isFalse);
      expect(WebPageView.isAllowedUrl('${Constants.backendUrl}/notices'), isFalse);
      expect(
        WebPageView.isAllowedUrl('${Constants.backendUrl}.evil.com/web/x'),
        isFalse,
      );
    });
  });
}
