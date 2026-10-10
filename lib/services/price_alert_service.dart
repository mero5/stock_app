// ============================================================
// PriceAlertService
// 株価アラートの登録・一覧・変更・削除と、テスト通知の送信。
//
// バックエンドの /alerts・/push/test（backend/routers/price_alerts.py）を呼ぶ。
// この API はログインのトークンが必須（ApiClient が付ける）。userId は送らない
// （バックエンドがトークンの持ち主を使う）。
//
// 失敗したときは PriceAlertException を投げる。メッセージはそのまま画面に出せる日本語。
// ============================================================

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../config/timeouts.dart';
import '../models/price_alert.dart';
import 'api_client.dart';

class PriceAlertException implements Exception {
  final String message;
  const PriceAlertException(this.message);

  @override
  String toString() => message;
}

class PriceAlertService {
  PriceAlertService._();

  /// 1人が登録できる数（backend/config/price_alerts.py の MAX_ALERTS_PER_USER と同じ）
  static const maxAlerts = 10;

  static Uri _uri(String path) => Uri.parse('${Constants.backendUrl}$path');

  /// バックエンドの応答を読む。`error` キーがあれば例外にする
  static Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const PriceAlertException('サーバーから正しい応答がありませんでした');
    }
    final error = body['error'];
    if (error != null) throw PriceAlertException(error.toString());
    return body;
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await ApiClient.post(
        _uri(path),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(AppTimeouts.api);
      return _decode(res);
    } on PriceAlertException {
      rethrow;
    } catch (e) {
      throw PriceAlertException('通信に失敗しました（$e）');
    }
  }

  /// 自分のアラートの一覧（作った順）
  static Future<List<PriceAlert>> list() async {
    try {
      final res = await ApiClient.get(_uri('/alerts')).timeout(AppTimeouts.api);
      final body = _decode(res);
      return (body['alerts'] as List? ?? [])
          .map((e) => PriceAlert.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PriceAlertException {
      rethrow;
    } catch (e) {
      throw PriceAlertException('通信に失敗しました（$e）');
    }
  }

  /// アラートを登録する
  static Future<PriceAlert> create({
    required String code,
    required String name,
    required String condition,
    required double target,
    required String repeat,
  }) async {
    final body = await _post('/alerts', {
      'code': code,
      'name': name,
      'condition': condition,
      'target': target,
      'repeat': repeat,
    });
    return PriceAlert.fromJson(body['alert'] as Map<String, dynamic>);
  }

  /// アラートを変更する（渡した項目だけ変わる）
  static Future<void> update(
    String alertId, {
    bool? enabled,
    String? condition,
    double? target,
    String? repeat,
  }) async {
    await _post('/alerts/update', {
      'alert_id': alertId,
      'enabled': ?enabled,
      'condition': ?condition,
      'target': ?target,
      'repeat': ?repeat,
    });
  }

  /// アラートを削除する
  static Future<void> delete(String alertId) async {
    await _post('/alerts/delete', {'alert_id': alertId});
  }

  /// 自分の全端末にテスト通知を送る
  static Future<void> sendTest() async {
    await _post('/push/test', {});
  }
}
