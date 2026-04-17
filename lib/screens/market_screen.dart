import 'package:flutter/material.dart';
import '../services/stock_service.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic> _sectorData = {"jp": [], "us": []};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await StockService.getSectorTrends();
      setState(() => _sectorData = data);
    } catch (e) {
      print('マーケットデータ取得エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('マーケット'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '🇯🇵 日本'),
            Tab(text: '🇺🇸 米国'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildSectorList('jp'), _buildSectorList('us')],
            ),
    );
  }

  Widget _buildSectorList(String market) {
    final sectors = List<Map<String, dynamic>>.from(_sectorData[market] ?? []);

    if (sectors.isEmpty) {
      return const Center(child: Text('データなし'));
    }

    // トップ上昇・下落セクター
    final topGainer = sectors.first;
    final topLoser = sectors.last;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // トレンドサマリー
          Row(
            children: [
              Expanded(
                child: _trendBadge(
                  '🔥 本日の上昇',
                  topGainer['name'],
                  topGainer['change_pct'],
                  Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _trendBadge(
                  '📉 本日の下落',
                  topLoser['name'],
                  topLoser['change_pct'],
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // セクター一覧
          const Text(
            'セクター騰落率（本日）',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...sectors.map((s) => _sectorRow(s)),
          const SizedBox(height: 20),

          // 5日トレンド
          const Text(
            '5日間トレンド',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...(() {
            final sorted = List<Map<String, dynamic>>.from(sectors)
              ..sort(
                (a, b) =>
                    (b['trend_5d'] as num).compareTo(a['trend_5d'] as num),
              );
            return sorted.map((s) => _sectorRow(s, use5d: true));
          })(),
        ],
      ),
    );
  }

  Widget _trendBadge(String label, String name, num changePct, Color color) {
    final sign = changePct >= 0 ? '+' : '';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Text(
              '$sign${changePct.toStringAsFixed(2)}%',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectorRow(Map<String, dynamic> s, {bool use5d = false}) {
    final pct = (use5d ? s['trend_5d'] : s['change_pct']) as num;
    final isUp = pct >= 0;
    final color = isUp ? Colors.red : Colors.green;
    final sign = isUp ? '+' : '';

    // バーの幅（最大±5%を100%とする）
    final barWidth = (pct.abs() / 5.0).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // セクター名
          SizedBox(
            width: 90,
            child: Text(
              s['name'],
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // バー
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: barWidth,
                  child: Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 数値
          SizedBox(
            width: 56,
            child: Text(
              '$sign${pct.toStringAsFixed(2)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
