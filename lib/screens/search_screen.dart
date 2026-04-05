import 'package:flutter/material.dart';
import '../models/stock.dart';
import '../services/stock_service.dart';
import '../services/watchlist_service.dart';

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

  Future<void> search(String keyword) async {
    if (keyword.isEmpty) {
      setState(() => filteredStocks = []);
      return;
    }
    setState(() => isLoading = true);
    try {
      final results = await StockService.search(keyword);
      setState(() => filteredStocks = results);
    } catch (e) {
      print("検索エラー: $e");
    } finally {
      setState(() => isLoading = false);
    }
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

  void handleAdd() async {
    final codes = selectedStocks.map((s) => s["code"]!).toList();
    await WatchlistService.save(codes);
    widget.onAdd(codes);
    setState(() {
      selectedStocks = [];
      filteredStocks = [];
      controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(
            controller: controller,
            onChanged: search,
            decoration: const InputDecoration(
              labelText: "銘柄名 or コード（例: トヨタ, 7203, AAPL）",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          if (isLoading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: filteredStocks.length,
              itemBuilder: (context, index) {
                final stock = filteredStocks[index];
                final code = stock["code"]!;
                final name = stock["name"]!;
                final market = stock["market"]!;
                final isSelected = selectedStocks.any((s) => s["code"] == code);
                final isAlreadyAdded = widget.watchList.any(
                  (s) => s.code == code,
                );

                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: market == "JP"
                          ? Colors.red.shade100
                          : Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      market,
                      style: TextStyle(
                        color: market == "JP"
                            ? Colors.red.shade800
                            : Colors.blue.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text(code),
                  trailing: Icon(
                    isAlreadyAdded || isSelected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color: isAlreadyAdded ? Colors.grey : Colors.blue,
                  ),
                  onTap: isAlreadyAdded ? null : () => toggleSelect(stock),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          if (selectedStocks.isNotEmpty)
            Text(
              "${selectedStocks.length}件選択中",
              style: const TextStyle(color: Colors.blue),
            ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            onPressed: selectedStocks.isNotEmpty ? handleAdd : null,
            icon: const Icon(Icons.add),
            label: const Text("ウォッチリストに追加"),
          ),
        ],
      ),
    );
  }
}
