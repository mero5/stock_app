import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

class WatchlistService {
  // 4桁の数字コードを5桁に正規化（例: 7203 → 72030）
  static String _normalize(String code) {
    final isAllDigits = RegExp(r'^\d+$').hasMatch(code);
    if (isAllDigits && code.length == 4) {
      return '${code}0';
    }
    return code;
  }

  static Future<void> save(List<String> stocks) async {
    final user = await Amplify.Auth.getCurrentUser();
    final normalized = stocks.map(_normalize).toList();
    await http.post(
      Uri.parse(Constants.saveUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"userId": user.userId, "stocks": normalized}),
    );
  }

  static Future<void> delete(String stock) async {
    final user = await Amplify.Auth.getCurrentUser();
    final normalized = _normalize(stock); // ← 追加
    final response = await http.post(
      Uri.parse(Constants.deleteUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"userId": user.userId, "stock": normalized}), // ← 修正
    );
    print("削除レスポンス: ${response.body}");
  }

  static Future<List<String>> getCodes() async {
    final user = await Amplify.Auth.getCurrentUser();
    final response = await http.get(
      Uri.parse("${Constants.getUrl}?userId=${user.userId}"),
    );
    final data = jsonDecode(response.body);
    return data
        .map<String>((item) => _normalize(item['stock'].toString()))
        .toList();
  }
}
