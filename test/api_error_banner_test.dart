// ============================================================
// ApiErrorBanner
// サーバー接続エラー用の一文と、スケジュールの取得エラー用の一文（K-54）
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_app/widgets/api_error_banner.dart';

void main() {
  Future<String> render(WidgetTester tester, Widget banner) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: banner)));
    return tester.widget<Text>(find.byType(Text)).data!;
  }

  testWidgets('既定はサーバー接続エラーの一文', (tester) async {
    final text = await render(tester, const ApiErrorBanner(message: 'J-Quantsに接続できません'));
    expect(text, 'J-Quantsに接続できません\n株価取得・AI分析などの機能が制限されています。');
  });

  testWidgets('下の一文を変えられる', (tester) async {
    final text = await render(
      tester,
      const ApiErrorBanner(message: '日経平均を取得できませんでした', note: '右上の再読み込みボタンで取り直せます。'),
    );
    expect(text, '日経平均を取得できませんでした\n右上の再読み込みボタンで取り直せます。');
  });
}
