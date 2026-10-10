// ============================================================
// StockService.stockFromQuote
// ウォッチリストの1銘柄分（/stock/quotes・/stock/price の結果）を表示用の Stock にする
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_app/services/stock_service.dart';

void main() {
  test('株価と前日比を表示用の文字列にする', () {
    final s = StockService.stockFromQuote('72030', 'トヨタ自動車', {
      'price': 2910.5,
      'change': 8.5,
      'change_pct': 0.29,
    });
    expect(s.name, 'トヨタ自動車');
    expect(s.price, '2911');
    expect(s.change, '+8.5');
    expect(s.changePct, '+0.29%');
    expect(s.isPositive, isTrue);
  });

  test('値下がりはマイナス表示', () {
    final s = StockService.stockFromQuote('AAPL', 'Apple Inc.', {
      'price': 336.64,
      'change': -3.78,
      'change_pct': -1.11,
    });
    expect(s.change, '-3.8');
    expect(s.changePct, '-1.11%');
    expect(s.isPositive, isFalse);
  });

  test('取れなかった項目は --- と空文字', () {
    final s = StockService.stockFromQuote('285A0', '285A0', {
      'price': null,
      'change': null,
      'change_pct': null,
    });
    expect(s.price, '---');
    expect(s.change, '');
    expect(s.changePct, '');
  });

  test('Lambda に断られたときの応答（株価の項目が無い）でも落ちない', () {
    final s = StockService.stockFromQuote('72030', '72030', {
      'Reason': 'ConcurrentInvocationLimitExceeded',
      'message': 'Rate Exceeded.',
    });
    expect(s.price, '---');
  });
}
