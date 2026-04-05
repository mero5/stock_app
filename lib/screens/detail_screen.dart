import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:candlesticks_plus/candlesticks_plus.dart';
import 'package:candlesticks_plus/src/models/candle_style.dart';
import '../services/stock_service.dart';
import '../utils/formatter.dart';
import '../widgets/signal_card.dart';
import '../widgets/indicator_row.dart';

class DetailScreen extends StatefulWidget {
  final String code;
  final String name;

  const DetailScreen({super.key, required this.code, required this.name});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Map<String, dynamic>? detail;
  bool isLoading = true;
  String error = '';

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final data = await StockService.getDetail(widget.code);
      setState(() {
        detail = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
          ? Center(child: Text("エラー: $error"))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (detail == null || detail!.containsKey('error')) {
      return const Center(child: Text("データを取得できませんでした"));
    }

    final candles = List<Map<String, dynamic>>.from(detail!['candles'] ?? []);

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          _buildPriceCard(
            detail!['price'],
            detail!['change'],
            detail!['change_pct'],
          ),
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.candlestick_chart), text: "チャート"),
              Tab(icon: Icon(Icons.flag), text: "判断"),
              Tab(icon: Icon(Icons.bar_chart), text: "指標"),
              Tab(icon: Icon(Icons.smart_toy), text: "AI分析"),
            ],
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildChartTab(candles),
                _buildJudgeTab(candles),
                _buildIndicatorTab(),
                _buildAiTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceCard(dynamic price, dynamic change, dynamic changePct) {
    final isPositive = change != null ? (change as num) >= 0 : true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.code,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  price != null ? "¥${Formatter.number(price)}" : "---",
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (change != null)
                  Text(
                    "${isPositive ? '+' : ''}${(change as num).toStringAsFixed(1)}  "
                    "${isPositive ? '+' : ''}${(changePct as num).toStringAsFixed(2)}%",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isPositive ? Colors.red : Colors.green,
                    ),
                  ),
              ],
            ),
            const Icon(Icons.show_chart, size: 40, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildChartTab(List<Map<String, dynamic>> candles) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ローソク足チャート",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          _buildCandleChart(candles),
          const SizedBox(height: 16),
          const Text(
            "RSI",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            "30以下：売られすぎ  70以上：買われすぎ",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _buildRsiChart(candles),
        ],
      ),
    );
  }

  Widget _buildJudgeTab(List<Map<String, dynamic>> candles) {
    if (candles.isEmpty) return const Center(child: Text("データなし"));

    final closes = candles
        .map((c) => (c['close'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final latest = closes.last;
    final ma5 = (candles.last['ma5'] as num?)?.toDouble() ?? 0.0;
    final ma25 = (candles.last['ma25'] as num?)?.toDouble() ?? 0.0;
    final rsi = (candles.last['rsi'] as num?)?.toDouble() ?? 50.0;

    String crossSignal = "なし";
    Color crossColor = Colors.grey;
    if (candles.length >= 2) {
      final prevMa5 =
          (candles[candles.length - 2]['ma5'] as num?)?.toDouble() ?? 0.0;
      final prevMa25 =
          (candles[candles.length - 2]['ma25'] as num?)?.toDouble() ?? 0.0;
      if (prevMa5 < prevMa25 && ma5 > ma25) {
        crossSignal = "ゴールデンクロス（買いシグナル）";
        crossColor = Colors.red;
      } else if (prevMa5 > prevMa25 && ma5 < ma25) {
        crossSignal = "デッドクロス（売りシグナル）";
        crossColor = Colors.green;
      }
    }

    String rsiSignal;
    Color rsiColor;
    if (rsi <= 30) {
      rsiSignal = "売られすぎ（買いチャンス）";
      rsiColor = Colors.red;
    } else if (rsi >= 70) {
      rsiSignal = "買われすぎ（売りチャンス）";
      rsiColor = Colors.green;
    } else {
      rsiSignal = "中立";
      rsiColor = Colors.grey;
    }

    String maSignal;
    Color maColor;
    if (latest > ma5 && latest > ma25) {
      maSignal = "移動平均線の上（強気）";
      maColor = Colors.red;
    } else if (latest < ma5 && latest < ma25) {
      maSignal = "移動平均線の下（弱気）";
      maColor = Colors.green;
    } else {
      maSignal = "移動平均線付近（中立）";
      maColor = Colors.grey;
    }

    final highs = candles
        .map((c) => (c['high'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final lows = candles
        .map((c) => (c['low'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final high52 = highs.reduce((a, b) => a > b ? a : b);
    final low52 = lows.reduce((a, b) => a < b ? a : b);
    final distFromHigh = ((high52 - latest) / high52 * 100).toStringAsFixed(1);
    final distFromLow = ((latest - low52) / low52 * 100).toStringAsFixed(1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "売買シグナル",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          SignalCard(label: "📈 トレンド", value: crossSignal, color: crossColor),
          const SizedBox(height: 8),
          SignalCard(
            label: "💹 RSI (${rsi.toStringAsFixed(1)})",
            value: rsiSignal,
            color: rsiColor,
          ),
          const SizedBox(height: 8),
          SignalCard(label: "📊 移動平均線", value: maSignal, color: maColor),
          const SizedBox(height: 16),
          const Text(
            "価格帯",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("高値から", style: TextStyle(color: Colors.grey)),
                      Text(
                        "-$distFromHigh%",
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("安値から", style: TextStyle(color: Colors.grey)),
                      Text(
                        "+$distFromLow%",
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicatorTab() {
    final per = detail!['per'];
    final pbr = detail!['pbr'];
    final marketCap = detail!['market_cap'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "バリュエーション指標",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          IndicatorRow(
            label: "PER（株価収益率）",
            value: per != null
                ? "${Formatter.number(per, decimals: 1)}倍"
                : "---",
            description: "株価が1株あたり利益の何倍か。低いほど割安",
          ),
          IndicatorRow(
            label: "PBR（株価純資産倍率）",
            value: pbr != null
                ? "${Formatter.number(pbr, decimals: 1)}倍"
                : "---",
            description: "1倍以下は解散価値以下で割安の目安",
          ),
          IndicatorRow(
            label: "時価総額",
            value: Formatter.marketCap(marketCap),
            description: "市場が評価する会社全体の価値",
          ),
        ],
      ),
    );
  }

  Widget _buildAiTab() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.smart_toy, size: 60, color: Colors.blue),
          SizedBox(height: 16),
          Text(
            "AI分析",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text("近日実装予定", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildCandleChart(List<Map<String, dynamic>> candles) {
    if (candles.isEmpty) return const Text("データなし");

    final data = candles.length > 60
        ? candles.sublist(candles.length - 60)
        : candles;

    final candleList = data.map((c) {
      return Candle(
        date: DateTime.parse(c['date']),
        open: (c['open'] as num?)?.toDouble() ?? 0.0,
        high: (c['high'] as num?)?.toDouble() ?? 0.0,
        low: (c['low'] as num?)?.toDouble() ?? 0.0,
        close: (c['close'] as num?)?.toDouble() ?? 0.0,
        volume: (c['volume'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    return SizedBox(
      height: 300,
      child: Candlesticks(
        candles: candleList,
        candleStyle: CandleStyle(
          bullColor: Colors.red,
          bearColor: Colors.green,
        ),
      ),
    );
  }

  Widget _buildRsiChart(List<Map<String, dynamic>> candles) {
    if (candles.isEmpty) return const Text("データなし");

    final data = candles.length > 30
        ? candles.sublist(candles.length - 30)
        : candles;

    final rsiSpots = data
        .asMap()
        .entries
        .where((e) => e.value['rsi'] != null)
        .map(
          (e) => FlSpot(e.key.toDouble(), (e.value['rsi'] as num).toDouble()),
        )
        .toList();

    return SizedBox(
      height: 120,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (value) {
              if (value == 30 || value == 70) {
                return const FlLine(
                  color: Colors.red,
                  strokeWidth: 1,
                  dashArray: [5, 5],
                );
              }
              return const FlLine(color: Colors.grey, strokeWidth: 0.5);
            },
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value == 30 || value == 70) {
                    return Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10, color: Colors.red),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            bottomTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: rsiSpots,
              isCurved: true,
              color: Colors.purple,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}
