// ============================================================
// NoticeService
// アップデート告知の取得と、既読バージョンの管理。
//
// 告知の内容はバックエンド（/notices）から取得する。
// アプリを更新しなくても告知を出せるようにするため。
//
// 既読バージョンはSharedPreferencesに保存する。
// キーは以前と同じものを使っているので、
// 既にv1を読んだユーザーに再表示されることはない。
// ============================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';

/// 告知1件
class Notice {
  /// 告知のバージョン（既読管理に使う通し番号）
  final int version;

  /// 告知日（YYYY-MM-DD）
  final String date;

  /// タイトル
  final String title;

  /// 本文。見出し付きのセクションの配列
  final List<NoticeSection> sections;

  /// 本文の下に添える補足
  final String footer;

  const Notice({
    required this.version,
    required this.date,
    required this.title,
    required this.sections,
    required this.footer,
  });

  factory Notice.fromMap(Map<String, dynamic> map) {
    final rawSections = map['sections'] as List? ?? [];
    return Notice(
      version: (map['version'] as num?)?.toInt() ?? 0,
      date: map['date']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      sections: rawSections
          .whereType<Map>()
          .map((s) => NoticeSection.fromMap(Map<String, dynamic>.from(s)))
          .toList(),
      footer: map['footer']?.toString() ?? '',
    );
  }
}

/// 告知本文の1セクション（見出し＋箇条書き）
class NoticeSection {
  /// 見出し。空文字の場合は見出しなしで箇条書きだけ表示する
  final String heading;

  /// 箇条書きの項目
  final List<String> items;

  const NoticeSection({required this.heading, required this.items});

  factory NoticeSection.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as List? ?? [];
    return NoticeSection(
      heading: map['heading']?.toString() ?? '',
      items: rawItems.map((e) => e.toString()).toList(),
    );
  }
}

class NoticeService {
  /// 既読バージョンの保存キー
  ///
  /// 以前のNoticeDialogと同じキーを使っている。
  /// 変えてしまうと、既に読んだユーザーにv1が再表示されるため。
  static const String _prefsKey = 'last_seen_notice_version';

  // ============================================================
  // 既読バージョン
  // ============================================================

  /// 保存されている既読バージョンを返す（未読なら0）
  static Future<int> getLastSeenVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_prefsKey) ?? 0;
    } catch (e) {
      debugPrint('既読バージョン取得エラー: $e');
      return 0;
    }
  }

  /// 既読バージョンを保存する
  ///
  /// 巻き戻さないよう、保存済みより小さい値では上書きしない。
  /// （複数の告知を1件ずつ既読化していく途中で
  ///   古い値を書いてしまうと、同じ告知が再表示されてしまう）
  static Future<void> saveLastSeenVersion(int version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_prefsKey) ?? 0;
      if (version > current) {
        await prefs.setInt(_prefsKey, version);
      }
    } catch (e) {
      debugPrint('既読バージョン保存エラー: $e');
    }
  }

  // ============================================================
  // 告知の取得
  // ============================================================

  /// 未読の告知を古い順に取得する
  ///
  /// 通信に失敗した場合は空リストを返す（何も表示しない）。
  /// 既読バージョンは更新しないので、次回オンライン時に改めて表示される。
  static Future<List<Notice>> fetchUnread() async {
    final lastSeen = await getLastSeenVersion();
    return _fetch(since: lastSeen);
  }

  /// 全ての告知を取得する（お知らせ履歴の表示用）
  static Future<List<Notice>> fetchAll() async {
    return _fetch(since: 0);
  }

  static Future<List<Notice>> _fetch({required int since}) async {
    try {
      final res = await http
          .get(Uri.parse('${Constants.backendUrl}/notices?since=$since'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        debugPrint('告知取得エラー: HTTP ${res.statusCode}');
        return [];
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['notices'] as List? ?? [];
      final notices = list
          .whereType<Map>()
          .map((n) => Notice.fromMap(Map<String, dynamic>.from(n)))
          .toList();
      // バックエンドは古い順で返すが、念のため並べ直す
      notices.sort((a, b) => a.version.compareTo(b.version));
      return notices;
    } catch (e) {
      debugPrint('告知取得エラー: $e');
      return [];
    }
  }

  /// 全ての告知を既読にする
  ///
  /// 新規ユーザーに「新しくなりました」と伝える意味はないため、
  /// 初回プロフィール設定の完了時に呼ぶ。
  static Future<void> markAllAsRead() async {
    try {
      final res = await http
          .get(Uri.parse('${Constants.backendUrl}/notices?since=0'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final latest = (data['latest_version'] as num?)?.toInt() ?? 0;
      await saveLastSeenVersion(latest);
    } catch (e) {
      debugPrint('既読化エラー: $e');
    }
  }
}
