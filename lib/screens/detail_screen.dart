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
  Map<String, dynamic>? aiAnalysis;
  bool isLoadingAi = false;

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

    // MACD計算
    double ema(List<double> data, int period) {
      if (data.length < period) return data.last;
      final k = 2 / (period + 1);
      double val = data.take(period).reduce((a, b) => a + b) / period;
      for (final v in data.skip(period)) val = v * k + val * (1 - k);
      return val;
    }

    final ema12 = ema(closes, 12);
    final ema26 = ema(closes, 26);
    final macd = ema12 - ema26;

    final per = detail!['per'];
    final pbr = detail!['pbr'];
    final dividendYield = detail!['dividend_yield'];
    final roe = detail!['roe'];

    // ── スコア計算 ──
    int score = 0;
    final List<Map<String, dynamic>> technicalSignals = [];
    final List<Map<String, dynamic>> fundamentalSignals = [];

    // RSI
    String rsiLabel;
    Color rsiColor;
    int rsiScore = 0;
    if (rsi <= 30) {
      rsiLabel = "売られすぎ（買いチャンス）";
      rsiColor = Colors.red;
      rsiScore = 20;
    } else if (rsi <= 45) {
      rsiLabel = "やや売られすぎ";
      rsiColor = Colors.orange;
      rsiScore = 10;
    } else if (rsi >= 70) {
      rsiLabel = "買われすぎ（過熱注意）";
      rsiColor = Colors.green;
      rsiScore = 0;
    } else if (rsi >= 55) {
      rsiLabel = "やや買われすぎ";
      rsiColor = Colors.teal;
      rsiScore = 5;
    } else {
      rsiLabel = "中立";
      rsiColor = Colors.grey;
      rsiScore = 10;
    }
    score += rsiScore;
    technicalSignals.add({
      "label": "RSI (${rsi.toStringAsFixed(1)})",
      "value": rsiLabel,
      "color": rsiColor,
    });

    // トレンド（MA）
    String maLabel;
    Color maColor;
    int maScore = 0;
    if (candles.length >= 2) {
      final prevMa5 =
          (candles[candles.length - 2]['ma5'] as num?)?.toDouble() ?? 0.0;
      final prevMa25 =
          (candles[candles.length - 2]['ma25'] as num?)?.toDouble() ?? 0.0;
      if (prevMa5 < prevMa25 && ma5 > ma25) {
        maLabel = "ゴールデンクロス発生！";
        maColor = Colors.red;
        maScore = 25;
      } else if (prevMa5 > prevMa25 && ma5 < ma25) {
        maLabel = "デッドクロス発生！";
        maColor = Colors.green;
        maScore = 0;
      } else if (ma5 > ma25) {
        maLabel = "上昇トレンド継続中";
        maColor = Colors.red;
        maScore = 20;
      } else {
        maLabel = "下降トレンド継続中";
        maColor = Colors.green;
        maScore = 5;
      }
    } else {
      maLabel = "データ不足";
      maColor = Colors.grey;
    }
    score += maScore;
    technicalSignals.add({
      "label": "移動平均線 (MA5/MA25)",
      "value": maLabel,
      "color": maColor,
    });

    // MACD
    String macdLabel;
    Color macdColor;
    int macdScore = 0;
    if (macd > 0) {
      macdLabel = "買いシグナル（プラス圏）";
      macdColor = Colors.red;
      macdScore = 15;
    } else if (macd > -50) {
      macdLabel = "やや弱い（マイナス圏）";
      macdColor = Colors.orange;
      macdScore = 5;
    } else {
      macdLabel = "売りシグナル";
      macdColor = Colors.green;
      macdScore = 0;
    }
    score += macdScore;
    technicalSignals.add({
      "label": "MACD (${macd.toStringAsFixed(1)})",
      "value": macdLabel,
      "color": macdColor,
    });

    // 価格帯
    String priceLabel;
    Color priceColor;
    int priceScore = 0;
    if (distFromLowPct <= 10) {
      priceLabel = "52週安値圏（割安ゾーン）";
      priceColor = Colors.red;
      priceScore = 15;
    } else if (distFromLowPct <= 25) {
      priceLabel = "安値寄り";
      priceColor = Colors.orange;
      priceScore = 8;
    } else if (distFromHighPct <= 5) {
      priceLabel = "52週高値圏（高値注意）";
      priceColor = Colors.green;
      priceScore = 0;
    } else if (distFromHighPct <= 15) {
      priceLabel = "高値寄り";
      priceColor = Colors.teal;
      priceScore = 3;
    } else {
      priceLabel = "中間帯";
      priceColor = Colors.grey;
      priceScore = 8;
    }
    score += priceScore;
    technicalSignals.add({
      "label": "価格帯",
      "value": priceLabel,
      "color": priceColor,
    });

    // PBR
    if (pbr != null) {
      final v = (pbr as num).toDouble();
      String l;
      Color c;
      int s = 0;
      if (v <= 1.0) {
        l = "1倍以下（割安）";
        c = Colors.red;
        s = 15;
      } else if (v <= 1.5) {
        l = "やや割安";
        c = Colors.orange;
        s = 8;
      } else if (v >= 5.0) {
        l = "割高注意";
        c = Colors.green;
        s = 0;
      } else {
        l = "適正水準";
        c = Colors.grey;
        s = 5;
      }
      score += s;
      fundamentalSignals.add({
        "label": "PBR (${v.toStringAsFixed(1)}倍)",
        "value": l,
        "color": c,
      });
    }

    // PER
    if (per != null) {
      final v = (per as num).toDouble();
      String l;
      Color c;
      int s = 0;
      if (v <= 10) {
        l = "10倍以下（割安）";
        c = Colors.red;
        s = 10;
      } else if (v <= 15) {
        l = "やや割安";
        c = Colors.orange;
        s = 5;
      } else if (v >= 30) {
        l = "割高注意";
        c = Colors.green;
        s = 0;
      } else {
        l = "適正水準";
        c = Colors.grey;
        s = 5;
      }
      score += s;
      fundamentalSignals.add({
        "label": "PER (${v.toStringAsFixed(1)}倍)",
        "value": l,
        "color": c,
      });
    }

    // ROE
    if (roe != null) {
      final v = (roe as num).toDouble() * 100;
      String l;
      Color c;
      int s = 0;
      if (v >= 15) {
        l = "高ROE（優良）";
        c = Colors.red;
        s = 10;
      } else if (v >= 8) {
        l = "標準的";
        c = Colors.grey;
        s = 5;
      } else {
        l = "低ROE（注意）";
        c = Colors.green;
        s = 0;
      }
      score += s;
      fundamentalSignals.add({
        "label": "ROE (${v.toStringAsFixed(1)}%)",
        "value": l,
        "color": c,
      });
    }

    // 配当
    if (dividendYield != null) {
      final v = (dividendYield as num).toDouble() * 100;
      String l;
      Color c;
      int s = 0;
      if (v >= 3.0) {
        l = "高配当（${v.toStringAsFixed(1)}%）";
        c = Colors.red;
        s = 5;
      } else if (v >= 1.5) {
        l = "配当あり（${v.toStringAsFixed(1)}%）";
        c = Colors.orange;
        s = 3;
      } else {
        l = "低配当・なし";
        c = Colors.grey;
        s = 0;
      }
      score += s;
      fundamentalSignals.add({"label": "配当利回り", "value": l, "color": c});
    }

    // 総合判定
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "$score点",
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: overallColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(overallIcon, color: overallColor, size: 18),
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
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: score / 100,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(overallColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // テクニカル分析
          const Text(
            "📈 テクニカル分析",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ...technicalSignals.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SignalCard(
                label: s["label"],
                value: s["value"],
                color: s["color"],
              ),
            ),
          ),

          // 52週価格帯バー
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "52週レンジ内の現在位置",
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ((latest - low52) / (high52 - low52)).clamp(
                        0.0,
                        1.0,
                      ),
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "安値 ¥${low52.toStringAsFixed(0)}",
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.blue,
                        ),
                      ),
                      Text(
                        "現在 ¥${latest.toStringAsFixed(0)}",
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "高値 ¥${high52.toStringAsFixed(0)}",
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ファンダメンタル分析
          const Text(
            "💰 ファンダメンタル分析",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (fundamentalSignals.isEmpty)
            const Text(
              "ファンダメンタルデータなし",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            )
          else
            ...fundamentalSignals.map(
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
    final dividendYield = detail!['dividend_yield'];
    final roe = detail!['roe'];

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
          IndicatorRow(
            label: "配当利回り",
            value: dividendYield != null
                ? "${((dividendYield as num) * 100).toStringAsFixed(2)}%"
                : "---",
            description: "1株あたり配当金 ÷ 株価。高いほど配当が多い",
          ),
          IndicatorRow(
            label: "ROE（自己資本利益率）",
            value: roe != null
                ? "${((roe as num) * 100).toStringAsFixed(1)}%"
                : "---",
            description: "自己資本でどれだけ利益を生んだか。15%以上が優良",
          ),
        ],
      ),
    );
  }

  Widget _buildAiTab() {
    if (isLoadingAi) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("AIが分析中...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (aiAnalysis == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.smart_toy, size: 60, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              "AI分析",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _loadAiAnalysis,
              icon: const Icon(Icons.auto_awesome),
              label: const Text("AI分析を実行する"),
            ),
          ],
        ),
      );
    }

    final a = aiAnalysis!['analysis'] as Map<String, dynamic>? ?? {};
    final news = aiAnalysis!['news'] as List? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI総合スコア
          _aiScoreCard(a),
          const SizedBox(height: 16),

          // ニュースセンチメント＋要約
          const Text(
            "📰 最近のニュース",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _aiNewsCard(a, news),
          const SizedBox(height: 16),

          // リスク・機会
          _aiRisksAndOpportunities(a),
          const SizedBox(height: 16),

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
                    "このAI分析は参考値です。投資判断は自己責任でお願いします。",
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

  Future<void> _loadAiAnalysis() async {
    setState(() => isLoadingAi = true);
    try {
      final data = await StockService.getAiAnalysis(widget.code);
      setState(() => aiAnalysis = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("AI分析エラー: $e")));
      }
    } finally {
      setState(() => isLoadingAi = false);
    }
  }

  Widget _aiScoreCard(Map<String, dynamic> a) {
    final score = (a['overall_score'] as num?)?.toInt() ?? 0;
    final judgment = a['overall_judgment'] as String? ?? 'hold';
    final reason = a['overall_reason'] as String? ?? '';
    final judgeMap = {
      'buy': ('買い推奨', Colors.red, Icons.arrow_upward),
      'sell': ('売り推奨', Colors.green, Icons.arrow_downward),
      'hold': ('保有継続', Colors.blue, Icons.pause),
      'watch': ('要注目', Colors.orange, Icons.visibility),
    };
    final (label, color, icon) =
        judgeMap[judgment] ?? ('様子見', Colors.grey, Icons.remove);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Text(
              "AI総合スコア",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            Text(
              "$score点",
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                reason,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _aiNewsCard(Map<String, dynamic> a, List news) {
    final sentimentMap = {
      'positive': ('ポジティブ', Colors.red),
      'negative': ('ネガティブ', Colors.green),
      'neutral': ('中立', Colors.grey),
    };
    final (sentLabel, sentColor) =
        sentimentMap[a['news_sentiment']] ?? ('不明', Colors.grey);
    final summary = a['news_summary'] as String? ?? '';
    final reason = a['news_sentiment_reason'] as String? ?? '';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // センチメント
            Row(
              children: [
                const SizedBox(
                  width: 90,
                  child: Text(
                    "ニュースの雰囲気",
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: sentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    sentLabel,
                    style: TextStyle(
                      color: sentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                reason,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
            if (summary.isNotEmpty) ...[
              const Divider(height: 16),
              Text(
                summary,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ],
            if (news.isNotEmpty) ...[
              const Divider(height: 16),
              ...news.map((n) => _aiNewsItem(n as Map<String, dynamic>)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _aiNewsItem(Map<String, dynamic> n) {
    final title = n['title'] as String? ?? '';
    final provider = n['provider'] as String? ?? '';
    final pubDate = n['pub_date'] as String? ?? '';
    String dateStr = '';
    if (pubDate.isNotEmpty) {
      try {
        final dt = DateTime.parse(pubDate).toLocal();
        dateStr =
            "${dt.month}/${dt.day} "
            "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      } catch (_) {}
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.article_outlined, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (provider.isNotEmpty || dateStr.isNotEmpty)
                  Text(
                    "$provider　$dateStr",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiRisksAndOpportunities(Map<String, dynamic> a) {
    final risks = a['risks'] as List? ?? [];
    final opportunities = a['opportunities'] as List? ?? [];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "⚠️ リスク",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ...risks.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "・",
                            style: TextStyle(fontSize: 12, color: Colors.red),
                          ),
                          Expanded(
                            child: Text(
                              r.toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "✨ 機会",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ...opportunities.map(
                    (o) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "・",
                            style: TextStyle(fontSize: 12, color: Colors.green),
                          ),
                          Expanded(
                            child: Text(
                              o.toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
