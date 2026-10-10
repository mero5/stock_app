// ============================================================
// StockLogo
// ホームのウォッチリストで、銘柄の左に出す丸い画像。
//
// 画像はバックエンドの /stock/quotes が返す logo_url（会社の Web サイトのアイコン）。
// 画像が無い・読み込めない・読み込み中のときは、銘柄名の頭文字を色付きの丸で出す
// （色は銘柄名から決めるので、同じ銘柄はいつも同じ色になる）。
// ============================================================

import 'package:flutter/material.dart';

class StockLogo extends StatelessWidget {
  /// 銘柄名（頭文字と色に使う）
  final String name;

  /// 画像の URL。null なら頭文字だけ
  final String? logoUrl;

  /// 丸の直径
  final double size;

  const StockLogo({
    super.key,
    required this.name,
    this.logoUrl,
    this.size = 40,
  });

  /// 頭文字の丸の背景色（銘柄名から決める）
  static const List<Color> _palette = [
    Colors.indigo,
    Colors.teal,
    Colors.deepOrange,
    Colors.purple,
    Colors.blueGrey,
    Colors.green,
    Colors.brown,
    Colors.blue,
  ];

  /// 銘柄名の頭文字（空なら「?」）
  static String initialOf(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  /// 銘柄名から背景色を選ぶ（同じ名前なら同じ色）
  static Color colorOf(String name) {
    final hash = name.runes.fold<int>(0, (sum, r) => (sum * 31 + r) & 0x7fffffff);
    return _palette[hash % _palette.length];
  }

  Widget _initial() {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colorOf(name),
      child: Text(
        initialOf(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.42,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = logoUrl;
    if (url == null || url.isEmpty) return _initial();
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        padding: EdgeInsets.all(size * 0.12),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          // 読み込み中・失敗したら頭文字を出す（画像が無い銘柄で空白にならないように）
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _initial(),
          errorBuilder: (context, error, stack) => _initial(),
        ),
      ),
    );
  }
}
