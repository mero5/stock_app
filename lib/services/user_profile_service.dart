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
import 'dart:convert';
import '../config/constants.dart';
import '../config/timeouts.dart';
import 'api_client.dart';

/// プロファイル取得の結果の種類
enum ProfileFetchStatus {
  /// 登録あり
  found,

  /// 未登録（新規ユーザー）
  notFound,

  /// 通信エラー・バックエンドのエラー（登録されているかは分からない）
  error,
}

/// プロファイル取得の結果。「未登録」と「エラー」を区別するためのもの
class ProfileFetchResult {
  final ProfileFetchStatus status;

  /// [status] が found のときだけ入る
  final Map<String, dynamic>? profile;

  /// [status] が error のときの技術的な詳細（ErrorDialog の detail 用）
  final String? errorDetail;

  const ProfileFetchResult._(this.status, {this.profile, this.errorDetail});

  const ProfileFetchResult.error(String detail)
      : this._(ProfileFetchStatus.error, errorDetail: detail);

  /// `/user/profile` の応答を結果に変換する
  ///
  /// `"exists": false` のときだけ「未登録」にする。
  /// 200 以外・JSON でない・`error` がある・`exists` が無い（Lambda に断られた応答など）は
  /// すべて「エラー」にする。
  factory ProfileFetchResult.fromResponse(int statusCode, String body) {
    if (statusCode != 200) {
      return ProfileFetchResult.error('HTTP $statusCode: $body');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (e) {
      return ProfileFetchResult.error('JSONではない応答: $body');
    }
    if (decoded is! Map<String, dynamic>) {
      return ProfileFetchResult.error('想定外の応答: $body');
    }
    if (decoded['error'] != null) {
      return ProfileFetchResult.error(decoded['error'].toString());
    }
    if (decoded['exists'] == false) {
      return const ProfileFetchResult._(ProfileFetchStatus.notFound);
    }
    if (decoded['exists'] == true) {
      return ProfileFetchResult._(ProfileFetchStatus.found, profile: decoded);
    }
    return ProfileFetchResult.error('exists が無い応答: $body');
  }
}

class UserProfileService {
  // ============================================================
  // 取得
  // ============================================================

  /// ユーザープロファイルを取得し、「登録あり・未登録・エラー」を区別して返す
  ///
  /// 「初回設定に進むか」「既存の値を読み込んでから編集させるか」を決めるときは、
  /// [getProfile] ではなくこちらを使う。[getProfile] はエラーも null（＝未登録）にするため、
  /// 登録済みのユーザーを初回設定に進め、既定値で上書き保存させてしまう（課題 K-36）。
  ///
  /// [userId] Cognito のユーザーID
  static Future<ProfileFetchResult> fetchProfile(String userId) async {
    try {
      final res = await ApiClient.get(
        Uri.parse('${Constants.backendUrl}/user/profile?userId=$userId'),
      ).timeout(AppTimeouts.api);
      return ProfileFetchResult.fromResponse(res.statusCode, res.body);
    } catch (e) {
      debugPrint('プロファイル取得エラー: $e');
      return ProfileFetchResult.error(e.toString());
    }
  }

  /// ユーザープロファイルをバックエンドから取得する（表示用）
  ///
  /// プロファイルが存在しない場合（新規ユーザー）はnullを返す。
  /// 通信エラーの場合もnullを返す（エラーは握り潰す）。
  /// 画面の行き先や保存の判断には使わず、[fetchProfile] を使うこと。
  ///
  /// [userId] Cognito のユーザーID
  /// 返り値：プロファイルのMap、未登録またはエラーの場合はnull
  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    // 未登録・エラーは null を返してUI側でデフォルト値を使う
    final result = await fetchProfile(userId);
    return result.profile;
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
      final res = await ApiClient.post(
        Uri.parse('${Constants.backendUrl}/user/profile'),
        headers: {'Content-Type': 'application/json'},
        // userIdとprofileの内容をマージして送信
        body: jsonEncode({'userId': userId, ...profile}),
      ).timeout(AppTimeouts.api);

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      // レスポンスの 'success' フィールドで成否を判定
      return data['success'] == true;
    } catch (e) {
      debugPrint('プロファイル保存エラー: $e');
      return false;
    }
  }
}
