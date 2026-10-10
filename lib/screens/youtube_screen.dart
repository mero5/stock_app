import 'package:flutter/material.dart';
import 'dart:convert';
import '../config/constants.dart';
import '../services/auth_service.dart';
import '../services/channel_service.dart';
import 'youtube_video_list_screen.dart';
import '../config/timeouts.dart';
import '../services/api_client.dart';

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

  // 登録チャンネル
  List<Map<String, String>> registeredChannels = [];
  bool isLoadingChannels = false;

  String? _userId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initUserId();
  }

  // UserIdを取得してからDynamoDBのチャンネルを読み込む
  Future<void> _initUserId() async {
    final userId = await AuthService.getUserId();
    setState(() => _userId = userId);
    if (userId != null) {
      _loadChannelsFromDb(userId);
    }
  }

  //  DynamoDBからチャンネル一覧を読み込む
  Future<void> _loadChannelsFromDb(String userId) async {
    setState(() => isLoadingChannels = true);
    final channels = await ChannelService.getChannels(userId);
    setState(() {
      registeredChannels = channels;
      isLoadingChannels = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // チャンネル検索（変更なし）
  Future<void> searchChannels(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }
    setState(() => isSearching = true);
    try {
      final res = await ApiClient.get(
        Uri.parse(
          "${Constants.backendUrl}/channels/search?q=${Uri.encodeComponent(query)}",
        ),
      ).timeout(AppTimeouts.api);
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

  //  変更: チャンネル登録をDynamoDBに保存
  Future<void> registerChannel(Map<String, String> channel) async {
    if (registeredChannels.any(
      (c) => c["channel_id"] == channel["channel_id"],
    )) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("すでに登録済みです")));
      return;
    }
    if (_userId == null) return;

    final success = await ChannelService.saveChannel(_userId!, channel);
    if (success) {
      setState(() => registeredChannels.add(channel));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("${channel["name"]} を登録しました")));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("登録に失敗しました")));
    }
  }

  //  変更: チャンネル削除をDynamoDBにも反映
  Future<void> deleteChannel(String channelId) async {
    if (_userId == null) return;

    final success = await ChannelService.deleteChannel(_userId!, channelId);
    if (success) {
      setState(() {
        registeredChannels.removeWhere((c) => c["channel_id"] == channelId);
      });
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("削除に失敗しました")));
    }
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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSearchTab(),
          _buildRegisteredTab(),
        ],
      ),
    );
  }

  // ① 検索タブ（変更なし）
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
                        : () => registerChannel(channel), //  async対応
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ② 登録チャンネルタブ（ ローディング表示）
  Widget _buildRegisteredTab() {
    // 初期読み込み中はインジケーターを表示
    if (isLoadingChannels) {
      return const Center(child: CircularProgressIndicator());
    }

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
            onPressed: () => deleteChannel(channel["channel_id"]!), //  async対応
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => YoutubeVideoListScreen(channel: channel),
              ),
            );
          },
        );
      },
    );
  }
}
