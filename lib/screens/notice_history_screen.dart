// ============================================================
// NoticeHistoryScreen
// これまでのアップデート告知を一覧で見返せる画面。
//
// ポップアップを閉じてしまっても、ここから読み直せる。
// 内容はバックエンド（/notices）から取得するので、
// ポップアップと常に同じものが表示される。
// ============================================================

import 'package:flutter/material.dart';

import '../services/notice_service.dart';
import '../widgets/notice_dialog.dart';

class NoticeHistoryScreen extends StatefulWidget {
  const NoticeHistoryScreen({super.key});

  @override
  State<NoticeHistoryScreen> createState() => _NoticeHistoryScreenState();
}

class _NoticeHistoryScreenState extends State<NoticeHistoryScreen> {
  List<Notice> _notices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final notices = await NoticeService.fetchAll();
    if (!mounted) return;
    setState(() {
      // 履歴は新しいものを上に出す
      _notices = notices.reversed.toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お知らせ履歴'),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notices.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'お知らせを取得できませんでした。\n'
                  '通信状況を確認してもう一度お試しください。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _notices.length,
              itemBuilder: (context, index) => _buildCard(_notices[index]),
            ),
    );
  }

  Widget _buildCard(Notice notice) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.campaign, color: Colors.blue, size: 20),
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
            if (notice.date.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  notice.date,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...NoticeDialog.buildNoticeBody(notice),
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
    );
  }
}
