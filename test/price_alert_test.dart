// 株価アラートのデータ（lib/models/price_alert.dart）
//
// バックエンドの /alerts が返す JSON を読めること、条件の表示が正しいことを確かめる。

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_app/models/price_alert.dart';

void main() {
  PriceAlert alert(String code, String condition, num target) =>
      PriceAlert.fromJson({
        'alert_id': 'a1',
        'code': code,
        'name': 'テスト',
        'condition': condition,
        'target': target,
        'repeat': 'once',
        'enabled': true,
        'last_notified_date': '',
      });

  test('JSON を読める（target は整数で来ても double にする）', () {
    final a = alert('72030', PriceAlertCondition.priceAbove, 3000);
    expect(a.target, 3000.0);
    expect(a.repeat, PriceAlertRepeat.once);
    expect(a.displayCode, '7203');
  });

  test('項目が欠けていても落ちない', () {
    final a = PriceAlert.fromJson({});
    expect(a.enabled, false);
    expect(a.repeat, PriceAlertRepeat.daily);
  });

  test('条件の表示', () {
    expect(alert('7203', PriceAlertCondition.priceAbove, 3000).conditionText,
        '3,000円以上');
    expect(alert('7203', PriceAlertCondition.priceBelow, 2999.5).conditionText,
        '2,999.5円以下');
    expect(alert('AAPL', PriceAlertCondition.priceAbove, 150).conditionText,
        '\$150.00以上');
    expect(alert('7203', PriceAlertCondition.changeUp, 5).conditionText,
        '前日比 +5%以上');
    expect(alert('7203', PriceAlertCondition.changeDown, 2.5).conditionText,
        '前日比 -2.5%以下');
  });

  test('前日比の条件だけ % で入れる', () {
    expect(PriceAlertCondition.isPercent(PriceAlertCondition.changeUp), true);
    expect(PriceAlertCondition.isPercent(PriceAlertCondition.priceAbove), false);
  });
}
