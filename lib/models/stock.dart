class Stock {
  final String code;
  final String name;
  final String price;
  final String change;
  final String changePct;
  final bool isPositive;

  Stock({
    required this.code,
    required this.name,
    this.price = "---",
    this.change = "",
    this.changePct = "",
    this.isPositive = true,
  });

  factory Stock.fromMap(Map<String, String> map) {
    return Stock(
      code: map['code'] ?? '',
      name: map['name'] ?? '',
      price: map['price'] ?? '---',
      change: map['change'] ?? '',
      changePct: map['change_pct'] ?? '',
      isPositive: map['is_positive'] != 'false',
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
    };
  }
}
