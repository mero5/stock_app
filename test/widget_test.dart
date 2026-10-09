// ============================================================
// 単体テスト
//
// 以前はFlutterのひな形（カウンターアプリ用）のままで、存在しない
// StockApp を参照していたため、flutter analyze / flutter test が
// 常にエラーになっていた。
//
// アプリ本体（MyApp）は起動時にAmplify（Cognito）の初期化が必要で
// テストから起動しにくいため、まずは外部に依存しない部分をテストする。
// ============================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:stock_app/models/stock.dart';
import 'package:stock_app/utils/formatter.dart';
import 'package:stock_app/utils/stock_code.dart';

void main() {
  group('Stock.displayCode', () {
    test('5桁の日本株コードは4桁で表示する', () {
      expect(Stock(code: '72030', name: 'トヨタ').displayCode, '7203');
    });

    test('4桁のコードはそのまま', () {
      expect(Stock(code: '7203', name: 'トヨタ').displayCode, '7203');
    });

    test('米国株のティッカーはそのまま', () {
      expect(Stock(code: 'AAPL', name: 'Apple').displayCode, 'AAPL');
    });

    test('英字入りの日本株コード（285A0）も4桁で表示する', () {
      expect(Stock(code: '285A0', name: 'キオクシア').displayCode, '285A');
    });
  });

  // 2024年から東証は英字入りのコード（285A キオクシア など）を使っている。
  // 以前は「数字だけか」で判定していたため、米国株として扱っていた。
  group('StockCode', () {
    test('日本株かどうか', () {
      for (final code in ['7203', '72030', '285A', '285A0', '130A']) {
        expect(StockCode.isJp(code), isTrue, reason: code);
      }
      for (final code in ['AAPL', 'BRK-B', '^N225', '7203.T', '720', '285a']) {
        expect(StockCode.isJp(code), isFalse, reason: code);
      }
    });

    test('保存用は5桁、yfinance用は4桁＋.T', () {
      expect(StockCode.storage('7203'), '72030');
      expect(StockCode.storage('285A'), '285A0');
      expect(StockCode.storage('72030'), '72030');
      expect(StockCode.storage('AAPL'), 'AAPL');
      expect(StockCode.ticker('285A0'), '285A.T');
      expect(StockCode.ticker('7203'), '7203.T');
      expect(StockCode.ticker('AAPL'), 'AAPL');
    });
  });

  group('Stock.toMap / fromMap', () {
    test('往復しても値が変わらない', () {
      final s = Stock(
        code: '72030',
        name: 'トヨタ',
        price: '3,000',
        change: '+10',
        changePct: '+0.33',
        isPositive: true,
      );
      final r = Stock.fromMap(s.toMap());
      expect(r.code, s.code);
      expect(r.price, s.price);
      expect(r.isPositive, isTrue);
    });
  });

  group('Formatter', () {
    test('3桁区切り', () {
      expect(Formatter.number(1234567), '1,234,567');
      expect(Formatter.number(1234.5, decimals: 1), '1,234.5');
    });

    test('nullは---', () {
      expect(Formatter.number(null), '---');
      expect(Formatter.marketCap(null), '---');
    });

    test('時価総額は兆円・億円で表示', () {
      expect(Formatter.marketCap(2.5e13), '25.0兆円');
      expect(Formatter.marketCap(3.0e10), '300億円');
    });
  });
}
