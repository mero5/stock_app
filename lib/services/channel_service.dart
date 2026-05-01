// ============================================================
// ChannelService
// YouTubeチャンネルのお気に入り管理を担当するサービスクラス。
//
// チャンネル情報はAWS Lambda + DynamoDBに保存・取得・削除する。
// WatchlistServiceと同じAPI Gatewayを使用しているが
// エンドポイントが異なる（/channels/save・get・delete）。
//
// 保存するチャンネル情報：
// ・id          : YouTubeチャンネルID
// ・title       : チャンネル名
// ・thumbnail   : サムネイルURL
// ・description : チャンネル説明文
// ============================================================

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ChannelService {
  // ============================================================
  // エンドポイント定義
  // WatchlistServiceと同じAPI Gatewayだがパスが異なる
  // ============================================================

  /// チャンネル保存用Lambda エンドポイント
  static const String _saveUrl =
      'https://b5srqu1twf.execute-api.ap-northeast-1.amazonaws.com/channels/save';

  /// チャンネル取得用Lambda エンドポイント
  static const String _getUrl =
      'https://b5srqu1twf.execute-api.ap-northeast-1.amazonaws.com/channels/get';

  /// チャンネル削除用Lambda エンドポイント
  static const String _deleteUrl =
      'https://b5srqu1twf.execute-api.ap-northeast-1.amazonaws.com/channels/delete';

  // ============================================================
  // 取得
  // ============================================================

  /// お気に入りチャンネル一覧をDynamoDBから取得する
  ///
  /// DynamoDBのレスポンス形式（id/channelId）の揺れに対応するため
  /// `id ?? channelId` でどちらのキーでも取得できるようにしている。
  ///
  /// [userId] Cognito のユーザーID
  /// 返り値：チャンネル情報のリスト（取得失敗時は空リスト）
  static Future<List<Map<String, String>>> getChannels(String userId) async {
    debugPrint('チャンネル取得開始 userId: $userId');
    try {
      final res = await http.get(Uri.parse('$_getUrl?userId=$userId'));
      debugPrint('チャンネル取得レスポンス: ${res.statusCode} ${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        // DynamoDBのレスポンスをFlutterで扱いやすい形式に変換
        return List<Map<String, String>>.from(
          (data['channels'] as List).map(
            (c) => {
              // id と channelId の両方に対応（APIの揺れに備える）
              'channel_id': (c['id'] ?? c['channelId'] ?? '') as String,
              'name': c['title'] as String,
              'thumbnail': (c['thumbnail'] ?? '') as String,
              'description': (c['description'] ?? '') as String,
            },
          ),
        );
      }
    } catch (e) {
      debugPrint('チャンネル取得エラー: $e');
    }

    // 通信失敗・ステータスコード異常の場合は空リストを返す
    return [];
  }

  // ============================================================
  // 保存
  // ============================================================

  /// チャンネルをお気に入りとしてDynamoDBに保存する
  ///
  /// すでに保存済みのチャンネルを再保存しても上書きされる（冪等）。
  ///
  /// [userId]  Cognito のユーザーID
  /// [channel] 保存するチャンネル情報
  ///           （channel_id・name・thumbnail・descriptionを含むMap）
  /// 返り値：保存成功ならtrue、失敗ならfalse
  static Future<bool> saveChannel(
    String userId,
    Map<String, String> channel,
  ) async {
    try {
      final res = await http.post(
        Uri.parse(_saveUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'channel': {
            'id': channel['channel_id'],
            'title': channel['name'],
            'thumbnail': channel['thumbnail'] ?? '',
            'description': channel['description'] ?? '',
          },
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('チャンネル保存エラー: $e');
      return false;
    }
  }

  // ============================================================
  // 削除
  // ============================================================

  /// チャンネルをお気に入りからDynamoDBで削除する
  ///
  /// [userId]    Cognito のユーザーID
  /// [channelId] 削除するYouTubeチャンネルID
  /// 返り値：削除成功ならtrue、失敗ならfalse
  static Future<bool> deleteChannel(String userId, String channelId) async {
    try {
      final res = await http.post(
        Uri.parse(_deleteUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'channelId': channelId}),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('チャンネル削除エラー: $e');
      return false;
    }
  }
}
