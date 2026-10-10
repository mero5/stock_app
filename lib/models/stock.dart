import '../utils/stock_code.dart';

class Stock {
  final String code;
  final String name;
  final String price;
  final String change;
  final String changePct;
  final bool isPositive;

  /// 銘柄の画像（会社の Web サイトのアイコン）の URL。分からなければ null
  final String? logoUrl;

  Stock({
    required this.code,
    required this.name,
    this.price = "---",
    this.change = "",
    this.changePct = "",
    this.isPositive = true,
    this.logoUrl,
  });

  factory Stock.fromMap(Map<String, String> map) {
    return Stock(
      code: map['code'] ?? '',
      name: map['name'] ?? '',
      price: map['price'] ?? '---',
      change: map['change'] ?? '',
      changePct: map['change_pct'] ?? '',
      isPositive: map['is_positive'] != 'false',
      logoUrl: map['logo_url'],
    );
  }

  Map<String, String> toMap() {
    return {
      'code': code,
      'name': name,
      'price': price,
      'change': change,
      'change_pct': changePct,
      'is_positive': isPositive ? 'true' : 'false',
      'logo_url': ?logoUrl,
    };
  }

  // stock.dart に追加
  String get displayCode {
    // 日本株の5桁コードは4桁で表示（285A0 → 285A のような英字入りも含む）
    return StockCode.display(code);
  }
}
