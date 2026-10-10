// ============================================================
// PriceAlert
// 株価アラート（指定の株価になったらプッシュ通知）1件分のデータ。
//
// バックエンドの /alerts が返す形をそのまま持つ（JSON のキーは snake_case のまま）。
// 条件の値（condition）・繰り返し（repeat）は backend/config/price_alerts.py と同じ。
// ============================================================

import '../utils/formatter.dart';
import '../utils/stock_code.dart';

/// 条件の種類（backend/config/price_alerts.py の CONDITIONS と同じ値）
class PriceAlertCondition {
  PriceAlertCondition._();

  static const priceAbove = 'price_above';
  static const priceBelow = 'price_below';
  static const changeUp = 'change_pct_above';
  static const changeDown = 'change_pct_below';

  static const all = [priceAbove, priceBelow, changeUp, changeDown];

  /// 画面に出す名前
  static String label(String condition) => switch (condition) {
    priceAbove => '株価が○円以上',
    priceBelow => '株価が○円以下',
    changeUp => '前日比 +○%以上（急騰）',
    changeDown => '前日比 -○%以下（急落）',
    _ => condition,
  };

  /// 金額ではなく % で入れる条件なら true
  static bool isPercent(String condition) =>
      condition == changeUp || condition == changeDown;
}

/// 繰り返し（backend/config/price_alerts.py の REPEATS と同じ値）
class PriceAlertRepeat {
  PriceAlertRepeat._();

  /// 条件を満たしている間、1日1回まで通知する
  static const daily = 'daily';

  /// 1回通知したら自動で OFF にする
  static const once = 'once';
}

class PriceAlert {
  final String alertId;
  final String code;
  final String name;
  final String condition;
  final double target;
  final String repeat;
  final bool enabled;

  /// 最後に通知した日（その市場の日付。"2026-10-13"）。まだなら空文字
  final String lastNotifiedDate;

  const PriceAlert({
    required this.alertId,
    required this.code,
    required this.name,
    required this.condition,
    required this.target,
    required this.repeat,
    required this.enabled,
    required this.lastNotifiedDate,
  });

  factory PriceAlert.fromJson(Map<String, dynamic> json) => PriceAlert(
    alertId: json['alert_id'] as String? ?? '',
    code: json['code'] as String? ?? '',
    name: json['name'] as String? ?? '',
    condition: json['condition'] as String? ?? '',
    target: (json['target'] as num?)?.toDouble() ?? 0,
    repeat: json['repeat'] as String? ?? PriceAlertRepeat.daily,
    enabled: json['enabled'] as bool? ?? false,
    lastNotifiedDate: json['last_notified_date'] as String? ?? '',
  );

  /// 画面表示用の銘柄コード（日本株は4文字）
  String get displayCode => StockCode.display(code);

  /// 条件を1行で（例：「3,000円以上」「前日比 -5%以下」）
  String get conditionText {
    final isWhole = target == target.roundToDouble();
    final value = StockCode.isJp(code)
        ? '${Formatter.number(target, decimals: isWhole ? 0 : 1)}円'
        : '\$${Formatter.number(target, decimals: 2)}';
    final pct = isWhole ? target.toStringAsFixed(0) : target.toString();
    return switch (condition) {
      PriceAlertCondition.priceAbove => '$value以上',
      PriceAlertCondition.priceBelow => '$value以下',
      PriceAlertCondition.changeUp => '前日比 +$pct%以上',
      PriceAlertCondition.changeDown => '前日比 -$pct%以下',
      _ => condition,
    };
  }
}
