// ============================================================
// ApiClient
// バックエンド・Lambda への通信の共通部品。
//
// ログイン中なら、メインのバックエンド（Constants.backendUrl）宛ての通信にだけ
// Cognito のアクセストークンを Authorization ヘッダー（"Bearer xxx"）に付けて送る。
// バックエンドはこれで「本当にログインしている本人か」を確かめる
// （backend/config/auth.py・services/auth.py）。
//
// 以前は何も付けずに送っていたため、URL さえ分かれば誰でも API を呼べた（課題 K-06）。
// 通信は http.get / http.post を直接呼ばず、必ずこのクラスを使うこと：
//   await ApiClient.get(uri).timeout(AppTimeouts.api)
//
// ※ ウォッチリスト・チャンネルの Lambda（API Gateway）には、まだ付けない。
//   Web版では Authorization ヘッダーを付けるとブラウザが CORS の事前確認をするが、
//   API Gateway 側がこのヘッダーを許可しているか未確認のため（段階3で AWS の設定と一緒に扱う）。
// ※ http パッケージの runWithClient（全体の差し替え）は、Flutter では
//   コールバックが同じ Zone で動く保証がなく効かないことがあるため使わない。
// ============================================================

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/constants.dart';
import 'auth_service.dart';

class ApiClient {
  ApiClient._();

  /// GET。[headers] にトークンを足して送る
  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    return http.get(url, headers: await _withAuth(url, headers));
  }

  /// POST。[headers] にトークンを足して送る
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    return http.post(
      url,
      headers: await _withAuth(url, headers),
      body: body,
      encoding: encoding,
    );
  }

  /// バックエンド宛てなら、ヘッダーにアクセストークンを足す。
  /// 未ログイン・取得失敗なら付けずに返す
  /// （段階1ではバックエンドはトークンが無くても拒否しないので、今までどおり動く）
  static Future<Map<String, String>> _withAuth(
    Uri url,
    Map<String, String>? headers,
  ) async {
    final merged = <String, String>{...?headers};
    if (!isBackend(url)) return merged;
    final token = await AuthService.getAccessToken();
    if (token != null) merged['Authorization'] = 'Bearer $token';
    return merged;
  }

  /// メインのバックエンド（Constants.backendUrl）宛ての通信なら true
  static bool isBackend(Uri url) =>
      url.toString().startsWith(Constants.backendUrl);
}
