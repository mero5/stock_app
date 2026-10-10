// ============================================================
// StockLogo（ホームの銘柄の左の画像）と、/stock/quotes の logo_url の受け取り
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_app/services/stock_service.dart';
import 'package:stock_app/widgets/stock_logo.dart';

void main() {
  test('頭文字は銘柄名の1文字目（英字は大文字）', () {
    expect(StockLogo.initialOf('トヨタ自動車'), 'ト');
    expect(StockLogo.initialOf('apple Inc.'), 'A');
    expect(StockLogo.initialOf('  '), '?');
  });

  test('同じ銘柄名なら同じ色', () {
    expect(StockLogo.colorOf('トヨタ自動車'), StockLogo.colorOf('トヨタ自動車'));
  });

  testWidgets('画像が無いときは頭文字の丸', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StockLogo(name: 'ソニーグループ'))),
    );
    expect(find.text('ソ'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  test('/stock/quotes の logo_url を受け取る', () {
    final s = StockService.stockFromQuote('72030', 'トヨタ自動車', {
      'price': 2910.5,
      'logo_url': 'https://www.google.com/s2/favicons?domain=global.toyota&sz=128',
    });
    expect(s.logoUrl, contains('global.toyota'));
    expect(StockService.stockFromQuote('285A0', '285A0', {'logo_url': null}).logoUrl, isNull);
    expect(StockService.stockFromQuote('285A0', '285A0', {'logo_url': ''}).logoUrl, isNull);
  });
}
