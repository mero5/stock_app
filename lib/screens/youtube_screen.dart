import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';

class YoutubeScreen extends StatefulWidget {
  const YoutubeScreen({super.key});

  @override
  State<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends State<YoutubeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 検索
  final searchController = TextEditingController();
  List<Map<String, String>> searchResults = [];
  bool isSearching = false;

  // 登録チャンネル（今はローカル管理、後でDynamoDBに移行予定）
  List<Map<String, String>> registeredChannels = [];

  // 要約一覧
  List<Map<String, dynamic>> summaries = [];
  bool isLoadingSummaries = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // チャンネル検索
  Future<void> searchChannels(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }
    setState(() => isSearching = true);
    try {
      final res = await http.get(
        Uri.parse(
          "${Constants.backendUrl}/channels/search?q=${Uri.encodeComponent(query)}",
        ),
      );
      final List data = jsonDecode(res.body);
      setState(() {
        searchResults = data
            .map<Map<String, String>>(
              (e) => {
                "channel_id": e["channel_id"].toString(),
                "name": e["name"].toString(),
                "description": e["description"].toString(),
                "thumbnail": e["thumbnail"].toString(),
              },
            )
            .toList();
      });
    } catch (e) {
      print("チャンネル検索エラー: $e");
    } finally {
      setState(() => isSearching = false);
    }
  }

  // チャンネル登録
  void registerChannel(Map<String, String> channel) {
    if (registeredChannels.any(
      (c) => c["channel_id"] == channel["channel_id"],
    )) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("すでに登録済みです")));
      return;
    }
    setState(() => registeredChannels.add(channel));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("${channel["name"]} を登録しました")));
  }

  // チャンネル削除
  void deleteChannel(String channelId) {
    setState(() {
      registeredChannels.removeWhere((c) => c["channel_id"] == channelId);
    });
  }

  // 字幕取得→要約
  Future<Map<String, dynamic>> getSummary(Map<String, String> channel) async {
    try {
      final res = await http.get(
        Uri.parse(
          "${Constants.backendUrl}/channels/${channel["channel_id"]}/latest_video",
        ),
      );
      final videoData = jsonDecode(res.body);

      if (videoData["error"] != null) {
        return {
          "channel_name": channel["name"],
          "title": "動画が見つかりません",
          "summary": "動画が取得できませんでした",
          "video_id": "",
          "url": "",
        };
      }

      final videoId = videoData["video_id"] ?? "";
      final title = videoData["title"] ?? "";
      final description = videoData["description"] ?? "";
      final videoUrl = "https://www.youtube.com/watch?v=$videoId";

      final summaryRes = await http.post(
        Uri.parse("${Constants.backendUrl}/summarize"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "title": title,
          "url": videoUrl,
          "transcript": description,
        }),
      );
      final summaryData = jsonDecode(summaryRes.body);

      return {
        "channel_name": channel["name"],
        "title": title,
        "summary": summaryData["summary"] ?? "要約できませんでした",
        "video_id": videoId,
        "url": videoUrl,
      };
    } catch (e) {
      return {
        "channel_name": channel["name"],
        "title": "エラー",
        "summary": "取得に失敗しました: $e",
        "video_id": "",
        "url": "",
      };
    }
  }

  // 全チャンネルの要約を取得
  Future<void> loadSummaries() async {
    if (registeredChannels.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("チャンネルを登録してください")));
      return;
    }
    setState(() {
      isLoadingSummaries = true;
      summaries = [];
    });

    for (final channel in registeredChannels) {
      final summary = await getSummary(channel);
      setState(() => summaries.add(summary));
    }

    setState(() => isLoadingSummaries = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("YouTube要約"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.search), text: "検索"),
            Tab(icon: Icon(Icons.subscriptions), text: "登録"),
            Tab(icon: Icon(Icons.summarize), text: "要約"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSearchTab(),
          _buildRegisteredTab(),
          _buildSummaryTab(),
        ],
      ),
    );
  }

  // ① 検索タブ
  Widget _buildSearchTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: searchController,
            onChanged: searchChannels,
            decoration: const InputDecoration(
              labelText: "チャンネル名で検索（例: 株式投資）",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          if (isSearching) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: searchResults.length,
              itemBuilder: (context, index) {
                final channel = searchResults[index];
                final isRegistered = registeredChannels.any(
                  (c) => c["channel_id"] == channel["channel_id"],
                );

                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.network(
                      channel["thumbnail"]!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.account_circle, size: 48),
                    ),
                  ),
                  title: Text(channel["name"]!),
                  subtitle: Text(
                    channel["description"]!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      isRegistered
                          ? Icons.check_circle
                          : Icons.add_circle_outline,
                      color: isRegistered ? Colors.green : Colors.blue,
                    ),
                    onPressed: isRegistered
                        ? null
                        : () => registerChannel(channel),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ② 登録チャンネルタブ
  Widget _buildRegisteredTab() {
    if (registeredChannels.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.subscriptions, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text("チャンネルを登録してください", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: registeredChannels.length,
      itemBuilder: (context, index) {
        final channel = registeredChannels[index];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.network(
              channel["thumbnail"]!,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.account_circle, size: 48),
            ),
          ),
          title: Text(channel["name"]!),
          subtitle: Text(
            channel["description"]!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => deleteChannel(channel["channel_id"]!),
          ),
        );
      },
    );
  }

  // ③ 要約タブ
  Widget _buildSummaryTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isLoadingSummaries ? null : loadSummaries,
              icon: const Icon(Icons.refresh),
              label: Text(isLoadingSummaries ? "取得中..." : "最新動画を要約する"),
            ),
          ),
          const SizedBox(height: 16),
          if (isLoadingSummaries)
            const Column(
              children: [
                LinearProgressIndicator(),
                SizedBox(height: 8),
                Text("字幕を取得・要約中です...", style: TextStyle(color: Colors.grey)),
              ],
            ),
          Expanded(
            child: summaries.isEmpty
                ? const Center(
                    child: Text(
                      "「最新動画を要約する」を押してください",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: summaries.length,
                    itemBuilder: (context, index) {
                      final s = summaries[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // チャンネル名
                              Text(
                                s["channel_name"] ?? "",
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // 動画タイトル
                              Text(
                                s["title"] ?? "",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              // 要約
                              Text(
                                s["summary"] ?? "",
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              // YouTubeリンク
                              if (s["url"] != null && s["url"]!.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () {
                                    // URLを開く（後でurl_launcherを追加）
                                  },
                                  icon: const Icon(
                                    Icons.play_circle,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    "YouTubeで見る",
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
