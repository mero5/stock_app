import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import '../models/stock.dart';
import '../services/stock_service.dart';
import '../services/watchlist_service.dart';
import '../utils/formatter.dart';
import 'login_screen.dart';
import 'search_screen.dart';
import 'detail_screen.dart';
import 'youtube_screen.dart';
import 'schedule_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  List<Stock> watchList = [];
  bool _editMode = false;
  List<String> _selectedCodes = [];

  @override
  void initState() {
    super.initState();
    loadFavorites();
  }

  Future<void> loadFavorites() async {
    try {
      final codes = await WatchlistService.getCodes();
      final stocks = await Future.wait(
        codes.map((code) => StockService.getStockInfo(code)),
      );
      setState(() => watchList = stocks);
    } catch (e) {
      print("お気に入り取得エラー: $e");
    }
  }

  void _toggleEditMode() {
    setState(() {
      _editMode = !_editMode;
      _selectedCodes = [];
    });
  }

  void _toggleSelect(String code) {
    setState(() {
      if (_selectedCodes.contains(code)) {
        _selectedCodes.remove(code);
      } else {
        _selectedCodes.add(code);
      }
    });
  }

  Future<void> _deleteSelected() async {
    for (final code in _selectedCodes) {
      await WatchlistService.delete(code);
    }
    await loadFavorites();
    setState(() {
      _editMode = false;
      _selectedCodes = [];
    });
  }

  Widget _buildHomeTab() {
    if (watchList.isEmpty) {
      return const Center(child: Text("銘柄を追加してください"));
    }
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: watchList.length,
            itemBuilder: (context, index) {
              final stock = watchList[index];
              final isSelected = _selectedCodes.contains(stock.code);

              return ListTile(
                leading: _editMode
                    ? Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleSelect(stock.code),
                      )
                    : const Icon(Icons.show_chart),
                title: Text(stock.name),
                subtitle: Text(stock.code),
                trailing: _editMode
                    ? null
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            stock.price != "---"
                                ? "¥${Formatter.number(int.tryParse(stock.price) ?? 0)}"
                                : "---",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (stock.change.isNotEmpty)
                            Text(
                              "${stock.change}  ${stock.changePct}",
                              style: TextStyle(
                                fontSize: 11,
                                color: stock.isPositive
                                    ? Colors.red
                                    : Colors.green,
                              ),
                            ),
                        ],
                      ),
                onTap: _editMode
                    ? () => _toggleSelect(stock.code)
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetailScreen(
                              code: stock.code,
                              name: stock.name,
                            ),
                          ),
                        );
                      },
              );
            },
          ),
        ),
        if (_editMode && _selectedCodes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _deleteSelected,
                icon: const Icon(Icons.delete),
                label: Text("${_selectedCodes.length}件削除"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("株アプリ"),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              icon: Icon(_editMode ? Icons.check : Icons.edit),
              onPressed: _toggleEditMode,
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          SearchScreen(
            watchList: watchList,
            onAdd: (codes) async {
              await loadFavorites();
              setState(() => _currentIndex = 0);
            },
          ),
          const YoutubeScreen(),
          const ScheduleScreen(),
          Center(
            child: ElevatedButton(
              onPressed: () async {
                await Amplify.Auth.signOut();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              child: const Text("ログアウト"),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) async {
          if (index == 0) await loadFavorites();
          setState(() {
            _currentIndex = index;
            _editMode = false;
            _selectedCodes = [];
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "ホーム"),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: "追加"),
          BottomNavigationBarItem(
            icon: Icon(Icons.play_circle),
            label: "YouTube",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: "スケジュール",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.logout), label: "ログアウト"),
        ],
      ),
    );
  }
}
