// ============================================================
// EventFilterService
// スケジュール画面で「どのイベントを表示するか」の設定を保存する。
//
// SharedPreferencesに保存するので、アプリを閉じても設定が残る。
// （利用規約の同意フラグ・お知らせの既読管理と同じ仕組み）
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/event_types.dart';

class EventFilterService {
  /// 表示するイベントグループのキーを保存するキー
  static const String _prefsKey = 'schedule_visible_event_groups';

  /// 表示中のイベントグループを取得する
  ///
  /// 未保存（初回起動）の場合は全種別を表示する。
  static Future<Set<String>> getVisibleGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefsKey);
      if (saved == null) return Set<String>.from(kAllEventGroupKeys);

      // 定義から消えたキーが残っていても無視する（アプリ更新対策）
      final valid = saved.where(kAllEventGroupKeys.contains).toSet();
      return valid;
    } catch (e) {
      debugPrint('イベントフィルタ取得エラー: $e');
      return Set<String>.from(kAllEventGroupKeys);
    }
  }

  /// 表示するイベントグループを保存する
  static Future<void> saveVisibleGroups(Set<String> groups) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, groups.toList());
    } catch (e) {
      debugPrint('イベントフィルタ保存エラー: $e');
    }
  }
}
