// ============================================================
// ProfileFetchResult.fromResponse
// /user/profile の応答を「登録あり・未登録・エラー」に分ける
//
// 以前はエラーも「未登録」扱いで、登録済みのユーザーが初回設定に進み、
// 既定値で上書き保存しうる状態だった（課題 K-36）。
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_app/services/user_profile_service.dart';

void main() {
  test('exists: true は登録あり', () {
    final r = ProfileFetchResult.fromResponse(
        200, '{"exists": true, "userId": "u1", "risk_level": "高"}');
    expect(r.status, ProfileFetchStatus.found);
    expect(r.profile?['risk_level'], '高');
  });

  test('exists: false だけが未登録', () {
    final r = ProfileFetchResult.fromResponse(200, '{"exists": false}');
    expect(r.status, ProfileFetchStatus.notFound);
    expect(r.profile, isNull);
  });

  test('バックエンドのエラー（error あり）はエラー', () {
    final r = ProfileFetchResult.fromResponse(
        200, '{"error": "DynamoDB throttled"}');
    expect(r.status, ProfileFetchStatus.error);
    expect(r.errorDetail, 'DynamoDB throttled');
  });

  test('古いバックエンドの error + exists: false もエラー', () {
    final r = ProfileFetchResult.fromResponse(
        200, '{"error": "DynamoDB throttled", "exists": false}');
    expect(r.status, ProfileFetchStatus.error);
  });

  test('Lambda に断られた応答（exists が無い）はエラー', () {
    final r = ProfileFetchResult.fromResponse(
        200, '{"Reason": "ConcurrentInvocationLimitExceeded"}');
    expect(r.status, ProfileFetchStatus.error);
  });

  test('200 以外はエラー', () {
    final r = ProfileFetchResult.fromResponse(
        502, '{"message": "Internal server error"}');
    expect(r.status, ProfileFetchStatus.error);
  });

  test('JSON でない応答はエラー', () {
    final r = ProfileFetchResult.fromResponse(200, '<html>');
    expect(r.status, ProfileFetchStatus.error);
  });
}
