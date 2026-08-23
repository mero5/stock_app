// ============================================================
// NoticeDialog
// アップデート告知のポップアップ。
//
// 告知の内容はバックエンド（/notices）から取得する。
// アプリを更新しなくても告知を出せるようにするため。
//
// 未読が複数溜まっている場合は、古い順に1件ずつ表示する。
//
// ★連続表示で壊さないための決まりごと★
//   1. showDialog を必ず await する
//      → 前のダイアログが完全に閉じてから次を出す。
//        awaitせずに連続で呼ぶと、Navigatorのスタックが壊れて
//        黒画面や例外になる。
//   2. 1件出すたびに context.mounted を確認する
//      → 表示中に画面が破棄された場合はそこで打ち切る。
//   3. 1件閉じるごとに既読を保存する
//      → 途中でアプリを閉じても、残りは次回また表示される。
//   4. 「残り◯件」を出す
//      → 続けてポップアップが出る理由がユーザーに分かるようにする。
// ============================================================

import 'package:flutter/material.dart';

import '../services/notice_service.dart';

class NoticeDialog {
  /// 未読の告知があれば、古い順に1件ずつ表示する
  ///
  /// 通信に失敗した場合は何も表示せず、既読も更新しない。
  /// （次回オンライン時に改めて表示される）
  static Future<void> showIfUnread(BuildContext context) async {
    final notices = await NoticeService.fetchUnread();
    if (notices.isEmpty) return;

    for (var i = 0; i < notices.length; i++) {
      // 通信や前のダイアログの待ち時間の間に画面が消えている可能性がある
      if (!context.mounted) return;

      final notice = notices[i];
      final remaining = notices.length - i - 1;

      // await することで、閉じきってから次のループに進む
      await _showOne(context, notice, remaining: remaining);

      // 1件ごとに既読化する。
      // ここでまとめて保存しないのは、途中でアプリを閉じられたときに
      // 未読の告知まで既読になってしまうのを防ぐため。
      await NoticeService.saveLastSeenVersion(notice.version);
    }
  }

  /// 告知を1件表示する
  static Future<void> _showOne(
    BuildContext context,
    Notice notice, {
    int remaining = 0,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.campaign, color: Colors.blue, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notice.title,
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
              ...buildNoticeBody(notice),
              if (notice.footer.isNotEmpty) ...[
                const Divider(height: 20),
                Text(
                  notice.footer,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          // 続けて別の告知が出ることを先に伝えておく
          if (remaining > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '他に$remaining件のお知らせがあります',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(remaining > 0 ? '次へ' : '閉じる'),
          ),
        ],
      ),
    );
  }

  /// 告知の本文（セクション＋箇条書き）を組み立てる
  ///
  /// お知らせ履歴画面でも同じ見た目にしたいので共有している。
  static List<Widget> buildNoticeBody(Notice notice) {
    final widgets = <Widget>[];

    for (final section in notice.sections) {
      if (section.heading.isNotEmpty) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              top: widgets.isEmpty ? 0 : 10,
              bottom: 6,
            ),
            child: Text(
              section.heading,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
        );
      }
      for (final item in section.items) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('・', style: TextStyle(fontSize: 13, height: 1.5)),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return widgets;
  }

  /// 全ての告知を既読として記録する
  ///
  /// ポップアップを出さずに既読扱いにしたい場合に使う。
  /// （初回プロフィール設定を終えた新規ユーザーなど、
  ///   「新しくなりました」と伝える意味がない場合）
  static Future<void> markAsRead() => NoticeService.markAllAsRead();
}
