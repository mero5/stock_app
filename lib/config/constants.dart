class Constants {
  // FastAPI on Lambda（Function URL）。旧: EC2 http://13.114.75.49:8000
  static const String backendUrl =
      "https://pcg3tt7tmvzye4pwh3mqkfdjs40muver.lambda-url.ap-northeast-1.on.aws";

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
