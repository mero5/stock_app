// ============================================================
// WatchlistService
// ウォッチリストの保存・取得・削除を担当するサービスクラス。
//
// データの保存先はAWS Lambda + DynamoDB。
// Amplify Authでログイン中のユーザーIDを取得して
// ユーザーごとにウォッチリストを管理する。
//
// 銘柄コードの正規化ルール：
// ・DynamoDB保存時は5桁（例：72030）
// ・画面表示時は4桁（例：7203）
// ・米国株（英字）はそのまま（例：AAPL）
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../utils/stock_code.dart';
import '../config/timeouts.dart';

class WatchlistService {
  // ============================================================
  // ユーティリティ
  // ============================================================

  /// 銘柄コードを5桁に正規化する（DynamoDB保存用）
  ///
  /// 日本株は4桁コードの末尾に「0」を付けて5桁にする。
  /// 例：7203 → 72030、9984 → 99840、285A → 285A0（英字入りのコード）
  /// 米国株（英字）・すでに5桁のコードはそのまま返す。
  static String _normalize(String code) => StockCode.storage(code);

  /// Lambda の応答が成功（HTTP 2xx）でなければ例外を投げる
  ///
  /// 以前は応答を確認していなかったため、保存・削除に失敗しても
  /// 画面上は成功したように見えていた（追加したのに一覧に出ない・削除したのに残る）。
  static void _checkResponse(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw WatchlistException(
      'ウォッチリストの$actionに失敗しました。時間をおいてもう一度お試しください。',
      'HTTP ${response.statusCode}: ${response.body}',
    );
  }

  // ============================================================
  // 保存
  // ============================================================

  /// ウォッチリスト全体をDynamoDBに保存する
  ///
  /// 既存のリストを上書きする形で保存する（差分更新ではない）。
  /// 銘柄コードは5桁に正規化してから送信する。
  ///
  /// [stocks] 保存する銘柄コードのリスト（4桁または5桁）
  static Future<void> save(List<String> stocks) async {
    // ログイン中のユーザー情報を取得
    final user = await Amplify.Auth.getCurrentUser();

    // 全コードを5桁に正規化
    final normalized = stocks.map(_normalize).toList();

    // LambdaにPOSTして保存
    final response = await http.post(
      Uri.parse(Constants.saveUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': user.userId, 'stocks': normalized}),
    ).timeout(AppTimeouts.api);
    _checkResponse(response, '保存');
  }

  // ============================================================
  // 削除
  // ============================================================

  /// 指定した銘柄をウォッチリストから削除する
  ///
  /// DynamoDBから該当の銘柄コードのみを削除する。
  /// 銘柄コードは5桁に正規化してから送信する。
  ///
  /// [stock] 削除する銘柄コード（4桁または5桁）
  static Future<void> delete(String stock) async {
    // ログイン中のユーザー情報を取得
    final user = await Amplify.Auth.getCurrentUser();

    // コードを5桁に正規化（DynamoDBのキーと一致させるため）
    final normalized = _normalize(stock);

    // LambdaにPOSTして削除
    final response = await http.post(
      Uri.parse(Constants.deleteUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': user.userId, 'stock': normalized}),
    ).timeout(AppTimeouts.api);

    // デバッグ用：削除結果をログに出力
    // debugPrintはリリースビルドでは出力されない
    debugPrint('削除レスポンス: ${response.body}');
    _checkResponse(response, '削除');
  }

  // ============================================================
  // 取得
  // ============================================================

  /// DynamoDBからウォッチリストの銘柄コード一覧を取得する
  ///
  /// レスポンスの銘柄コードは5桁で返ってくるが、
  /// 正規化処理を通すことでフォーマットを統一して返す。
  ///
  /// 返り値：銘柄コードの一覧（5桁の日本株・英字の米国株）
  static Future<List<String>> getCodes() async {
    // ログイン中のユーザー情報を取得
    final user = await Amplify.Auth.getCurrentUser();

    // LambdaにGETリクエストを送信
    final response = await http.get(
      Uri.parse('${Constants.getUrl}?userId=${user.userId}'),
    ).timeout(AppTimeouts.api);

    // レスポンスをパースして銘柄コードのリストに変換
    final data = jsonDecode(response.body);
    return data
        .map<String>((item) => _normalize(item['stock'].toString()))
        .toList();
  }
}

/// ウォッチリストの保存・削除に失敗したときの例外
///
/// [message] ユーザー向けの日本語メッセージ（ErrorDialog の上段）
/// [detail]  技術的な詳細（ErrorDialog の折りたたみ）
class WatchlistException implements Exception {
  final String message;
  final String detail;

  WatchlistException(this.message, this.detail);

  @override
  String toString() => '$message ($detail)';
}
