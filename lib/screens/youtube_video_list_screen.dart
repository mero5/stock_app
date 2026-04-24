import 'package:flutter/material.dart';
import '../services/stock_service.dart';
import '../config/constants.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'youtube_detail_screen.dart';

class YoutubeVideoListScreen extends StatefulWidget {
  final Map<String, String> channel;
  const YoutubeVideoListScreen({super.key, required this.channel});

  @override
  State<YoutubeVideoListScreen> createState() => _YoutubeVideoListScreenState();
}

class _YoutubeVideoListScreenState extends State<YoutubeVideoListScreen> {
  List<Map<String, dynamic>> _videos = [];
  bool _isLoading = true;
  String? _summarizingId;

  // 要約済みキャッシュ（video_id → summary）
  final Map<String, Map<String, dynamic>> _summaryCache = {};

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    final videos = await StockService.getChannelVideos(
      widget.channel["channel_id"]!,
    );
    setState(() {
      _videos = videos;
      _isLoading = false;
    });
  }

  Future<void> _summarize(Map<String, dynamic> video) async {
    // すでに要約済みなら詳細へ
    if (_summaryCache.containsKey(video["video_id"])) {
      _openDetail(_summaryCache[video["video_id"]]!);
      return;
    }

    setState(() => _summarizingId = video["video_id"]);
    try {
      final videoUrl = "https://www.youtube.com/watch?v=${video["video_id"]}";
      final res = await http.post(
        Uri.parse("${Constants.backendUrl}/summarize"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "title": video["title"],
          "url": videoUrl,
          "transcript": video["description"] ?? "",
        }),
      );
      final data = jsonDecode(res.body);
      final summaryData = <String, dynamic>{
        "channel_name": widget.channel["name"],
        "title": video["title"],
        "url": videoUrl,
        "published_at": video["published_at"] ?? "",
        ...data,
      };

      // ローカルキャッシュに保存
      _summaryCache[video["video_id"]] = summaryData;
      setState(() {});

      if (mounted) _openDetail(summaryData);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("要約に失敗しました: $e")));
      }
    } finally {
      if (mounted) setState(() => _summarizingId = null);
    }
  }

  void _openDetail(Map<String, dynamic> summary) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => YoutubeDetailScreen(summary: summary)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSummarizing = _summarizingId != null;

    return WillPopScope(
      // 要約中は戻るボタンを無効化
      onWillPop: () async => !isSummarizing,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.channel["name"] ?? "動画一覧"),
          // 要約中は戻るボタンを無効化
          leading: isSummarizing ? const SizedBox() : const BackButton(),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _videos.isEmpty
            ? const Center(child: Text("動画が見つかりませんでした"))
            : Column(
                children: [
                  // 要約中バナー
                  if (isSummarizing)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 16,
                      ),
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
                            "要約中です。完了までお待ちください...",
                            style: TextStyle(fontSize: 13, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _videos.length,
                      itemBuilder: (context, index) {
                        final v = _videos[index];
                        final vid = v["video_id"];
                        final isThisSummarizing = _summarizingId == vid;
                        final isSummarized = _summaryCache.containsKey(vid);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // サムネイル
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12),
                                ),
                                child: Image.network(
                                  v["thumbnail"] ?? "",
                                  width: double.infinity,
                                  height: 160,
                                  fit: BoxFit.cover,
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
                                    // タイトル
                                    Text(
                                      v["title"] ?? "",
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
                                      _formatDate(v["published_at"] ?? ""),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    // ボタン
                                    Row(
                                      children: [
                                        // 要約済みなら詳細ボタン
                                        if (isSummarized) ...[
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: isSummarizing
                                                  ? null
                                                  : () => _openDetail(
                                                      _summaryCache[vid]!,
                                                    ),
                                              icon: const Icon(
                                                Icons.article_outlined,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                "詳細を見る",
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.blue,
                                                side: const BorderSide(
                                                  color: Colors.blue,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                    ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: isSummarizing
                                                  ? null
                                                  : () => _summarize(v),
                                              icon: const Icon(
                                                Icons.refresh,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                "再要約",
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.grey.shade600,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ] else
                                          // 未要約なら要約ボタン
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: isSummarizing
                                                  ? null
                                                  : () => _summarize(v),
                                              icon: isThisSummarizing
                                                  ? const SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.white,
                                                          ),
                                                    )
                                                  : const Icon(
                                                      Icons.auto_awesome,
                                                      size: 16,
                                                    ),
                                              label: Text(
                                                isThisSummarizing
                                                    ? "要約中..."
                                                    : "この動画を要約",
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    isThisSummarizing
                                                    ? Colors.blue.shade300
                                                    : Colors.blue,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                    ),
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
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return "${dt.year}/${dt.month.toString().padLeft(2, '0')}/"
          "${dt.day.toString().padLeft(2, '0')}";
    } catch (_) {
      return iso;
    }
  }
}
