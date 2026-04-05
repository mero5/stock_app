import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

class WatchlistService {
  static Future<void> save(List<String> stocks) async {
    final user = await Amplify.Auth.getCurrentUser();
    await http.post(
      Uri.parse(Constants.saveUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"userId": user.userId, "stocks": stocks}),
    );
  }

  static Future<void> delete(String stock) async {
    final user = await Amplify.Auth.getCurrentUser();
    final response = await http.delete(
      Uri.parse(Constants.deleteUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"userId": user.userId, "stock": stock}),
    );
    print("削除レスポンス: ${response.body}");
  }

  static Future<List<String>> getCodes() async {
    final user = await Amplify.Auth.getCurrentUser();
    final response = await http.get(
      Uri.parse("${Constants.getUrl}?userId=${user.userId}"),
    );
    final data = jsonDecode(response.body);
    return data.map<String>((item) => item['stock'].toString()).toList();
  }
}
