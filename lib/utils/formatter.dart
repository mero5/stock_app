class Formatter {
  static String number(dynamic value, {int decimals = 0}) {
    if (value == null) return "---";
    final num v = value is num ? value : num.parse(value.toString());
    final parts = v.toStringAsFixed(decimals).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return decimals > 0 ? '$intPart.${parts[1]}' : intPart;
  }

  static String marketCap(dynamic mc) {
    if (mc == null) return "---";
    final v = (mc as num).toDouble();
    if (v >= 1e12) return "${number(v / 1e12, decimals: 1)}兆円";
    if (v >= 1e8) return "${number(v / 1e8)}億円";
    return "¥${number(v)}";
  }
}
