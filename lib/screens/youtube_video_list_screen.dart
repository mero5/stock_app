// ============================================================
// YoutubeVideoListScreen
// YouTubeチャンネルの動画一覧を表示する画面。
//
// 担当する処理：
// ・チャンネルの最新動画一覧をバックエンドから取得
// ・動画の要約をAI（Gemini 2.5 Flash）で実行
// ・要約済み動画はメモリキャッシュに保持（画面内のみ有効）
// ・要約中は戻るボタンを無効化して誤操作を防ぐ
//
// 遷移元：YoutubeScreen（チャンネル一覧）
// 遷移先：YoutubeDetailScreen（要約詳細）
// ============================================================

import 'package:flutter/material.dart';
import '../services/stock_service.dart';
import '../config/constants.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'youtube_detail_screen.dart';

class YoutubeVideoListScreen extends StatefulWidget {
  /// 表示するチャンネルの情報
  /// channel_id・name・thumbnail・descriptionを含むMap
  final Map<String, String> channel;

  const YoutubeVideoListScreen({super.key, required this.channel});

  @override
  State<YoutubeVideoListScreen> createState() => _YoutubeVideoListScreenState();
}

class _YoutubeVideoListScreenState extends State<YoutubeVideoListScreen> {
  // ============================================================
  // 状態変数
  // ============================================================

  /// 取得した動画一覧
  List<Map<String, dynamic>> _videos = [];

  /// 動画一覧の取得中フラグ
  bool _isLoading = true;

  /// 現在要約中の動画ID（nullの場合は要約していない）
  String? _summarizingId;

  /// 要約済みデータのメモリキャッシュ
  /// key: video_id、value: 要約データのMap
  /// 同じ動画を再度タップした時にAPIを叩かずキャッシュから返す
  final Map<String, Map<String, dynamic>> _summaryCache = {};

  // ============================================================
  // ライフサイクル
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  // ============================================================
  // データ取得
  // ============================================================

  /// チャンネルの最新動画一覧をバックエンドから取得する
  Future<void> _loadVideos() async {
    final videos = await StockService.getChannelVideos(
      widget.channel['channel_id']!,
    );
    setState(() {
      _videos = videos;
      _isLoading = false;
    });
  }

  // ============================================================
  // AI要約
  // ============================================================

  /// 動画をAIで要約して詳細画面に遷移する
  ///
  /// 処理の流れ：
  /// 1. キャッシュに要約済みデータがあればそのまま詳細画面へ
  /// 2. なければバックエンドに要約リクエストを送信
  /// 3. 結果をキャッシュに保存して詳細画面へ遷移
  ///
  /// [video] 要約する動画のデータ（video_id・title・description等）
  Future<void> _summarize(Map<String, dynamic> video) async {
    // キャッシュヒット：APIを叩かずに詳細画面へ遷移
    if (_summaryCache.containsKey(video['video_id'])) {
      _openDetail(_summaryCache[video['video_id']]!);
      return;
    }

    // 要約開始：このvideo_idのローディング状態をセット
    setState(() => _summarizingId = video['video_id']);

    try {
      final videoUrl = 'https://www.youtube.com/watch?v=${video["video_id"]}';

      // バックエンドに要約リクエストを送信
      // titleとdescription（字幕の代わり）をAIに渡す
      final res = await http.post(
        Uri.parse('${Constants.backendUrl}/summarize'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': video['title'],
          'url': videoUrl,
          'transcript': video['description'] ?? '',
        }),
      );

      final data = jsonDecode(res.body);

      // 要約結果に画面表示用の追加情報をマージ
      final summaryData = <String, dynamic>{
        'channel_name': widget.channel['name'],
        'title': video['title'],
        'url': videoUrl,
        'published_at': video['published_at'] ?? '',
        ...data, // AIの要約結果（summary・sentiment・topics等）
      };

      // メモリキャッシュに保存（同じ動画の再要約を防ぐ）
      _summaryCache[video['video_id']] = summaryData;
      setState(() {});

      // 要約完了後に詳細画面へ遷移
      if (mounted) _openDetail(summaryData);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('要約に失敗しました: $e')));
      }
    } finally {
      // 成功・失敗どちらでもローディングを終了
      if (mounted) setState(() => _summarizingId = null);
    }
  }

  // ============================================================
  // 画面遷移
  // ============================================================

  /// 要約詳細画面へ遷移する
  ///
  /// [summary] 要約データ（_summaryCache から取得したMap）
  void _openDetail(Map<String, dynamic> summary) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => YoutubeDetailScreen(summary: summary)),
    );
  }

  // ============================================================
  // build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // 要約中かどうかのフラグ（UI制御に使う）
    final isSummarizing = _summarizingId != null;

    return WillPopScope(
      // 要約中は誤操作防止のため戻るボタンを無効化
      onWillPop: () async => !isSummarizing,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.channel['name'] ?? '動画一覧'),
          // 要約中は戻るボタンを非表示にする
          leading: isSummarizing ? const SizedBox() : const BackButton(),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _videos.isEmpty
            ? const Center(child: Text('動画が見つかりませんでした'))
            : Column(
                children: [
                  // 要約中バナー（要約中のみ表示）
                  if (isSummarizing) _buildSummarizingBanner(),

                  // 動画一覧
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _videos.length,
                      itemBuilder: (context, index) =>
                          _buildVideoCard(_videos[index], isSummarizing),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ============================================================
  // UIパーツ
  // ============================================================

  /// 要約中バナーを構築する
  /// 画面上部に表示してユーザーに処理中であることを伝える
  Widget _buildSummarizingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: Colors.blue.shade50,
      child: const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(
            '要約中です。完了までお待ちください...',
            style: TextStyle(fontSize: 13, color: Colors.blue),
          ),
        ],
      ),
    );
  }

  /// 動画カードを構築する
  ///
  /// 要約済みかどうかで表示するボタンが変わる：
  /// ・未要約 → 「この動画を要約」ボタン
  /// ・要約済み → 「詳細を見る」＋「再要約」ボタン
  ///
  /// [video]         動画データ
  /// [isSummarizing] 現在いずれかの動画を要約中かどうか
  Widget _buildVideoCard(Map<String, dynamic> video, bool isSummarizing) {
    final vid = video['video_id'];
    final isThisSummarizing = _summarizingId == vid;
    final isSummarized = _summaryCache.containsKey(vid);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // サムネイル画像
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Image.network(
              video['thumbnail'] ?? '',
              width: double.infinity,
              height: 160,
              fit: BoxFit.cover,
              // 画像取得失敗時はプレースホルダーを表示
              errorBuilder: (_, __, ___) => Container(
                height: 160,
                color: Colors.grey.shade200,
                child: const Icon(
                  Icons.play_circle,
                  size: 48,
                  color: Colors.grey,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 動画タイトル
                Text(
                  video['title'] ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // 投稿日
                Text(
                  _formatDate(video['published_at'] ?? ''),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 10),

                // アクションボタン（要約済み/未要約で切り替え）
                Row(
                  children: [
                    if (isSummarized) ...[
                      // 要約済み：詳細ボタン＋再要約ボタン
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isSummarizing
                              ? null
                              : () => _openDetail(_summaryCache[vid]!),
                          icon: const Icon(Icons.article_outlined, size: 16),
                          label: const Text(
                            '詳細を見る',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                            side: const BorderSide(color: Colors.blue),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isSummarizing
                              ? null
                              : () => _summarize(video),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text(
                            '再要約',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ] else
                      // 未要約：要約ボタン
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isSummarizing
                              ? null
                              : () => _summarize(video),
                          icon: isThisSummarizing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome, size: 16),
                          label: Text(
                            isThisSummarizing ? '要約中...' : 'この動画を要約',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            // 要約中は薄い青、通常は青
                            backgroundColor: isThisSummarizing
                                ? Colors.blue.shade300
                                : Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ユーティリティ
  // ============================================================

  /// ISO 8601形式の日付文字列を「YYYY/MM/DD」形式に変換する
  ///
  /// パース失敗時は元の文字列をそのまま返す。
  /// 例：「2024-01-15T09:00:00Z」→「2024/01/15」
  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
          '${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
