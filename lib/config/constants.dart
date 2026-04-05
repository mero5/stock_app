class Constants {
  // FastAPI on EC2
  static const String backendUrl = "http://13.114.75.49:8000";

  // Lambda - ウォッチリスト保存
  static const String saveUrl =
      "https://b5srqu1twf.execute-api.ap-northeast-1.amazonaws.com/save";

  // Lambda - ウォッチリスト取得
  static const String getUrl =
      "https://3nbvb44ku4.execute-api.ap-northeast-1.amazonaws.com/get";

  // Lambda - ウォッチリスト削除
  static const String deleteUrl =
      "https://b5srqu1twf.execute-api.ap-northeast-1.amazonaws.com/delete";
}
