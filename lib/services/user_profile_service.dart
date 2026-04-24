import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';

class UserProfileService {
  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      final res = await http.get(
        Uri.parse("${Constants.backendUrl}/user/profile?userId=$userId"),
      );
      final data = jsonDecode(res.body);
      if (data['exists'] == false) return null;
      return data;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> saveProfile(
    String userId,
    Map<String, dynamic> profile,
  ) async {
    try {
      final res = await http.post(
        Uri.parse("${Constants.backendUrl}/user/profile"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"userId": userId, ...profile}),
      );
      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }
}
