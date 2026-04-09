import 'dart:convert';
import 'package:http/http.dart' as http;

class ChannelService {
  // ウォッチリスト保存と同じAPI Gatewayのベース（エンドポイントを追加してください）
  static const String _saveUrl =
      'https://b5srqu1twf.execute-api.ap-northeast-1.amazonaws.com/channels/save';
  static const String _getUrl =
      'https://b5srqu1twf.execute-api.ap-northeast-1.amazonaws.com/channels/get';
  static const String _deleteUrl =
      'https://b5srqu1twf.execute-api.ap-northeast-1.amazonaws.com/channels/delete';

  /// チャンネル一覧をDynamoDBから取得
  static Future<List<Map<String, String>>> getChannels(String userId) async {
    print('🔍 getChannels userId: $userId'); // ← 追加
    try {
      final res = await http.get(Uri.parse('$_getUrl?userId=$userId'));
      print('🔍 response: ${res.statusCode} ${res.body}'); // ← 追加
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return List<Map<String, String>>.from(
          (data['channels'] as List).map(
            (c) => {
              'channel_id': c['channelId'] as String,
              'name': c['title'] as String,
              'thumbnail': (c['thumbnail'] ?? '') as String,
              'description': (c['description'] ?? '') as String,
            },
          ),
        );
      }
    } catch (e) {
      print('チャンネル取得エラー: $e');
    }
    return [];
  }

  /// チャンネルをDynamoDBに保存
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
      print('チャンネル保存エラー: $e');
      return false;
    }
  }

  /// チャンネルをDynamoDBから削除
  static Future<bool> deleteChannel(String userId, String channelId) async {
    try {
      final res = await http.post(
        Uri.parse(_deleteUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'channelId': channelId}),
      );
      return res.statusCode == 200;
    } catch (e) {
      print('チャンネル削除エラー: $e');
      return false;
    }
  }
}
