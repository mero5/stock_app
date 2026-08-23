// ============================================================
// NoticeDialog
// アップデート内容を知らせるポップアップ。
//
// 「もう読んだか」はSharedPreferencesに保存する。
// 利用規約の同意フラグ（terms_agreed）と同じ仕組み。
//
// 表示内容は config/release_notes.dart に分離している。
// ============================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/release_notes.dart';

class NoticeDialog {
  /// 最後に表示した告知バージョンを保存するキー
  static const String _prefsKey = 'last_seen_notice_version';

  /// 未読の告知があればポップアップを表示する
  ///
  /// 保存済みバージョンが最新以上の場合は何もしない。
  /// 表示して閉じられた時点で既読として記録する。
  static Future<void> showIfUnread(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getInt(_prefsKey) ?? 0;
    if (lastSeen >= kLatestNoticeVersion) return;

    // await をまたいでいるので、画面がまだ生きているか確認する
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.campaign, color: Colors.blue, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                kNoticeTitle,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...kNoticeBody.map(
                (text) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '・',
                        style: TextStyle(fontSize: 13, height: 1.5),
                      ),
                      Expanded(
                        child: Text(
                          text,
                          style: const TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 20),
              Text(
                kNoticeFooter,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );

    await markAsRead();
  }

  /// 現在の告知を既読として記録する
  ///
  /// ポップアップを出さずに既読扱いにしたい場合にも使う。
  /// （初回プロフィール設定を終えた新規ユーザーなど、
  ///   「新しくなりました」と伝える意味がない場合）
  static Future<void> markAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, kLatestNoticeVersion);
  }
}
