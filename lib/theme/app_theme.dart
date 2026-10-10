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
//
// デザインの方針（2026-10 刷新）：シンプルで落ち着いた「上質」な見た目
//   ・背景はオフホワイト、文字は黒に近い濃紺。差し色は青（ボタン・選択中）と
//     緑（補助の線・見出し）の2色だけにする
//   ・カードは影を付けず、細い線（ヘアライン）で区切る
//   ・数字は等幅（tabular figures）にして、株価の桁を縦にそろえる
//   ・WebView の画面（backend/web/static/app.css）も同じ色を使う。
//     ここの色を変えたら app.css の :root も合わせて直す
// ============================================================

import 'package:flutter/material.dart';

class AppTheme {
  // ============================================================
  // ベースカラー（背景・面・線）
  // ============================================================

  /// 画面の背景（オフホワイト）
  static const Color background = Color(0xFFFAFAF7);

  /// カード・シート・ヘッダーなどの面
  static const Color surface = Colors.white;

  /// 区切り線・カードの枠線（ヘアライン）
  static const Color hairline = Color(0xFFE6E6E1);

  // ============================================================
  // プライマリカラー（青）・アクセントカラー（緑）
  // ============================================================

  /// アプリのメインカラー（ボタン・選択中・リンク）
  static const MaterialColor primary = MaterialColor(0xFF1D4ED8, {
    50: Color(0xFFEFF4FF),
    100: Color(0xFFDBE6FE),
    200: Color(0xFFBFD3FE),
    300: Color(0xFF93B4FD),
    400: Color(0xFF6090FA),
    500: Color(0xFF1D4ED8),
    600: Color(0xFF1A45C2),
    700: Color(0xFF1E3A8A),
    800: Color(0xFF1B3275),
    900: Color(0xFF172554),
  });

  /// メインカラーの薄い背景版（カードの背景など）
  static const Color primaryLight = Color(0xFFEFF4FF);

  /// 補助の差し色（見出しの線・アクセント）。上昇・下落の色としては使わない
  static const MaterialColor accent = MaterialColor(0xFF047857, {
    50: Color(0xFFECFDF5),
    100: Color(0xFFD1FAE5),
    200: Color(0xFFA7F3D0),
    300: Color(0xFF6EE7B7),
    400: Color(0xFF34D399),
    500: Color(0xFF047857),
    600: Color(0xFF046C4E),
    700: Color(0xFF065F46),
    800: Color(0xFF064E3B),
    900: Color(0xFF053B2D),
  });

  // ============================================================
  // 株価の上昇・下落カラー
  // 日本株の慣例に合わせて上昇=赤・下落=緑
  // 原色だと派手すぎるので、彩度を少し落とした色にしている
  // ============================================================

  static const MaterialColor _red = MaterialColor(0xFFD64545, {
    50: Color(0xFFFDF3F3),
    100: Color(0xFFFBE4E4),
    200: Color(0xFFF6C9C9),
    300: Color(0xFFEFA3A3),
    400: Color(0xFFE47070),
    500: Color(0xFFD64545),
    600: Color(0xFFBF3535),
    700: Color(0xFFA02B2B),
    800: Color(0xFF832727),
    900: Color(0xFF6C2525),
  });

  static const MaterialColor _green = MaterialColor(0xFF1E9E62, {
    50: Color(0xFFEFFAF4),
    100: Color(0xFFD8F3E4),
    200: Color(0xFFB3E6CB),
    300: Color(0xFF80D2AA),
    400: Color(0xFF4BB985),
    500: Color(0xFF1E9E62),
    600: Color(0xFF178452),
    700: Color(0xFF156944),
    800: Color(0xFF145438),
    900: Color(0xFF12452F),
  });

  static const MaterialColor _amber = MaterialColor(0xFFC77D0A, {
    50: Color(0xFFFEF8EC),
    100: Color(0xFFFCEDCC),
    200: Color(0xFFF8D995),
    300: Color(0xFFF2C05D),
    400: Color(0xFFE29F2A),
    500: Color(0xFFC77D0A),
    600: Color(0xFFA86507),
    700: Color(0xFF874E0A),
    800: Color(0xFF6E400E),
    900: Color(0xFF5C360F),
  });

  static const MaterialColor _slate = MaterialColor(0xFF8A9099, {
    50: Color(0xFFF7F7F5),
    100: Color(0xFFEEEFEC),
    200: Color(0xFFDDDFDB),
    300: Color(0xFFC3C6C2),
    400: Color(0xFFA6AAAD),
    500: Color(0xFF8A9099),
    600: Color(0xFF6B717B),
    700: Color(0xFF525862),
    800: Color(0xFF3A3F47),
    900: Color(0xFF23272E),
  });

  /// 上昇・買い・ポジティブを示す色（日本株慣例：赤）
  static const MaterialColor bullish = _red;

  /// 下落・売り・ネガティブを示す色（日本株慣例：緑）
  static const MaterialColor bearish = _green;

  /// 中立・様子見を示す色
  static const MaterialColor neutral = _slate;

  /// 警告・注意を示す色
  static const MaterialColor warning = _amber;

  /// 危険・エラーを示す色
  static const MaterialColor danger = _red;

  // ============================================================
  // セマンティックカラー（意味を持つ色）
  // ============================================================

  /// 信頼度「高」の色
  static const MaterialColor confidenceHigh = _green;

  /// 信頼度「中」の色
  static const MaterialColor confidenceMedium = _amber;

  /// 信頼度「低」の色
  static const MaterialColor confidenceLow = _red;

  /// リスクオンの色
  static const MaterialColor riskOn = _red;

  /// リスクオフの色
  static const MaterialColor riskOff = _green;

  // ============================================================
  // テキストカラー
  // ============================================================

  /// 主要テキスト（黒に近い濃紺）
  static const Color textPrimary = Color(0xFF0B0F14);

  /// サブテキスト（説明文など）
  static const Color textSecondary = Color(0xFF4A5260);

  /// 補足テキスト（ラベルなど）
  static const Color textTertiary = Color(0xFF6E7582);

  /// 無効・グレーアウトテキスト
  static const Color textDisabled = Color(0xFFA6AAAD);

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
  // 影の代わりに細い枠線で区切る
  // ============================================================

  /// 標準カードの形状
  static ShapeBorder get cardShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radiusLg),
    side: const BorderSide(color: hairline),
  );

  /// 大きいカードの形状
  static ShapeBorder get cardShapeLg => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radiusXl),
    side: const BorderSide(color: hairline),
  );

  // ============================================================
  // バッジの共通スタイル生成
  // 色を渡すと統一されたバッジのDecorationを返す
  // ============================================================

  /// バッジのBoxDecoration（色を引数で渡す）
  ///
  /// 例：AppTheme.badgeDecoration(Colors.red)
  static BoxDecoration badgeDecoration(Color color) => BoxDecoration(
    color: color.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(radiusFull),
    border: Border.all(color: color.withValues(alpha: 0.35)),
  );

  /// 小バッジのBoxDecoration
  static BoxDecoration badgeDecorationSm(Color color) => BoxDecoration(
    color: color.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(radiusMd),
    border: Border.all(color: color.withValues(alpha: 0.3)),
  );

  // ============================================================
  // ThemeData（MaterialAppに渡す）
  // ============================================================

  /// 文字の共通設定。数字を等幅にして、株価・騰落率の桁をそろえる
  static TextTheme _textTheme(TextTheme base) {
    TextStyle? tune(TextStyle? style) => style?.copyWith(
      color: textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return base.copyWith(
      displayLarge: tune(base.displayLarge),
      displayMedium: tune(base.displayMedium),
      displaySmall: tune(base.displaySmall),
      headlineLarge: tune(base.headlineLarge),
      headlineMedium: tune(base.headlineMedium),
      headlineSmall: tune(base.headlineSmall),
      titleLarge: tune(base.titleLarge),
      titleMedium: tune(base.titleMedium),
      titleSmall: tune(base.titleSmall),
      bodyLarge: tune(base.bodyLarge),
      bodyMedium: tune(base.bodyMedium),
      bodySmall: tune(base.bodySmall),
      labelLarge: tune(base.labelLarge),
      labelMedium: tune(base.labelMedium),
      labelSmall: tune(base.labelSmall),
    );
  }

  /// アプリ全体のThemeData
  static ThemeData get themeData {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      error: danger,
      surface: surface,
      onSurface: textPrimary,
      outline: hairline,
      outlineVariant: hairline,
    );
    final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMd),
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: _textTheme(base.textTheme),
      dividerColor: hairline,
      dividerTheme: const DividerThemeData(color: hairline, thickness: 1),
      cardTheme: CardThemeData(
        shape: cardShape,
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: hairline)),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textTertiary,
        elevation: 0,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textTertiary,
        indicatorColor: primary,
        dividerColor: hairline,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: buttonShape,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: hairline),
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        side: const BorderSide(color: hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: textPrimary,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      listTileTheme: const ListTileThemeData(iconColor: textSecondary),
    );
  }
}
