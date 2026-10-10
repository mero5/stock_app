// ============================================================
// 通信のタイムアウト（これ以上は待たない時間）
//
// Dart の http パッケージは、タイムアウトを指定しないと
// サーバーが応答するまでいつまでも待つ。バックエンド（Lambda）は
// 最大15分で打ち切られるので、最悪15分「読み込み中」のまま止まる。
// 通信には必ずどちらかを付けること：
//   `await ApiClient.get(...).timeout(AppTimeouts.api)`
//
// バックエンド側の値は backend/config/timeouts.py にある。
// アプリ側はそれより長くして、バックエンドのエラーを先に受け取れるようにする。
// ============================================================

class AppTimeouts {
  AppTimeouts._();

  /// 通常のAPI（株価・詳細・検索・ウォッチリスト・スケジュールなど）
  ///
  /// Lambda の起動（コールドスタート）に数秒、銘柄マスタの取り直しで
  /// J-Quants を最大35秒（backend/config/timeouts.py の JQUANTS_TIMEOUT）待つことがあるので、
  /// それより長くしている。
  static const Duration api = Duration(seconds: 40);

  /// AI を使うAPI（AI分析・相談・相場解説・YouTube要約など）
  ///
  /// バックエンドは OpenAI を90秒、Gemini を60秒で打ち切るので、それより長くしている。
  static const Duration ai = Duration(seconds: 120);
}
