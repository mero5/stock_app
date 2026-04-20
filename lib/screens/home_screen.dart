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
import 'market_screen.dart';

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

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ログアウト', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await Amplify.Auth.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  // AI診断モーダル
  void _showAiDiagnosis() {
    String _selectedPeriod = '短期';
    bool _isAnalyzing = false;
    List<Map<String, dynamic>> _results = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (_, scrollController) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // タイトル
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🤖 AI診断',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 期間選択
                const Text(
                  '診断期間を選択',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['短期', '中期', '長期'].map((v) {
                    final selected = _selectedPeriod == v;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () => setModalState(() => _selectedPeriod = v),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.blue
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected
                                    ? Colors.blue
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  v,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: selected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                Text(
                                  v == '短期'
                                      ? '数日〜2週間'
                                      : v == '中期'
                                      ? '1〜3ヶ月'
                                      : '6ヶ月以上',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: selected
                                        ? Colors.white70
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // 診断ボタン
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAnalyzing || watchList.isEmpty
                        ? null
                        : () async {
                            setModalState(() => _isAnalyzing = true);
                            final results = <Map<String, dynamic>>[];
                            for (final stock in watchList) {
                              try {
                                final result = await StockService.consult(
                                  code: stock.displayCode,
                                  name: stock.name,
                                  direction: '買い',
                                  tradeType: '現物取引',
                                  period: _selectedPeriod,
                                  extraQuestions: [],
                                  price: double.tryParse(
                                    stock.price.replaceAll(',', ''),
                                  ),
                                );
                                results.add({
                                  'code': stock.displayCode,
                                  'name': stock.name,
                                  'price': stock.price,
                                  'change': stock.change,
                                  'isPositive': stock.isPositive,
                                  ...result,
                                });
                              } catch (e) {
                                print('AI診断エラー ${stock.displayCode}: $e');
                              }
                            }
                            setModalState(() {
                              _results = results;
                              _isAnalyzing = false;
                            });
                          },
                    icon: _isAnalyzing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _isAnalyzing
                          ? '診断中... (${watchList.length}銘柄)'
                          : 'ウォッチリストを一括診断',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 結果一覧
                Expanded(
                  child: _results.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 48,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                watchList.isEmpty
                                    ? 'ウォッチリストに銘柄を追加してください'
                                    : '期間を選択して診断してください',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _results.length,
                          itemBuilder: (_, i) =>
                              _buildDiagnosisCard(_results[i]),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiagnosisCard(Map<String, dynamic> r) {
    final judgment = r['judgment'] as String? ?? '';
    final judgeMap = {
      '適切': (Colors.red, Icons.trending_up, '買い有利'),
      '要注意': (Colors.orange, Icons.warning, '要注意'),
      '不適切': (Colors.green, Icons.trending_down, '見送り'),
    };
    final (color, icon, label) =
        judgeMap[judgment] ?? (Colors.grey, Icons.help, '不明');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 左：銘柄情報
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    r['code'],
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  if ((r['judgment_reason'] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        r['judgment_reason'],
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 右：判定
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
              final isSelected = _selectedCodes.contains(stock.displayCode);
              return ListTile(
                leading: _editMode
                    ? Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleSelect(stock.displayCode),
                      )
                    : const Icon(Icons.show_chart),
                title: Text(stock.name),
                subtitle: Text(
                  // 5桁の日本株コードは末尾の0を除いて4桁で表示
                  RegExp(r'^\d{5}$').hasMatch(stock.displayCode)
                      ? stock.displayCode.substring(0, 4)
                      : stock.displayCode,
                ),
                trailing: _editMode
                    ? null
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            stock.price != "---" ? "¥${stock.price}" : "---",
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
                    ? () => _toggleSelect(stock.displayCode)
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetailScreen(
                              code: stock.displayCode,
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
          // ホームタブのみ表示
          if (_currentIndex == 0) ...[
            // AI診断ボタン
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'AI診断',
              onPressed: _showAiDiagnosis,
            ),
            // 銘柄追加ボタン
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '銘柄を追加',
              onPressed: () async {
                print('🔍 プラスボタン押された');
                // 編集モードをリセット
                setState(() {
                  _editMode = false;
                  _selectedCodes = [];
                });
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SearchScreen(
                      watchList: watchList,
                      onAdd: (codes) async {
                        await loadFavorites();
                      },
                    ),
                  ),
                );
                // 戻ってきたときにも更新
                await loadFavorites();
              },
            ),
            // 編集ボタン
            IconButton(
              icon: Icon(_editMode ? Icons.check : Icons.edit),
              onPressed: _toggleEditMode,
            ),
          ],
          // ログアウトメニュー
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'logout') _confirmLogout();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text('ログアウト', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          const YoutubeScreen(),
          const ScheduleScreen(),
          const MarketScreen(),
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
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ホーム'),
          BottomNavigationBarItem(
            icon: Icon(Icons.play_circle),
            label: 'YouTube',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: 'スケジュール',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'マーケット'),
        ],
      ),
    );
  }
}
