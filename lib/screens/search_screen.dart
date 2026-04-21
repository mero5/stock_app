import 'package:flutter/material.dart';
import '../models/stock.dart';
import '../services/stock_service.dart';
import '../services/watchlist_service.dart';
import 'dart:async';

class SearchScreen extends StatefulWidget {
  final Function(List<String>) onAdd;
  final List<Stock> watchList;

  const SearchScreen({super.key, required this.onAdd, required this.watchList});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final controller = TextEditingController();
  List<Map<String, String>> filteredStocks = [];
  List<Map<String, String>> selectedStocks = [];
  bool isLoading = false;
  bool _isAdding = false; // ← 追加
  String _lastQuery = ''; // ← 追加（検索の重複防止）
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel(); // ← 追加
    controller.dispose();
    super.dispose();
  }

  Future<void> search(String keyword) async {
    // デバウンス処理：入力が止まってから500ms後に検索
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() {});
      _lastQuery = keyword;

      if (keyword.isEmpty) {
        setState(() {
          filteredStocks = [];
          isLoading = false;
        });
        return;
      }
      setState(() => isLoading = true);
      try {
        final results = await StockService.search(keyword);
        if (_lastQuery == keyword && mounted) {
          setState(() => filteredStocks = results);
        }
      } catch (e) {
        print("検索エラー: $e");
      } finally {
        if (mounted) setState(() => isLoading = false);
      }
    });
  }

  void toggleSelect(Map<String, String> stock) {
    final code = stock["code"]!;
    if (widget.watchList.any((s) => s.code == code)) return;
    setState(() {
      final idx = selectedStocks.indexWhere((s) => s["code"] == code);
      if (idx >= 0) {
        selectedStocks.removeAt(idx);
      } else {
        selectedStocks.add(stock);
      }
    });
  }

  Future<void> handleAdd() async {
    if (_isAdding) return; // ← 二重タップ防止
    setState(() => _isAdding = true);
    try {
      final codes = selectedStocks.map((s) => s["code"]!).toList();
      await WatchlistService.save(codes);
      widget.onAdd(codes);
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      print("追加エラー: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("追加エラー: $e")));
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("銘柄を追加"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
          // 検索バー
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: controller,
              // autofocus: true,
              onChanged: (value) {
                setState(() {}); // ← controllerの変化をUIに反映
                search(value);
              },
              decoration: InputDecoration(
                hintText: "銘柄名 or コード（例: トヨタ, 7203, AAPL）",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          controller.clear();
                          setState(() => filteredStocks = []);
                        },
                      )
                    : null,
              ),
            ),
          ),

          // ローディング
          if (isLoading) const LinearProgressIndicator(),

          // 検索結果
          Expanded(
            child: filteredStocks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search,
                          size: 60,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          controller.text.isEmpty
                              ? "銘柄名やコードで検索してください"
                              : "検索結果がありません",
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: filteredStocks.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16),
                    itemBuilder: (context, index) {
                      final stock = filteredStocks[index];
                      final code = stock["code"]!;
                      final name = stock["name"]!;
                      final market = stock["market"]!;
                      final isSelected = selectedStocks.any(
                        (s) => s["code"] == code,
                      );
                      final isAlreadyAdded = widget.watchList.any(
                        (s) => s.code == code,
                      );

                      return ListTile(
                        tileColor: isSelected
                            ? Colors.blue.withOpacity(0.05)
                            : Colors.white,
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: market == "JP"
                                ? Colors.red.shade50
                                : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              market,
                              style: TextStyle(
                                color: market == "JP"
                                    ? Colors.red.shade700
                                    : Colors.blue.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          code,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: isAlreadyAdded
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  "追加済み",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            : Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.add_circle_outline,
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.grey.shade400,
                                size: 28,
                              ),
                        onTap: isAlreadyAdded
                            ? null
                            : () => toggleSelect(stock),
                      );
                    },
                  ),
          ),

          // 追加ボタン
          if (selectedStocks.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isAdding ? null : handleAdd,
                  icon: const Icon(Icons.add),
                  label: Text("ウォッチリストに追加（${selectedStocks.length}件）"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
