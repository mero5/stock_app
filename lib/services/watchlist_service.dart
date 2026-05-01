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

class WatchlistService {
  // ============================================================
  // ユーティリティ
  // ============================================================

  /// 銘柄コードを5桁に正規化する（DynamoDB保存用）
  ///
  /// 日本株は4桁コードの末尾に「0」を付けて5桁にする。
  /// 例：7203 → 72030、9984 → 99840
  /// 米国株（英字）・すでに5桁のコードはそのまま返す。
  static String _normalize(String code) {
    // 数字のみかどうかを判定（日本株かどうかの判断に使う）
    final isAllDigits = RegExp(r'^\d+$').hasMatch(code);

    // 4桁の数字コード（日本株）の場合のみ末尾に0を付ける
    if (isAllDigits && code.length == 4) {
      return '${code}0';
    }

    // 米国株・5桁コードはそのまま返す
    return code;
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
    await http.post(
      Uri.parse(Constants.saveUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': user.userId, 'stocks': normalized}),
    );
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
    );

    // デバッグ用：削除結果をログに出力
    // debugPrintはリリースビルドでは出力されない
    debugPrint('削除レスポンス: ${response.body}');
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
    );

    // レスポンスをパースして銘柄コードのリストに変換
    final data = jsonDecode(response.body);
    return data
        .map<String>((item) => _normalize(item['stock'].toString()))
        .toList();
  }
}
