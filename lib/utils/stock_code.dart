// ============================================================
// 銘柄コードの判定・変換
//
// 日本株の銘柄コードは「4文字」（ウォッチリスト・J-Quantsでは末尾に0を付けた5文字）。
// 2024年1月から東証は、新しく上場する銘柄に英字入りのコードを使っている
// （例：285A キオクシア、130A）。1・3文字目は数字、2・4文字目は数字か英大文字。
//
// 以前は「数字だけかどうか」で日本株を判定していたため、英字入りのコードが
// 米国株として扱われ、4文字表示・削除・AI診断がうまく動かなかった。
// 日本株かどうかの判定と変換は、必ずこのファイルの関数を使うこと。
// （バックエンドの backend/services/stock_code.py と同じルール）
//
//   ウォッチリスト（DynamoDB） : 72030 / 285A0   （5文字）
//   画面表示                   : 7203  / 285A    （4文字）
//   yfinance                   : 7203.T / 285A.T
// ============================================================

class StockCode {
  StockCode._();

  // 米国株のティッカーは数字で始まらないので、1文字目が数字かどうかで区別できる
  static final RegExp _jp4 = RegExp(r'^[0-9][0-9A-Z][0-9][0-9A-Z]$');
  static final RegExp _jp5 = RegExp(r'^[0-9][0-9A-Z][0-9][0-9A-Z][0-9]$');

  /// 日本株の銘柄コード（4文字または5文字。英字入りも含む）なら true
  static bool isJp(String code) => _jp4.hasMatch(code) || _jp5.hasMatch(code);

  /// 画面表示用（日本株の5文字は4文字にする。それ以外はそのまま）
  static String display(String code) =>
      _jp5.hasMatch(code) ? code.substring(0, 4) : code;

  /// ウォッチリスト保存用（日本株の4文字は末尾に0を付けて5文字にする）
  static String storage(String code) => _jp4.hasMatch(code) ? '${code}0' : code;

  /// yfinance 用（日本株は4文字＋.T、それ以外はそのまま）
  static String ticker(String code) =>
      isJp(code) ? '${code.substring(0, 4)}.T' : code;
}
