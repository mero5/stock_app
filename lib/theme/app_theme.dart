// ============================================================
// AppTheme
// アプリ全体のデザイントークンを一元管理するクラス。
//
// ここに色・フォントサイズ・余白・角丸を集約することで、
// ・デザイン変更が1箇所で済む
// ・チームで統一した見た目を保てる
// ・ハードコードされた数値をなくせる
//
// 使い方：
//   AppTheme.bullish       → 上昇色
//   AppTheme.fontSm        → 小さいフォント
//   AppTheme.spaceMd       → 中くらいの余白
// ============================================================

import 'package:flutter/material.dart';

class AppTheme {
  // ============================================================
  // プライマリカラー
  // ============================================================

  /// アプリのメインカラー（ボタン・アクセント）
  static const MaterialColor primary = Colors.blue;

  /// メインカラーの薄い背景版（カードの背景など）
  static const Color primaryLight = Color(0xFFE3F2FD);

  // ============================================================
  // 株価の上昇・下落カラー
  // 日本株の慣例に合わせて上昇=赤・下落=緑
  // ============================================================

  /// 上昇・買い・ポジティブを示す色（日本株慣例：赤）
  static const MaterialColor bullish = Colors.red;

  /// 下落・売り・ネガティブを示す色（日本株慣例：緑）
  static const MaterialColor bearish = Colors.green;

  /// 中立・様子見を示す色
  static const MaterialColor neutral = Colors.grey;

  /// 警告・注意を示す色
  static const MaterialColor warning = Colors.orange;

  /// 危険・エラーを示す色
  static const MaterialColor danger = Colors.red;

  // ============================================================
  // セマンティックカラー（意味を持つ色）
  // ============================================================

  /// 信頼度「高」の色
  static const MaterialColor confidenceHigh = Colors.green;

  /// 信頼度「中」の色
  static const MaterialColor confidenceMedium = Colors.orange;

  /// 信頼度「低」の色
  static const MaterialColor confidenceLow = Colors.red;

  /// リスクオンの色
  static const MaterialColor riskOn = Colors.red;

  /// リスクオフの色
  static const MaterialColor riskOff = Colors.green;

  // ============================================================
  // テキストカラー
  // ============================================================

  /// 主要テキスト
  static const Color textPrimary = Colors.black87;

  /// サブテキスト（説明文など）
  static const Color textSecondary = Colors.black54;

  /// 補足テキスト（ラベルなど）
  static const Color textTertiary = Colors.black45;

  /// 無効・グレーアウトテキスト
  static const Color textDisabled = Colors.grey;

  // ============================================================
  // フォントサイズ
  // ============================================================

  /// 極小（補足情報・タイムスタンプ）
  static const double fontXs = 10.0;

  /// 小（ラベル・サブテキスト）
  static const double fontSm = 11.0;

  /// 中小（本文・説明文）
  static const double fontMd = 12.0;

  /// 中（カード内テキスト）
  static const double fontLg = 13.0;

  /// 大（タイトル・強調）
  static const double fontXl = 14.0;

  /// 特大（セクションタイトル）
  static const double fontXxl = 16.0;

  /// 株価表示用
  static const double fontPrice = 28.0;

  // ============================================================
  // 余白（スペーシング）
  // ============================================================

  /// 極小余白（アイコンとテキストの間など）
  static const double spaceXs = 4.0;

  /// 小余白（関連する要素間）
  static const double spaceSm = 8.0;

  /// 中余白（カード内のセクション間）
  static const double spaceMd = 12.0;

  /// 大余白（カード間・セクション間）
  static const double spaceLg = 16.0;

  /// 特大余白（画面のパディング）
  static const double spaceXl = 20.0;

  // ============================================================
  // 角丸（ボーダーレディアス）
  // ============================================================

  /// 小（バッジ・チップ）
  static const double radiusSm = 6.0;

  /// 中（ボタン・入力フィールド）
  static const double radiusMd = 8.0;

  /// 大（カード）
  static const double radiusLg = 10.0;

  /// 特大（モーダル・大きいカード）
  static const double radiusXl = 12.0;

  /// 円形（アバター・アイコンボタン）
  static const double radiusFull = 999.0;

  // ============================================================
  // カードの共通スタイル
  // ============================================================

  /// 標準カードの形状
  static ShapeBorder get cardShape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg));

  /// 大きいカードの形状
  static ShapeBorder get cardShapeLg =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXl));

  // ============================================================
  // バッジの共通スタイル生成
  // 色を渡すと統一されたバッジのDecorationを返す
  // ============================================================

  /// バッジのBoxDecoration（色を引数で渡す）
  ///
  /// 例：AppTheme.badgeDecoration(Colors.red)
  static BoxDecoration badgeDecoration(Color color) => BoxDecoration(
    color: color.withOpacity(0.1),
    borderRadius: BorderRadius.circular(radiusFull),
    border: Border.all(color: color.withOpacity(0.4)),
  );

  /// 小バッジのBoxDecoration
  static BoxDecoration badgeDecorationSm(Color color) => BoxDecoration(
    color: color.withOpacity(0.1),
    borderRadius: BorderRadius.circular(radiusMd),
    border: Border.all(color: color.withOpacity(0.3)),
  );

  // ============================================================
  // ThemeData（MaterialAppに渡す）
  // ============================================================

  /// アプリ全体のThemeData
  static ThemeData get themeData => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: primary),
    useMaterial3: true,
    cardTheme: CardThemeData(shape: cardShape, elevation: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 1,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
    ),
  );
}
