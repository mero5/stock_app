// ============================================================
// ErrorDialog
// AI分析・ニュース取得などが失敗したときに出すポップアップ。
//
// 以前は「エラーなのに画面に何も出ない」状態があったため、
// 失敗したら必ずこのダイアログで知らせる方針にしている。
//
// ・上段：ユーザー向けの日本語メッセージ（バックエンドの error）
// ・下段：技術的な詳細（error_detail）を折りたたみで表示
//         → 普段は隠れているのでユーザーの邪魔にならない
// ============================================================

import 'package:flutter/material.dart';

class ErrorDialog {
  /// エラーポップアップを表示する
  ///
  /// [message] ユーザー向けの日本語メッセージ
  /// [detail]  技術的な詳細（例外メッセージ等）。nullなら折りたたみ自体を出さない
  /// [title]   ダイアログのタイトル（省略時は「エラー」）
  /// [onRetry] 「再試行」ボタンの処理。nullならボタンを出さない
  static Future<void> show(
    BuildContext context, {
    required String message,
    String? detail,
    String title = 'エラー',
    VoidCallback? onRetry,
  }) async {
    // 非同期処理の後に呼ばれることが多いので、画面が生きているか確認する
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
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
              Text(
                message,
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
              // ── 技術的な詳細（折りたたみ）──
              if (detail != null && detail.isNotEmpty) ...[
                const SizedBox(height: 8),
                Theme(
                  // ExpansionTileの上下の区切り線を消す
                  data: Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      '詳細を表示',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: SelectableText(
                          detail,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: Colors.grey.shade800,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onRetry();
              },
              child: const Text('再試行'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
}
