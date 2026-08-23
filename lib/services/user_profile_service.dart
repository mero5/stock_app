// ============================================================
// UserProfileService
// ユーザープロファイルの取得・保存を担当するサービスクラス。
//
// プロファイルはバックエンド（FastAPI on EC2）経由で
// DynamoDBに保存・取得する。
//
// 保存するプロファイル情報：
// ・investment_style : 投資スタイル（短期・中期・長期）
// ・trade_type       : 取引種別（現物のみ・信用も使う）
// ・short_selling    : 空売り（する・しない）
// ・analysis_style   : 分析スタイル（テクニカル重視・バランス型等）
// ・risk_level       : リスク許容度（低・中・高）
// ・experience       : 投資経験（初級・中級・上級）
// ・market           : 対象市場（日本株・米国株・両方）
// ・concentration    : 集中・分散（集中派・分散派）
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';

class UserProfileService {
  // ============================================================
  // 取得
  // ============================================================

  /// ユーザープロファイルをバックエンドから取得する
  ///
  /// プロファイルが存在しない場合（新規ユーザー）はnullを返す。
  /// 通信エラーの場合もnullを返す（エラーは握り潰す）。
  ///
  /// [userId] Cognito のユーザーID
  /// 返り値：プロファイルのMap、未登録またはエラーの場合はnull
  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      final res = await http.get(
        Uri.parse('${Constants.backendUrl}/user/profile?userId=$userId'),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      // 'exists: false' はプロファイル未登録を意味する
      if (data['exists'] == false) return null;

      return data;
    } catch (e) {
      // 通信エラー等はnullを返してUI側でデフォルト値を使う
      debugPrint('プロファイル取得エラー: $e');
      return null;
    }
  }

  // ============================================================
  // 保存
  // ============================================================

  /// ユーザープロファイルをバックエンドに保存する
  ///
  /// 既存のプロファイルがある場合は上書き保存する。
  /// 保存に成功した場合はtrue、失敗した場合はfalseを返す。
  ///
  /// [userId]  Cognito のユーザーID
  /// [profile] 保存するプロファイルのMap
  ///           （investment_style・risk_level等のキーを含む）
  /// 返り値：保存成功ならtrue、失敗ならfalse
  static Future<bool> saveProfile(
    String userId,
    Map<String, dynamic> profile,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('${Constants.backendUrl}/user/profile'),
        headers: {'Content-Type': 'application/json'},
        // userIdとprofileの内容をマージして送信
        body: jsonEncode({'userId': userId, ...profile}),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      // レスポンスの 'success' フィールドで成否を判定
      return data['success'] == true;
    } catch (e) {
      debugPrint('プロファイル保存エラー: $e');
      return false;
    }
  }
}
