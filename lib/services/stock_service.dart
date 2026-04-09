import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/stock.dart';

class StockService {
  // 銘柄名取得
  static Future<String> getName(String code) async {
    try {
      final res = await http.get(
        Uri.parse(
          "${Constants.backendUrl}/stock/name?code=${Uri.encodeComponent(code)}",
        ),
      );
      final data = jsonDecode(res.body);
      return data['name']?.toString() ?? code;
    } catch (_) {
      return code;
    }
  }

  // 株価・前日比取得
  static Future<Map<String, dynamic>> getPrice(String code) async {
    try {
      final res = await http.get(
        Uri.parse(
          "${Constants.backendUrl}/stock/price?code=${Uri.encodeComponent(code)}",
        ),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {};
    }
  }

  // 詳細取得（チャート・RSI・PER・PBR）
  static Future<Map<String, dynamic>> getDetail(String code) async {
    final res = await http.get(
      Uri.parse(
        "${Constants.backendUrl}/stock/detail?code=${Uri.encodeComponent(code)}",
      ),
    );
    return jsonDecode(res.body);
  }

  // 銘柄検索
  static Future<List<Map<String, String>>> search(String keyword) async {
    final res = await http.get(
      Uri.parse(
        "${Constants.backendUrl}/search?q=${Uri.encodeComponent(keyword)}",
      ),
    );
    final List data = jsonDecode(res.body);
    return data
        .map<Map<String, String>>(
          (e) => {
            "code": e["code"].toString(),
            "name": e["name"].toString(),
            "market": e["market"].toString(),
          },
        )
        .toList();
  }

  // YouTubeチャンネル検索
  static Future<List<Map<String, String>>> searchChannels(String query) async {
    try {
      final res = await http.get(
        Uri.parse(
          "${Constants.backendUrl}/channels/search?q=${Uri.encodeComponent(query)}",
        ),
      );
      final List data = jsonDecode(res.body);
      return data
          .map<Map<String, String>>(
            (e) => {
              "channel_id": e["channel_id"].toString(),
              "name": e["name"].toString(),
              "description": e["description"].toString(),
              "thumbnail": e["thumbnail"].toString(),
            },
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  // EC2に字幕を送って要約
  static Future<String> summarize(String title, String transcript) async {
    try {
      final res = await http.post(
        Uri.parse("${Constants.backendUrl}/summarize"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"title": title, "transcript": transcript}),
      );
      final data = jsonDecode(res.body);
      return data["summary"] ?? "要約できませんでした";
    } catch (e) {
      return "エラーが発生しました: $e";
    }
  }

  // ウォッチリスト用：コードから Stock オブジェクトを生成
  static Future<Stock> getStockInfo(String code) async {
    String name = code;
    String price = "---";
    String change = "";
    String changePct = "";
    bool isPositive = true;

    try {
      name = await getName(code);
      final priceData = await getPrice(code);
      if (priceData['price'] != null) {
        price = (priceData['price'] as num).toStringAsFixed(0);
      }
      if (priceData['change'] != null) {
        final c = priceData['change'] as num;
        final cp = priceData['change_pct'] as num;
        isPositive = c >= 0;
        change = c >= 0 ? "+${c.toStringAsFixed(1)}" : c.toStringAsFixed(1);
        changePct = cp >= 0
            ? "+${cp.toStringAsFixed(2)}%"
            : "${cp.toStringAsFixed(2)}%";
      }
    } catch (_) {}

    return Stock(
      code: code,
      name: name,
      price: price,
      change: change,
      changePct: changePct,
      isPositive: isPositive,
    );
  }

  static Future<Map<String, dynamic>> getAiAnalysis(String code) async {
    final res = await http.get(
      Uri.parse("${Constants.backendUrl}/stock/ai_analysis?code=$code"),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
