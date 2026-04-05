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

    final highs = candles
        .map((c) => (c['high'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final lows = candles
        .map((c) => (c['low'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final high52 = highs.reduce((a, b) => a > b ? a : b);
    final low52 = lows.reduce((a, b) => a < b ? a : b);
    final distFromLowPct = (latest - low52) / low52 * 100;
    final distFromHighPct = (high52 - latest) / high52 * 100;

    final per = detail!['per'];
    final pbr = detail!['pbr'];

    // ── スコア計算 ──
    int score = 0;
    final List<Map<String, dynamic>> signals = [];

    // RSI判定
    String rsiSignal;
    Color rsiColor;
    int rsiScore = 0;
    if (rsi <= 30) {
      rsiSignal = "売られすぎ（買いチャンス）";
      rsiColor = Colors.red;
      rsiScore = 20;
    } else if (rsi <= 45) {
      rsiSignal = "やや売られすぎ";
      rsiColor = Colors.orange;
      rsiScore = 10;
    } else if (rsi >= 70) {
      rsiSignal = "買われすぎ（売りチャンス）";
      rsiColor = Colors.green;
      rsiScore = 0;
    } else if (rsi >= 55) {
      rsiSignal = "やや買われすぎ";
      rsiColor = Colors.teal;
      rsiScore = 5;
    } else {
      rsiSignal = "中立";
      rsiColor = Colors.grey;
      rsiScore = 10;
    }
    score += rsiScore;
    signals.add({
      "label": "💹 RSI (${rsi.toStringAsFixed(1)})",
      "value": rsiSignal,
      "color": rsiColor,
    });

    // トレンド判定
    String crossSignal;
    Color crossColor;
    int crossScore = 0;
    if (candles.length >= 2) {
      final prevMa5 =
          (candles[candles.length - 2]['ma5'] as num?)?.toDouble() ?? 0.0;
      final prevMa25 =
          (candles[candles.length - 2]['ma25'] as num?)?.toDouble() ?? 0.0;
      if (prevMa5 < prevMa25 && ma5 > ma25) {
        crossSignal = "🔥 ゴールデンクロス発生！";
        crossColor = Colors.red;
        crossScore = 25;
      } else if (prevMa5 > prevMa25 && ma5 < ma25) {
        crossSignal = "⚠️ デッドクロス発生！";
        crossColor = Colors.green;
        crossScore = 0;
      } else if (ma5 > ma25) {
        final diff = ((ma5 - ma25) / ma25 * 100).toStringAsFixed(1);
        crossSignal = "上昇トレンド（+$diff%）";
        crossColor = Colors.red;
        crossScore = 20;
      } else {
        final diff = ((ma25 - ma5) / ma25 * 100).toStringAsFixed(1);
        crossSignal = "下降トレンド（-$diff%）";
        crossColor = Colors.green;
        crossScore = 0;
      }
    } else {
      crossSignal = "データ不足";
      crossColor = Colors.grey;
    }
    score += crossScore;
    signals.add({
      "label": "📈 トレンド",
      "value": crossSignal,
      "color": crossColor,
    });

    // 価格帯判定
    String priceSignal;
    Color priceColor;
    int priceScore = 0;
    if (distFromLowPct <= 10) {
      priceSignal = "52週安値圏（割安ゾーン）";
      priceColor = Colors.red;
      priceScore = 20;
    } else if (distFromLowPct <= 25) {
      priceSignal = "安値寄り";
      priceColor = Colors.orange;
      priceScore = 10;
    } else if (distFromHighPct <= 5) {
      priceSignal = "52週高値圏（高値注意）";
      priceColor = Colors.green;
      priceScore = 0;
    } else if (distFromHighPct <= 15) {
      priceSignal = "高値寄り";
      priceColor = Colors.teal;
      priceScore = 5;
    } else {
      priceSignal = "中間帯";
      priceColor = Colors.grey;
      priceScore = 10;
    }
    score += priceScore;
    signals.add({"label": "📊 価格帯", "value": priceSignal, "color": priceColor});

    // PBR判定
    if (pbr != null) {
      final pbrVal = (pbr as num).toDouble();
      String pbrSignal;
      Color pbrColor;
      int pbrScore = 0;
      if (pbrVal <= 1.0) {
        pbrSignal = "1倍以下（割安）";
        pbrColor = Colors.red;
        pbrScore = 20;
      } else if (pbrVal <= 1.5) {
        pbrSignal = "やや割安";
        pbrColor = Colors.orange;
        pbrScore = 10;
      } else if (pbrVal >= 5.0) {
        pbrSignal = "割高注意";
        pbrColor = Colors.green;
        pbrScore = 0;
      } else {
        pbrSignal = "適正水準";
        pbrColor = Colors.grey;
        pbrScore = 5;
      }
      score += pbrScore;
      signals.add({
        "label": "💰 PBR (${pbrVal.toStringAsFixed(1)}倍)",
        "value": pbrSignal,
        "color": pbrColor,
      });
    }

    // スコアに基づく総合判定
    String overallLabel;
    Color overallColor;
    IconData overallIcon;
    if (score >= 70) {
      overallLabel = "強い買いシグナル";
      overallColor = Colors.red;
      overallIcon = Icons.trending_up;
    } else if (score >= 50) {
      overallLabel = "買い検討";
      overallColor = Colors.orange;
      overallIcon = Icons.thumb_up;
    } else if (score >= 35) {
      overallLabel = "様子見";
      overallColor = Colors.grey;
      overallIcon = Icons.remove;
    } else {
      overallLabel = "売り検討";
      overallColor = Colors.green;
      overallIcon = Icons.trending_down;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 総合スコアカード
          Card(
            elevation: 3,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [overallColor.withOpacity(0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    "総合スコア",
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "$score点",
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.bold,
                      color: overallColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(overallIcon, color: overallColor, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        overallLabel,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: overallColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // スコアバー
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: score / 100,
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(overallColor),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        "0",
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      Text(
                        "50",
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      Text(
                        "100",
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 各シグナル詳細
          const Text(
            "シグナル詳細",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          ...signals.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SignalCard(
                label: s["label"],
                value: s["value"],
                color: s["color"],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 価格帯の詳細
          const Text(
            "価格帯の詳細",
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
                      const Text(
                        "52週高値から",
                        style: TextStyle(color: Colors.grey),
                      ),
                      Text(
                        "-${distFromHighPct.toStringAsFixed(1)}%",
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
                      const Text(
                        "52週安値から",
                        style: TextStyle(color: Colors.grey),
                      ),
                      Text(
                        "+${distFromLowPct.toStringAsFixed(1)}%",
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

          const SizedBox(height: 12),
          // 注意書き
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "このスコアは参考値です。投資判断は自己責任でお願いします。",
                    style: TextStyle(fontSize: 11, color: Colors.brown),
                  ),
                ),
              ],
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
