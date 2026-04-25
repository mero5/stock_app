import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:candlesticks_plus/candlesticks_plus.dart';
import 'package:candlesticks_plus/src/models/candle_style.dart';
import '../services/stock_service.dart';
import '../utils/formatter.dart';
import '../widgets/signal_card.dart';
import '../widgets/indicator_row.dart';
import 'dart:async';

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
  String _selectedPeriod = '短期';
  // AI分析（新スイング分析用）
  final Map<String, bool> _analysisChecks = {
    'technical': true,
    'fundamental': true,
    'macro': false,
    'supply': false,
    'news': false,
  };
  Map<String, dynamic>? _aiResult;
  bool _isAnalyzing = false;
  double _analysisProgress = 0.0;

  // ニュースタブ用
  List<Map<String, dynamic>> _newsItems = [];
  bool _isLoadingNews = false;
  double _newsProgress = 0.0;
  // 判断タブのスコアを保持
  int _currentScore = 0;

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

    // 株価が取れない場合（市場休場など）もエラーにしない
    final candles = List<Map<String, dynamic>>.from(detail!['candles'] ?? []);

    return DefaultTabController(
      length: 5,
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
              Tab(icon: Icon(Icons.show_chart), text: "テクニカル"),
              Tab(icon: Icon(Icons.account_balance), text: "ファンダ"),
              Tab(icon: Icon(Icons.smart_toy), text: "AI分析"),
              Tab(icon: Icon(Icons.newspaper), text: "ニュース"),
            ],
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            labelStyle: TextStyle(fontSize: 11),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildChartTab(candles),
                _buildJudgeTab(candles),
                _buildIndicatorTab(),
                _buildAiTab(),
                _buildNewsTab(),
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
                  // 5桁→4桁表示
                  RegExp(r'^\d{5}$').hasMatch(widget.code)
                      ? widget.code.substring(0, 4)
                      : widget.code,
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
                if (change != null && changePct != null)
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
          // ローソク足
          const Text(
            "ローソク足チャート",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          _buildCandleChart(candles),
          const SizedBox(height: 16),

          // MA折れ線チャート（日付付き）
          const Text(
            "移動平均線 (MA5 / MA25)",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          _buildMaChart(candles),
          const SizedBox(height: 16),

          // ボリンジャーバンド
          const Text(
            "ボリンジャーバンド (±2σ)",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          _buildBollingerChart(candles),
          const SizedBox(height: 16),

          // RSI
          const Text(
            "RSI (14)",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            "30以下：売られすぎ  70以上：買われすぎ",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          _buildRsiChart(candles),
          const SizedBox(height: 16),

          // MACD
          const Text(
            "MACD (12/26)",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            "0より上：買いシグナル  0より下：売りシグナル",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          _buildMacdChart(candles),
        ],
      ),
    );
  }

  Widget _buildJudgeTab(List<Map<String, dynamic>> candles) {
    if (candles.isEmpty) return const Center(child: Text("データなし"));

    final closes = candles
        .map((c) => (c['close'] as num?)?.toDouble() ?? 0.0)
        .toList();

    if (closes.isEmpty || closes.every((v) => v == 0.0)) {
      return const Center(child: Text("株価データを取得できませんでした（市場休場日の可能性があります）"));
    }

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

    final bbUpper = (candles.last['bb_upper'] as num?)?.toDouble();
    final bbMiddle = (candles.last['bb_middle'] as num?)?.toDouble();
    final bbLower = (candles.last['bb_lower'] as num?)?.toDouble();

    // ── RSI判定 ──
    String rsiLabel;
    Color rsiColor;
    String rsiReason;
    if (rsi <= 30) {
      rsiLabel = "売られすぎ";
      rsiColor = Colors.red;
      rsiReason =
          "RSIが${rsi.toStringAsFixed(1)}と30以下です。売りが過剰な状態で、反発・買い戻しが起きやすいゾーンです。逆張りの買いチャンスとして注目されます。ただし下降トレンド中は売られすぎが続く場合もあります。";
    } else if (rsi <= 45) {
      rsiLabel = "やや売られすぎ";
      rsiColor = Colors.orange;
      rsiReason =
          "RSIが${rsi.toStringAsFixed(1)}と45以下です。売り圧力がやや強い水準です。完全な売られすぎではありませんが、反発の余地があります。他の指標と合わせて判断してください。";
    } else if (rsi >= 70) {
      rsiLabel = "買われすぎ・過熱注意";
      rsiColor = Colors.green;
      rsiReason =
          "RSIが${rsi.toStringAsFixed(1)}と70以上です。買いが過熱している状態で、短期的な調整（株価下落）が起きやすいゾーンです。新規買いには注意が必要です。";
    } else if (rsi >= 55) {
      rsiLabel = "やや買われすぎ";
      rsiColor = Colors.teal;
      rsiReason =
          "RSIが${rsi.toStringAsFixed(1)}と55〜70の水準です。買い優勢ですがまだ過熱とは言えません。上昇トレンドが継続している可能性があります。";
    } else {
      rsiLabel = "中立";
      rsiColor = Colors.grey;
      rsiReason =
          "RSIが${rsi.toStringAsFixed(1)}と45〜55の中立ゾーンです。買いも売りも優勢ではない状態です。方向感が出るまで様子見が無難です。";
    }

    // ── MA判定 ──
    String maLabel;
    Color maColor;
    String maReason;
    if (candles.length >= 2) {
      final prevMa5 =
          (candles[candles.length - 2]['ma5'] as num?)?.toDouble() ?? 0.0;
      final prevMa25 =
          (candles[candles.length - 2]['ma25'] as num?)?.toDouble() ?? 0.0;
      if (prevMa5 < prevMa25 && ma5 > ma25) {
        maLabel = "ゴールデンクロス発生！";
        maColor = Colors.red;
        maReason =
            "短期移動平均（MA5=${ma5.toStringAsFixed(0)}円）が長期移動平均（MA25=${ma25.toStringAsFixed(0)}円）を下から上に突き抜けました。これをゴールデンクロスと呼び、買いシグナルの中でも特に強力なシグナルです。上昇トレンドへの転換を示唆しています。";
      } else if (prevMa5 > prevMa25 && ma5 < ma25) {
        maLabel = "デッドクロス発生！";
        maColor = Colors.green;
        maReason =
            "短期移動平均（MA5=${ma5.toStringAsFixed(0)}円）が長期移動平均（MA25=${ma25.toStringAsFixed(0)}円）を上から下に突き抜けました。これをデッドクロスと呼び、売りシグナルの中でも特に強力なシグナルです。下降トレンドへの転換を示唆しています。";
      } else if (ma5 > ma25) {
        maLabel = "上昇トレンド継続中";
        maColor = Colors.red;
        maReason =
            "MA5（${ma5.toStringAsFixed(0)}円）がMA25（${ma25.toStringAsFixed(0)}円）を上回っています。短期の平均価格が中期の平均価格より高い状態で、上昇の勢いが継続中と判断できます。差が大きいほど上昇の勢いが強い状態です。";
      } else {
        maLabel = "下降トレンド継続中";
        maColor = Colors.green;
        maReason =
            "MA5（${ma5.toStringAsFixed(0)}円）がMA25（${ma25.toStringAsFixed(0)}円）を下回っています。短期の平均価格が中期の平均価格より低い状態で、下降の勢いが継続中と判断できます。反発の兆候が出るまで慎重な対応が必要です。";
      }
    } else {
      maLabel = "データ不足";
      maColor = Colors.grey;
      maReason = "移動平均の計算に必要なデータが不足しています。";
    }

    // ── MACD判定 ──
    String macdLabel;
    Color macdColor;
    String macdReason;
    if (macd > 0) {
      macdLabel = "買いシグナル（プラス圏）";
      macdColor = Colors.red;
      macdReason =
          "MACDが${macd.toStringAsFixed(1)}とプラス圏にあります。短期EMA（12日）が長期EMA（26日）を上回っており、上昇モメンタムが強い状態です。値が大きいほど上昇の勢いが強いことを示します。";
    } else if (macd > -50) {
      macdLabel = "やや弱い（マイナス圏）";
      macdColor = Colors.orange;
      macdReason =
          "MACDが${macd.toStringAsFixed(1)}と小幅なマイナス圏にあります。短期EMAが長期EMAを若干下回っている状態です。まだ深刻な売りシグナルではありませんが、慎重な姿勢が必要です。";
    } else {
      macdLabel = "売りシグナル";
      macdColor = Colors.green;
      macdReason =
          "MACDが${macd.toStringAsFixed(1)}と大きくマイナス圏にあります。下降モメンタムが強く、売り圧力が続いている状態です。トレンド転換のシグナルが出るまで新規買いは慎重に行う必要があります。";
    }

    // ── ボリンジャーバンド判定 ──
    String? bbLabel;
    Color? bbColor;
    String? bbReason;
    if (bbUpper != null && bbLower != null && bbMiddle != null) {
      if (latest <= bbLower) {
        bbLabel = "下限タッチ・反発の可能性";
        bbColor = Colors.red;
        bbReason =
            "現在株価（${latest.toStringAsFixed(0)}円）がボリンジャーバンド下限（${bbLower.toStringAsFixed(0)}円）に接触しています。統計的に株価の約95%はバンド内に収まるため、下限タッチは反発が起きやすいポイントです。ただし強い下降トレンド中はバンドをはみ出して推移する「バンドウォーク」が起きる場合もあります。";
      } else if (latest >= bbUpper) {
        bbLabel = "上限タッチ・過熱注意";
        bbColor = Colors.green;
        bbReason =
            "現在株価（${latest.toStringAsFixed(0)}円）がボリンジャーバンド上限（${bbUpper.toStringAsFixed(0)}円）に接触しています。上昇が行き過ぎている可能性があり、短期的な調整が起きやすいポイントです。強い上昇トレンド中はバンドウォークが起きる場合もあります。";
      } else if (latest < (bbUpper + bbLower) / 2) {
        bbLabel = "バンド内・中央線より下";
        bbColor = Colors.orange;
        bbReason =
            "現在株価（${latest.toStringAsFixed(0)}円）がボリンジャーバンド中央線（${bbMiddle.toStringAsFixed(0)}円）より下に位置しています。中立よりやや弱い水準で、下限（${bbLower.toStringAsFixed(0)}円）に向かうか、中央線を上抜けるかが注目ポイントです。";
      } else {
        bbLabel = "バンド内・中央線より上";
        bbColor = Colors.teal;
        bbReason =
            "現在株価（${latest.toStringAsFixed(0)}円）がボリンジャーバンド中央線（${bbMiddle.toStringAsFixed(0)}円）より上に位置しています。中立よりやや強い水準で、上限（${bbUpper.toStringAsFixed(0)}円）に向かうか、中央線を割り込むかが注目ポイントです。";
      }
    }

    // ── 52週価格帯判定 ──
    final distFromLow = (latest - low52) / low52 * 100;
    final distFromHigh = (high52 - latest) / high52 * 100;
    String priceLabel;
    Color priceColor;
    String priceReason;
    if (distFromLow <= 10) {
      priceLabel = "52週安値圏";
      priceColor = Colors.red;
      priceReason =
          "現在株価（${latest.toStringAsFixed(0)}円）が52週安値（${low52.toStringAsFixed(0)}円）から${distFromLow.toStringAsFixed(1)}%の水準にあります。年間の底値に近い割安ゾーンで、長期的な買い場として注目されやすい価格帯です。";
    } else if (distFromLow <= 25) {
      priceLabel = "安値寄りの水準";
      priceColor = Colors.orange;
      priceReason =
          "52週安値から${distFromLow.toStringAsFixed(1)}%上昇した水準にあります。年間レンジの下位25%に位置しており、比較的割安な水準です。";
    } else if (distFromHigh <= 5) {
      priceLabel = "52週高値圏・高値注意";
      priceColor = Colors.green;
      priceReason =
          "現在株価（${latest.toStringAsFixed(0)}円）が52週高値（${high52.toStringAsFixed(0)}円）から${distFromHigh.toStringAsFixed(1)}%の水準にあります。年間の天井付近で割高感があります。新規買いには注意が必要です。";
    } else if (distFromHigh <= 15) {
      priceLabel = "高値寄りの水準";
      priceColor = Colors.teal;
      priceReason =
          "52週高値から${distFromHigh.toStringAsFixed(1)}%下の水準にあります。年間レンジの上位15%に位置しており、やや高値圏です。";
    } else {
      priceLabel = "中間帯";
      priceColor = Colors.grey;
      priceReason = "52週の高値・安値の中間帯に位置しています。特に割安でも割高でもない中立水準です。";
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── ヘッダー ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'テクニカル分析は過去の株価パターンから将来の動きを予測する手法です。複数の指標を組み合わせて判断することが重要です。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── RSI ──
          _technicalCard(
            title: 'RSI（相対力指数）',
            subtitle: '現在値：${rsi.toStringAsFixed(1)}',
            label: rsiLabel,
            color: rsiColor,
            reason: rsiReason,
            infoTitle: 'RSIとは',
            infoContent: '''【RSI（Relative Strength Index）とは】
  過去14日間の「上昇幅の平均」と「下落幅の平均」の比率から、買われすぎ・売られすぎを0〜100の数値で表したテクニカル指標です。

  【見方】
  ・0〜30：売られすぎゾーン（反発・上昇しやすい）
  ・30〜45：やや売られすぎ
  ・45〜55：中立
  ・55〜70：やや買われすぎ
  ・70〜100：買われすぎゾーン（調整・下落しやすい）

  【計算式】
  RSI = 100 − (100 ÷ (1 + 平均上昇幅 ÷ 平均下落幅))

  【注意点】
  ・強いトレンドが続く時は長期間30以下・70以上に留まることがあります
  ・単独では判断せず、移動平均線やMACDと組み合わせるのが基本です
  ・本アプリでは14日間を使用しています''',
          ),
          const SizedBox(height: 8),

          // ── 移動平均線 ──
          _technicalCard(
            title: '移動平均線（MA5 / MA25）',
            subtitle:
                'MA5：${ma5.toStringAsFixed(0)}円  MA25：${ma25.toStringAsFixed(0)}円',
            label: maLabel,
            color: maColor,
            reason: maReason,
            infoTitle: '移動平均線とは',
            infoContent: '''【移動平均線（Moving Average）とは】
  過去N日間の終値の平均を繋いだ線です。価格のトレンドを視覚化するための最も基本的な指標です。

  【本アプリで使用している移動平均線】
  ・MA5（5日移動平均）：直近5日間の終値の平均。短期トレンドを示す
  ・MA25（25日移動平均）：直近25日間の終値の平均。中期トレンドを示す

  【ゴールデンクロスとは】
  短期MA（MA5）が長期MA（MA25）を下から上に突き抜けること。買いシグナルとして有名です。上昇トレンドへの転換を示唆します。

  【デッドクロスとは】
  短期MA（MA5）が長期MA（MA25）を上から下に突き抜けること。売りシグナルとして有名です。下降トレンドへの転換を示唆します。

  【上昇トレンド・下降トレンドの判断基準】
  ・MA5 ＞ MA25 → 上昇トレンド（短期平均が中期平均を上回っている）
  ・MA5 ＜ MA25 → 下降トレンド（短期平均が中期平均を下回っている）

  【注意点】
  移動平均線は「遅行指標」です。実際のトレンド転換より遅れてシグナルが出ます。急激な価格変動には対応が遅れる場合があります。''',
          ),
          const SizedBox(height: 8),

          // ── MACD ──
          _technicalCard(
            title: 'MACD（マックディー）',
            subtitle: '現在値：${macd.toStringAsFixed(1)}',
            label: macdLabel,
            color: macdColor,
            reason: macdReason,
            infoTitle: 'MACDとは',
            infoContent: '''【MACD（Moving Average Convergence/Divergence）とは】
  短期EMA（12日）から長期EMA（26日）を引いた値です。移動平均線の収束・拡散を利用して、トレンドの方向と勢いを判断します。

  【本アプリの設定】
  ・短期EMA：12日
  ・長期EMA：26日
  ・MACD = EMA12 − EMA26

  【EMAとは】
  指数移動平均線（Exponential Moving Average）。直近のデータを重視する移動平均。通常の移動平均より価格変動への反応が速いのが特徴です。

  【見方】
  ・MACDがプラス → 短期EMAが長期EMAより上 → 上昇モメンタム
  ・MACDがマイナス → 短期EMAが長期EMAより下 → 下降モメンタム
  ・0をゼロラインと呼び、プラスかマイナスかが重要な判断基準

  【シグナルラインとは】
  本来はMACDの9日EMAをシグナルラインとして使いますが、本アプリでは現在MACDの値のみ使用しています。

  【注意点】
  MACDは後追い指標のため、急激な相場反転には対応が遅れる場合があります。''',
          ),
          const SizedBox(height: 8),

          // ── ボリンジャーバンド ──
          if (bbLabel != null && bbColor != null && bbReason != null)
            _technicalCard(
              title: 'ボリンジャーバンド（±2σ）',
              subtitle:
                  '上限：${bbUpper!.toStringAsFixed(0)}円  中央：${bbMiddle!.toStringAsFixed(0)}円  下限：${bbLower!.toStringAsFixed(0)}円',
              label: bbLabel!,
              color: bbColor!,
              reason: bbReason!,
              infoTitle: 'ボリンジャーバンドとは',
              infoContent: '''【ボリンジャーバンドとは】
  移動平均線（中央線）を中心に、上下に「標準偏差×2」の幅を持ったバンドを描いた指標です。統計的に株価の約95%はこのバンド内に収まると言われています。

  【本アプリの設定】
  ・中央線：20日移動平均
  ・上限バンド：20日移動平均 + 標準偏差×2
  ・下限バンド：20日移動平均 − 標準偏差×2

  【見方】
  ・上限タッチ：統計的に高すぎる水準。調整・下落が起きやすい
  ・下限タッチ：統計的に低すぎる水準。反発・上昇が起きやすい
  ・バンド収縮（幅が狭い）：大きな値動きの前兆
  ・バンド拡大（幅が広い）：強いトレンドが出ている状態

  【バンドウォークとは】
  強いトレンドが出ている時、株価がバンド上限（または下限）に沿って推移し続ける現象。単純な「上限タッチ＝売り」が機能しないケースです。

  【注意点】
  ボリンジャーバンドのタッチは「反転しやすい」という確率論的な話であり、必ず反転するわけではありません。''',
            ),
          if (bbLabel != null) const SizedBox(height: 8),

          // ── 52週価格帯 ──
          _technicalCard(
            title: '52週価格帯（年間レンジ）',
            subtitle:
                '安値：${low52.toStringAsFixed(0)}円  現在：${latest.toStringAsFixed(0)}円  高値：${high52.toStringAsFixed(0)}円',
            label: priceLabel,
            color: priceColor,
            reason: priceReason,
            infoTitle: '52週価格帯とは',
            infoContent: '''【52週価格帯とは】
  過去52週間（約1年間）の最高値と最安値の範囲のことです。現在の株価がその年間レンジのどこに位置しているかを示します。

  【見方】
  ・年間安値付近（下位10%）：割安ゾーン。長期投資の買い場として注目されやすい
  ・安値寄り（下位25%）：比較的割安な水準
  ・中間帯（25〜85%）：特に割安でも割高でもない中立水準
  ・高値寄り（上位15%）：やや高値圏。利確検討の水準
  ・年間高値付近（上位5%）：割高ゾーン。新規買いには注意

  【なぜ52週なのか】
  機関投資家や多くのトレーダーが参照する期間であり、意識されやすい節目となっているため、テクニカル上の重要な参考値とされています。

  【注意点】
  52週高値更新は強いシグナルになることもあります。「高値圏だから売り」とは一概に言えず、業績好調で新高値を更新し続ける銘柄も多数あります。''',
          ),
          const SizedBox(height: 8),

          // ── 52週レンジバー ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '52週レンジ内の現在位置',
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
                      minHeight: 12,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(priceColor),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '安値\n¥${low52.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.blue,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        '現在\n¥${latest.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        '高値\n¥${high52.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.orange,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 注意書き ──
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
                    'テクニカル分析は参考値です。投資判断は自己責任でお願いします。',
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
    final divYield = detail!['dividend_yield'];
    final roe = detail!['roe'];
    final roa = detail!['roa'];
    final revGrowth = detail!['revenue_growth'];
    final debtEquity = detail!['debt_to_equity'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.green, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ファンダメンタル分析は企業の財務・業績データから株価の本質的な価値を判断する手法です。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // PER
          _fundaCard(
            label: 'PER（株価収益率）',
            value: per != null
                ? '${Formatter.number(per, decimals: 1)}倍'
                : '---',
            judge: _perJudge(per),
            infoTitle: 'PERとは',
            infoContent: '''【PER（Price Earnings Ratio）とは】
  株価 ÷ 1株あたり利益（EPS）で計算される指標です。現在の株価が1年分の利益の何倍の価格になっているかを示します。

  【見方】
  ・10倍以下：割安（業績不振・成長鈍化の可能性も）
  ・10〜15倍：やや割安
  ・15〜25倍：適正水準（日本株平均は15倍前後）
  ・25〜30倍：やや割高
  ・30倍以上：割高（高成長期待が織り込まれている）

  【注意点】
  ・赤字企業はPERを計算できません（マイナスになるため）
  ・成長株は高PERでも割安なケースがあります（PEGレシオで補完）
  ・業種によって適正PERは大きく異なります（公益・銀行は低め、IT・バイオは高め）

  【データソース】yfinance（trailingPE：過去12ヶ月の実績EPS使用）''',
          ),
          const SizedBox(height: 8),

          // PBR
          _fundaCard(
            label: 'PBR（株価純資産倍率）',
            value: pbr != null
                ? '${Formatter.number(pbr, decimals: 1)}倍'
                : '---',
            judge: _pbrJudge(pbr),
            infoTitle: 'PBRとは',
            infoContent: '''【PBR（Price Book-value Ratio）とは】
  株価 ÷ 1株あたり純資産（BPS）で計算される指標です。企業が保有する純資産（資産−負債）に対して株価が何倍かを示します。

  【見方】
  ・1倍以下：理論上、企業を解散させると株価以上の資産が戻ってくる「解散価値以下」の割安水準
  ・1〜1.5倍：割安〜適正
  ・1.5〜5倍：適正〜やや割高
  ・5倍以上：高い成長期待・ブランド価値が反映されている

  【なぜ1倍が重要なのか】
  PBR1倍が「理論上の最低限の価値」とされており、機関投資家やバリュー投資家が注目する水準です。東証もPBR1倍割れ企業に改善を要請しています（2023年〜）。

  【注意点】
  ・製造業・金融業と無形資産が多いIT企業ではPBRの意味が異なります
  ・純資産の質（含み損益など）によって実態が変わります

  【データソース】yfinance（priceToBook使用）''',
          ),
          const SizedBox(height: 8),

          // ROE
          _fundaCard(
            label: 'ROE（自己資本利益率）',
            value: roe != null
                ? '${((roe as num) * 100).toStringAsFixed(1)}%'
                : '---',
            judge: _roeJudge(roe),
            infoTitle: 'ROEとは',
            infoContent: '''【ROE（Return On Equity）とは】
  当期純利益 ÷ 自己資本 × 100（%）で計算されます。株主が出資したお金（自己資本）をどれだけ効率よく利益に変えているかを示す収益性指標です。

  【見方】
  ・15%以上：優良（外国人投資家が好む水準）
  ・8〜15%：標準的
  ・5〜8%：やや低い
  ・5%未満：低い（資本効率が悪い）
  ・マイナス：赤字

  【なぜROEが重要なのか】
  ウォーレン・バフェットも重視する指標で、「株主のお金を有効活用できているか」を示します。日本企業は欧米と比べてROEが低いとされており、企業改革の文脈でよく登場します。

  【注意点】
  ・自社株買いや借入増加でROEを人工的に上げることができます
  ・ROEだけでなくROA（総資産利益率）と組み合わせて見ることが重要です

  【データソース】yfinance（returnOnEquity使用）''',
          ),
          const SizedBox(height: 8),

          // ROA
          if (roa != null) ...[
            _fundaCard(
              label: 'ROA（総資産利益率）',
              value: '${((roa as num) * 100).toStringAsFixed(1)}%',
              judge: _roaJudge(roa),
              infoTitle: 'ROAとは',
              infoContent: '''【ROA（Return On Assets）とは】
  当期純利益 ÷ 総資産 × 100（%）で計算されます。企業が保有する全資産（自己資本＋負債）をどれだけ効率よく利益に変えているかを示す指標です。

  【見方】
  ・10%以上：非常に優秀
  ・5〜10%：優良
  ・3〜5%：標準的
  ・3%未満：低い

  【ROEとの違い】
  ・ROE：株主の視点（自己資本の効率性）
  ・ROA：経営者の視点（全資産の効率性）
  ROAはレバレッジ（借入）の影響を受けにくいため、企業本来の収益力を示します。

  【データソース】yfinance（returnOnAssets使用）''',
            ),
            const SizedBox(height: 8),
          ],

          // 配当利回り
          _fundaCard(
            label: '配当利回り',
            value: divYield != null
                ? '${((divYield as num) * 100).toStringAsFixed(2)}%'
                : '---',
            judge: _dividendJudge(divYield),
            infoTitle: '配当利回りとは',
            infoContent: '''【配当利回りとは】
  1株あたり年間配当金 ÷ 現在株価 × 100（%）で計算されます。株価に対して年間どれだけの配当金を受け取れるかを示す指標です。

  【見方】
  ・3%以上：高配当（インカム投資家に人気）
  ・1.5〜3%：配当あり・普通水準
  ・1.5%未満：低配当
  ・0%：無配当（成長投資に資本を集中している場合もある）

  【日本株の平均配当利回り】
  東証プライムの平均は約2〜2.5%（2024年時点）

  【注意点】
  ・業績悪化により配当が減配・無配になるリスクがあります（配当トラップ）
  ・株価が下落すると利回りは上がりますが、それは良い兆候とは限りません
  ・増配傾向（配当が増えている企業）かどうかも重要な確認ポイントです

  【データソース】yfinance（dividendYield使用）''',
          ),
          const SizedBox(height: 8),

          // 売上成長率
          if (revGrowth != null) ...[
            _fundaCard(
              label: '売上成長率（前年比）',
              value: '${((revGrowth as num) * 100).toStringAsFixed(1)}%',
              judge: _revGrowthJudge(revGrowth),
              infoTitle: '売上成長率とは',
              infoContent: '''【売上成長率とは】
  前年同期と比較した売上高の増減率です。企業の事業拡大スピードを示す最も基本的な成長指標です。

  【見方】
  ・10%以上：高成長（成長株として評価されやすい）
  ・5〜10%：良好な成長
  ・0〜5%：微増（安定しているが成長は鈍い）
  ・マイナス：減収（要注意・業績悪化の可能性）

  【注意点】
  ・売上が伸びていても利益が出ていなければ意味がありません（利益率も確認）
  ・一時的な要因（M&A・会計基準変更）で大きく変動することがあります
  ・業種によって適正な成長率は異なります

  【データソース】yfinance（revenueGrowth使用・直近12ヶ月）''',
            ),
            const SizedBox(height: 8),
          ],

          // 負債比率
          if (debtEquity != null) ...[
            _fundaCard(
              label: '負債比率（D/Eレシオ）',
              value: '${(debtEquity as num).toStringAsFixed(0)}%',
              judge: _debtJudge(debtEquity),
              infoTitle: '負債比率（D/Eレシオ）とは',
              infoContent: '''【D/Eレシオ（Debt to Equity Ratio）とは】
  有利子負債 ÷ 自己資本 × 100（%）で計算されます。自己資本に対してどれだけの借入があるかを示す財務安全性の指標です。

  【見方】
  ・50%以下：低負債（財務安全性が高い）
  ・50〜150%：標準的
  ・150%以上：高負債（金利上昇・業績悪化時のリスクが高い）

  【注意点】
  ・銀行・保険・不動産などの業種は構造上負債が多く、高D/Eが正常です
  ・成長投資のために借入を増やしている場合は一概に悪いとは言えません
  ・金利上昇局面では高負債企業の業績が悪化するリスクがあります

  【データソース】yfinance（debtToEquity使用）''',
            ),
            const SizedBox(height: 8),
          ],

          // 時価総額
          _fundaCard(
            label: '時価総額',
            value: Formatter.marketCap(detail!['market_cap']),
            judge: null,
            infoTitle: '時価総額とは',
            infoContent: '''【時価総額とは】
  現在の株価 × 発行済み株式数で計算されます。市場が企業全体に付けている価格（評価額）です。

  【規模の目安（日本株）】
  ・1兆円以上：大型株（機関投資家が中心）
  ・1000億〜1兆円：中型株
  ・1000億円未満：小型株（流動性に注意）

  【なぜ重要か】
  ・大型株は流動性が高く、売買しやすい
  ・小型株は値動きが大きく、ハイリスク・ハイリターン
  ・M&Aの際の買収コストの目安にもなります

  【データソース】yfinance（marketCap使用）''',
          ),
          const SizedBox(height: 16),

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
                    'ファンダメンタル指標は参考値です。投資判断は自己責任でお願いします。',
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

  Widget _buildAiTab() {
    final candles = List<Map<String, dynamic>>.from(detail!['candles'] ?? []);
    final lastCandle = candles.isNotEmpty ? candles.last : <String, dynamic>{};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 期間選択 ──
          const Text(
            '分析期間',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Row(
            children: ['短期', '中期', '長期'].map((v) {
              final selected = _selectedPeriod == v;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedPeriod = v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? Colors.blue : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? Colors.blue : Colors.grey.shade300,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            v,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: selected ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            v == '短期'
                                ? '1〜2週間'
                                : v == '中期'
                                ? '1〜3ヶ月'
                                : '6ヶ月以上',
                            style: TextStyle(
                              fontSize: 10,
                              color: selected ? Colors.white70 : Colors.grey,
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

          // ── 分析ボタン ──
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isAnalyzing ? null : () => _runAiAnalysis(lastCandle),
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
              label: Text(_isAnalyzing ? '分析中...' : 'AI分析を実行'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),

          // ── プログレスバー ──
          if (_isAnalyzing) ...[
            const SizedBox(height: 16),
            _buildProgressBar(),
          ],

          // ── 結果表示 ──
          if (_aiResult != null && !_isAnalyzing) ...[
            const SizedBox(height: 20),
            _buildAiResultCard(_aiResult!),
          ],
        ],
      ),
    );
  }

  Widget _buildNewsTab() {
    if (_isLoadingNews) {
      final steps = [
        'ニュースを取得中...',
        '記事を解析中...',
        'AIが日本語に翻訳中...',
        'ニュースを整理中...',
      ];
      final stepIndex = (_newsProgress * steps.length).floor().clamp(
        0,
        steps.length - 1,
      );

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.newspaper, size: 48, color: Colors.blue),
              const SizedBox(height: 20),
              Text(
                steps[stepIndex],
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _newsProgress,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_newsProgress * 100).toInt()}%',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (_newsItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.newspaper, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '最近のニュース',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _loadNews,
              icon: const Icon(Icons.refresh),
              label: const Text('ニュースを取得する'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _newsItems.length,
      itemBuilder: (context, index) {
        final n = _newsItems[index];
        final title = n['title'] as String? ?? '';
        final summary = n['summary'] as String? ?? '';
        final provider = n['provider'] as String? ?? '';
        final pubDate = n['pub_date'] as String? ?? '';

        String dateStr = '';
        if (pubDate.isNotEmpty) {
          try {
            final dt = DateTime.parse(pubDate).toLocal();
            dateStr =
                '${dt.month}/${dt.day} '
                '${dt.hour.toString().padLeft(2, '0')}:'
                '${dt.minute.toString().padLeft(2, '0')}';
          } catch (_) {}
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: summary.isNotEmpty
                ? () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    builder: (_) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (provider.isNotEmpty || dateStr.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '$provider　$dateStr',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                          const Divider(height: 20),
                          const Text(
                            '📝 AIによる要約',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            summary,
                            style: const TextStyle(fontSize: 13, height: 1.6),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  )
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.article_outlined,
                    size: 18,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (provider.isNotEmpty || dateStr.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            '$provider　$dateStr',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (summary.isNotEmpty)
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Colors.grey,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadNews() async {
    setState(() {
      _isLoadingNews = true;
      _newsProgress = 0.0;
    });

    // 疑似プログレス（APIが終わるまでゆっくり進む）
    final progressTimer = Timer.periodic(const Duration(milliseconds: 300), (
      timer,
    ) {
      if (!_isLoadingNews) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_newsProgress < 0.9) {
          _newsProgress += 0.018; // 約5秒で85%
        }
      });
    });

    try {
      final data = await StockService.getAiAnalysis(widget.code);
      final news = data['news'] as List? ?? [];
      progressTimer.cancel();
      setState(() {
        _newsProgress = 1.0;
        _newsItems = news.map((n) => n as Map<String, dynamic>).toList();
      });
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      progressTimer.cancel();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ニュース取得エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingNews = false);
    }
  }

  Widget _buildAiResultCard(Map<String, dynamic> r) {
    if (r.containsKey('error')) {
      return Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'エラー: ${r['error']}',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    final period = r['_period'] as String? ?? _selectedPeriod;
    final verdict = r['verdict'] as Map? ?? {};
    final prob = r['probability'] as Map? ?? {};
    final conf = r['confidence'] as Map? ?? {};
    final summary = r['summary'] as String? ?? '';

    final verdictValue = verdict['value'] as String? ?? 'sideways';
    final verdictMap = {
      'up': ('上昇', Colors.red, Icons.trending_up),
      'sideways': ('様子見', Colors.grey, Icons.trending_flat),
      'down': ('下落', Colors.green, Icons.trending_down),
    };
    final (vLabel, vColor, vIcon) =
        verdictMap[verdictValue] ?? ('様子見', Colors.grey, Icons.trending_flat);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 総合判定 ──
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [vColor.withOpacity(0.1), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(vIcon, color: vColor, size: 28),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '$period予測：$vLabel',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: vColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () =>
                          _showInfoSheet('総合判定について', _getInfoText('verdict')),
                      child: _infoIcon(),
                    ),
                  ],
                ),
                if ((verdict['reason'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    verdict['reason'],
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── 確率分布 ──
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoHeader('確率分布', '確率分布について', _getInfoText('probability')),
                const SizedBox(height: 12),
                _probBar('上昇', prob['up']?['value'] ?? 0, Colors.red),
                if ((prob['up']?['reason'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 56, top: 2, bottom: 6),
                    child: Text(
                      prob['up']['reason'],
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                        height: 1.5,
                      ),
                    ),
                  ),
                _probBar('様子見', prob['sideways']?['value'] ?? 0, Colors.grey),
                if ((prob['sideways']?['reason'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 56, top: 2, bottom: 6),
                    child: Text(
                      prob['sideways']['reason'],
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                        height: 1.5,
                      ),
                    ),
                  ),
                _probBar('下落', prob['down']?['value'] ?? 0, Colors.green),
                if ((prob['down']?['reason'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 56, top: 2, bottom: 6),
                    child: Text(
                      prob['down']['reason'],
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ── 短期のみ：価格戦略 ──
        if (period == '短期') ...[
          _buildPriceStrategyCard(r),
          const SizedBox(height: 8),
        ],

        // ── 中期のみ：価格見通し・トレンド強度 ──
        if (period == '中期') ...[
          _buildMidTermCards(r),
          const SizedBox(height: 8),
        ],

        // ── 長期のみ：ファンダ分析・バリュエーション ──
        if (period == '長期') ...[
          _buildLongTermCards(r),
          const SizedBox(height: 8),
        ],

        // ── リスク・好材料（全期間共通） ──
        _buildRiskOpportunityCards(r),
        const SizedBox(height: 8),

        // ── マクロ分析（全期間共通） ──
        _buildMacroCard(r),
        const SizedBox(height: 8),

        // ── 信頼度（全期間共通） ──
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _infoHeader('信頼度', '信頼度について', _getInfoText('confidence')),
                    const SizedBox(width: 8),
                    _confidenceBadge(conf['value'] as String? ?? 'low'),
                  ],
                ),
                if ((conf['reason'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    conf['reason'],
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ── 総合サマリー ──
        if (summary.isNotEmpty)
          Card(
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoHeader('📋 総合サマリー', '総合判定について', _getInfoText('verdict')),
                  const SizedBox(height: 8),
                  Text(
                    summary,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),

        // ── 免責 ──
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
                  'このAI分析は参考値です。投資判断は自己責任でお願いします。',
                  style: TextStyle(fontSize: 11, color: Colors.brown),
                ),
              ),
            ],
          ),
        ),
        // ── デバッグ：渡したデータ確認ボタン ──
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showPromptSheet(_aiResult!),
          icon: const Icon(Icons.code, size: 16),
          label: const Text('AIに渡したデータを確認', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey,
            side: const BorderSide(color: Colors.grey),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _probBar(String label, dynamic value, Color color) {
    final pct = (value is num ? value.toDouble() : 0.0).clamp(0.0, 100.0);
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 14,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(color.withOpacity(0.7)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${pct.toInt()}%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _priceRow(String label, String value, Color color, String reason) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _macroRow(String label, dynamic data) {
    if (data == null) return const SizedBox();
    final value = data['value'] as String? ?? '';
    final reason = data['reason'] as String? ?? '';

    final colorMap = {
      'risk_on': Colors.red,
      'risk_off': Colors.green,
      'neutral': Colors.grey,
      'positive': Colors.red,
      'negative': Colors.green,
      'strong': Colors.red,
      'weak': Colors.green,
      'high': Colors.red,
      'medium': Colors.orange,
      'low': Colors.grey,
      'undervalued': Colors.red,
      'fair': Colors.grey,
      'overvalued': Colors.green,
      'uptrend': Colors.red,
      'sideways': Colors.grey,
      'downtrend': Colors.green,
    };
    final color = colorMap[value] ?? Colors.grey;

    final labelMap = {
      'risk_on': 'リスクオン',
      'risk_off': 'リスクオフ',
      'neutral': '中立',
      'positive': 'ポジティブ',
      'negative': 'ネガティブ',
      'strong': '強い',
      'weak': '弱い',
      'high': '高',
      'medium': '中',
      'low': '低',
      'undervalued': '割安',
      'fair': '適正水準',
      'overvalued': '割高',
      'uptrend': '上昇トレンド',
      'sideways': '横ばい',
      'downtrend': '下降トレンド',
    };
    final displayValue = labelMap[value] ?? value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                displayValue,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            reason,
            style: const TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
      ],
    );
  }

  Widget _confidenceBadge(String value) {
    final map = {
      'high': ('高', Colors.green),
      'medium': ('中', Colors.orange),
      'low': ('低', Colors.red),
    };
    final (label, color) = map[value] ?? ('低', Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final steps = [
      '株価データを取得中...',
      'テクニカル指標を計算中...',
      'マクロ環境を分析中...',
      'AIが総合判断を生成中...',
      '結果を整理中...',
    ];
    final stepIndex = (_analysisProgress * steps.length).floor().clamp(
      0,
      steps.length - 1,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          steps[stepIndex],
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _analysisProgress,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${(_analysisProgress * 100).toInt()}%',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  Future<void> _runAiAnalysis(Map<String, dynamic> lastCandle) async {
    setState(() {
      _isAnalyzing = true;
      _aiResult = null;
      _analysisProgress = 0.0;
    });

    // ① 先にセクターデータを取得
    final sectorData = await StockService.getSectorTrends();

    final progressTimer = Timer.periodic(const Duration(milliseconds: 450), (
      timer,
    ) {
      if (!_isAnalyzing) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_analysisProgress < 0.9) {
          _analysisProgress += 0.03;
        }
      });
    });

    try {
      final result = await StockService.runSwingAnalysis(
        code: widget.code,
        name: widget.name,
        detail: detail!,
        lastCandle: lastCandle,
        checks: _analysisChecks,
        period: _selectedPeriod,
        sectorData: sectorData, // ② 取得したデータを渡す
      );
      progressTimer.cancel();
      setState(() {
        _analysisProgress = 1.0;
        _aiResult = result;
      });
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      progressTimer.cancel();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('AI分析エラー: $e')));
      }
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  Widget _buildCandleChart(List<Map<String, dynamic>> candles) {
    if (candles.isEmpty) return const Text("データなし");

    final data = candles.length > 60
        ? candles.sublist(candles.length - 60)
        : candles;

    final candleList = data.map((c) {
      return Candle(
        date: DateTime.parse(c['date'] + 'T09:00:00'),
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

  // 日付ラベル生成ヘルパー
  String _dateLabel(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return "${dt.month}/${dt.day}";
    } catch (_) {
      return '';
    }
  }

  // MA折れ線チャート（日付軸付き）
  Widget _buildMaChart(List<Map<String, dynamic>> candles) {
    if (candles.isEmpty) return const Text("データなし");
    final data = candles.length > 60
        ? candles.sublist(candles.length - 60)
        : candles;

    final closeSpots = data
        .asMap()
        .entries
        .where((e) => e.value['close'] != null)
        .map(
          (e) => FlSpot(e.key.toDouble(), (e.value['close'] as num).toDouble()),
        )
        .toList();
    final ma5Spots = data
        .asMap()
        .entries
        .where((e) => e.value['ma5'] != null)
        .map(
          (e) => FlSpot(e.key.toDouble(), (e.value['ma5'] as num).toDouble()),
        )
        .toList();
    final ma25Spots = data
        .asMap()
        .entries
        .where((e) => e.value['ma25'] != null)
        .map(
          (e) => FlSpot(e.key.toDouble(), (e.value['ma25'] as num).toDouble()),
        )
        .toList();

    // 日付ラベル（10本おき）
    final labelIndices = <int>{0, data.length ~/ 2, data.length - 1};

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (!labelIndices.contains(i) || i >= data.length)
                    return const SizedBox();
                  return Text(
                    _dateLabel(data[i]['date']),
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
              ),
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
              spots: closeSpots,
              color: Colors.black54,
              barWidth: 1,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: ma5Spots,
              color: Colors.blue,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: ma25Spots,
              color: Colors.orange,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  // ボリンジャーバンドチャート
  Widget _buildBollingerChart(List<Map<String, dynamic>> candles) {
    if (candles.isEmpty) return const Text("データなし");
    final data = candles.length > 60
        ? candles.sublist(candles.length - 60)
        : candles;

    final closeSpots = data
        .asMap()
        .entries
        .where((e) => e.value['close'] != null)
        .map(
          (e) => FlSpot(e.key.toDouble(), (e.value['close'] as num).toDouble()),
        )
        .toList();
    final upperSpots = data
        .asMap()
        .entries
        .where((e) => e.value['bb_upper'] != null)
        .map(
          (e) =>
              FlSpot(e.key.toDouble(), (e.value['bb_upper'] as num).toDouble()),
        )
        .toList();
    final middleSpots = data
        .asMap()
        .entries
        .where((e) => e.value['bb_middle'] != null)
        .map(
          (e) => FlSpot(
            e.key.toDouble(),
            (e.value['bb_middle'] as num).toDouble(),
          ),
        )
        .toList();
    final lowerSpots = data
        .asMap()
        .entries
        .where((e) => e.value['bb_lower'] != null)
        .map(
          (e) =>
              FlSpot(e.key.toDouble(), (e.value['bb_lower'] as num).toDouble()),
        )
        .toList();

    final labelIndices = <int>{0, data.length ~/ 2, data.length - 1};

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (!labelIndices.contains(i) || i >= data.length)
                    return const SizedBox();
                  return Text(
                    _dateLabel(data[i]['date']),
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
              ),
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
              spots: upperSpots,
              color: Colors.red.withOpacity(0.5),
              barWidth: 1,
              dotData: const FlDotData(show: false),
              dashArray: [4, 4],
            ),
            LineChartBarData(
              spots: middleSpots,
              color: Colors.grey,
              barWidth: 1,
              dotData: const FlDotData(show: false),
              dashArray: [4, 4],
            ),
            LineChartBarData(
              spots: lowerSpots,
              color: Colors.blue.withOpacity(0.5),
              barWidth: 1,
              dotData: const FlDotData(show: false),
              dashArray: [4, 4],
            ),
            LineChartBarData(
              spots: closeSpots,
              color: Colors.black87,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  // ℹ️ アイコンのみのウィジェット
  Widget _infoIcon() {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.info_outline, size: 12, color: Colors.blue),
    );
  }

  // 短期：価格戦略カード
  Widget _buildPriceStrategyCard(Map<String, dynamic> r) {
    final price = r['price_strategy'] as Map? ?? {};
    if (price.isEmpty) return const SizedBox();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoHeader('💹 価格戦略', '価格戦略について', _getInfoText('price_strategy')),
            const SizedBox(height: 10),
            _priceRow(
              'エントリー',
              price['entry']?['value']?.toString() ?? '-',
              Colors.blue,
              price['entry']?['reason'] ?? '',
            ),
            const Divider(height: 16),
            _priceRow(
              '損切り',
              '¥${price['stop_loss']?['value'] ?? '-'}',
              Colors.red,
              price['stop_loss']?['reason'] ?? '',
            ),
            const Divider(height: 16),
            _priceRow(
              '利確',
              '¥${price['take_profit']?['value'] ?? '-'}',
              Colors.green,
              price['take_profit']?['reason'] ?? '',
            ),
          ],
        ),
      ),
    );
  }

  // 中期：価格見通し＋トレンド強度カード
  Widget _buildMidTermCards(Map<String, dynamic> r) {
    final trend = r['trend_analysis'] as Map? ?? {};
    final outlook = r['price_outlook'] as Map? ?? {};
    return Column(
      children: [
        if (trend.isNotEmpty)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoHeader(
                    '📊 トレンド強度',
                    'トレンド強度について',
                    _getInfoText('trend_strength'),
                  ),
                  const SizedBox(height: 8),
                  _macroRow('強度', trend['strength']),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (outlook.isNotEmpty)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoHeader(
                    '💹 価格見通し（1〜3ヶ月）',
                    '価格見通しについて',
                    _getInfoText('price_outlook_mid'),
                  ),
                  const SizedBox(height: 8),
                  _macroRow('想定値幅', outlook['range']),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        _buildFundaCard(r),
      ],
    );
  }

  // 長期：ファンダ分析＋バリュエーション
  Widget _buildLongTermCards(Map<String, dynamic> r) {
    final funda = r['fundamental_analysis'] as Map? ?? {};
    final val = r['valuation_analysis'] as Map? ?? {};
    final ltRisk = r['long_term_risk'] as Map? ?? {};
    final outlook = r['price_outlook'] as Map? ?? {};
    return Column(
      children: [
        if (funda.isNotEmpty)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoHeader(
                    '📈 ファンダメンタル分析',
                    'ファンダメンタル分析について',
                    _getInfoText('funda_long'),
                  ),
                  const SizedBox(height: 10),
                  _macroRow('成長性', funda['growth']),
                  const Divider(height: 12),
                  _macroRow('収益性', funda['profitability']),
                  const Divider(height: 12),
                  _macroRow('効率性', funda['efficiency']),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (val.isNotEmpty)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoHeader(
                    '💰 バリュエーション',
                    'バリュエーションについて',
                    _getInfoText('valuation_long'),
                  ),
                  const SizedBox(height: 8),
                  _macroRow('評価水準', val['level']),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (ltRisk.isNotEmpty)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚠️ 長期リスク',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  _macroRow('リスク水準', ltRisk),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (outlook.isNotEmpty)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoHeader(
                    '🎯 長期価格トレンド',
                    '長期価格トレンドについて',
                    _getInfoText('price_trend_long'),
                  ),
                  const SizedBox(height: 8),
                  _macroRow('方向性', outlook['target_trend']),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // 中期：ファンダカード
  Widget _buildFundaCard(Map<String, dynamic> r) {
    final funda = r['fundamental_analysis'] as Map? ?? {};
    if (funda.isEmpty) return const SizedBox();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoHeader(
              '📈 ファンダメンタル',
              'ファンダメンタル分析について',
              _getInfoText('funda_mid'),
            ),
            const SizedBox(height: 10),
            _macroRow('成長性', funda['growth']),
            if (funda['valuation'] != null) ...[
              const Divider(height: 12),
              _macroRow('バリュエーション', funda['valuation']),
            ],
          ],
        ),
      ),
    );
  }

  // リスク・好材料カード（全期間共通）
  Widget _buildRiskOpportunityCards(Map<String, dynamic> r) {
    return Column(
      // ← Rowを Columnに変更
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoHeader(
                  '⚠️ リスク要因',
                  'リスク要因・好材料について',
                  _getInfoText('risk_factors'),
                ),
                const SizedBox(height: 8),
                ...(r['negative_points'] as List? ??
                        r['risk_factors'] as List? ??
                        [])
                    .map(
                      (rf) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '・',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                            Expanded(
                              child: Text(
                                rf.toString(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                ),
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
        const SizedBox(height: 8), // ← 追加
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoHeader(
                  '✨ 好材料',
                  'リスク要因・好材料について',
                  _getInfoText('risk_factors'),
                ),
                const SizedBox(height: 8),
                ...(r['positive_points'] as List? ??
                        r['opportunity_factors'] as List? ??
                        [])
                    .map(
                      (of) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '・',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                of.toString(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                ),
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
      ],
    );
  }

  // マクロ分析カード（全期間共通）
  Widget _buildMacroCard(Map<String, dynamic> r) {
    final macro = r['macro_analysis'] as Map? ?? {};
    if (macro.isEmpty) return const SizedBox();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoHeader('🌍 マクロ分析', 'マクロ分析について', _getInfoText('macro')),
            const SizedBox(height: 10),
            _macroRow('リスクモード', macro['risk_mode']),
            const Divider(height: 12),
            _macroRow('ドル円影響', macro['usd_jpy_impact']),
            const Divider(height: 12),
            _macroRow('金利影響', macro['interest_rate_impact']),
          ],
        ),
      ),
    );
  }

  Widget _technicalCard({
    required String title,
    required String subtitle,
    required String label,
    required Color color,
    required String reason,
    required String infoTitle,
    required String infoContent,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // タイトル行
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showInfoSheet(infoTitle, infoContent),
                  child: _infoIcon(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
            const SizedBox(height: 8),
            // 判定バッジ
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.4)),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 理由
            Text(
              reason,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fundaCard({
    required String label,
    required String value,
    required String infoTitle,
    required String infoContent,
    _JudgeResult? judge,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showInfoSheet(infoTitle, infoContent),
                  child: _infoIcon(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (judge != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: judge.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: judge.color.withOpacity(0.4)),
                    ),
                    child: Text(
                      judge.label,
                      style: TextStyle(
                        color: judge.color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (judge != null && judge.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                judge.reason,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // MACDチャート
  Widget _buildMacdChart(List<Map<String, dynamic>> candles) {
    if (candles.isEmpty) return const Text("データなし");
    final data = candles.length > 60
        ? candles.sublist(candles.length - 60)
        : candles;

    final macdSpots = data
        .asMap()
        .entries
        .where((e) => e.value['macd'] != null)
        .map(
          (e) => FlSpot(e.key.toDouble(), (e.value['macd'] as num).toDouble()),
        )
        .toList();

    if (macdSpots.isEmpty) return const Text("MACDデータなし");

    final labelIndices = <int>{0, data.length ~/ 2, data.length - 1};

    return SizedBox(
      height: 120,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (value) => FlLine(
              color: value == 0 ? Colors.red : Colors.grey.withOpacity(0.3),
              strokeWidth: value == 0 ? 1.5 : 0.5,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (!labelIndices.contains(i) || i >= data.length)
                    return const SizedBox();
                  return Text(
                    _dateLabel(data[i]['date']),
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
              ),
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
              spots: macdSpots,
              color: Colors.purple,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.purple.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoHeader(String title, String infoTitle, String infoContent) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => _showInfoSheet(infoTitle, infoContent),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.info_outline, size: 12, color: Colors.blue),
          ),
        ),
      ],
    );
  }

  void _showInfoSheet(String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ハンドル
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // タイトル
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              // コンテンツ
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Text(
                    content,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      height: 1.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPromptSheet(Map<String, dynamic> result) {
    final prompt = result['_prompt'] as String? ?? 'プロンプト未取得';
    final tech = result['_tech_data'] as Map? ?? {};
    final fund = result['_fund_data'] as Map? ?? {};
    final macro = result['_macro_data'] as Map? ?? {};
    final breadth = result['_breadth_data'] as Map? ?? {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => DefaultTabController(
          length: 2,
          child: Column(
            children: [
              // ハンドル
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.code, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      'AIに渡したデータ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: '📊 データ一覧'),
                  Tab(text: '📝 プロンプト全文'),
                ],
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.blue,
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    // タブ①：データ一覧
                    SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _dataSection('📈 テクニカル', tech),
                          const SizedBox(height: 12),
                          _dataSection('💰 ファンダメンタル', fund),
                          const SizedBox(height: 12),
                          _dataSection('🌍 マクロ', macro),
                          const SizedBox(height: 12),
                          _dataSection('📊 市場内部', breadth),
                        ],
                      ),
                    ),
                    // タブ②：プロンプト全文
                    SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: SelectableText(
                              prompt,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black87,
                                height: 1.6,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dataSection(String title, Map data) {
    // キー名の日本語変換マップ
    final keyLabels = {
      // テクニカル
      'price': '現在株価',
      'ma5': '移動平均 MA5',
      'ma25': '移動平均 MA25',
      'ma75': '移動平均 MA75',
      'rsi': 'RSI（14日）',
      'macd': 'MACD',
      'macd_signal': 'MACDシグナル',
      'macd_hist': 'MACDヒストグラム',
      'bb_upper': 'ボリンジャー上限',
      'bb_mid': 'ボリンジャー中央',
      'bb_lower': 'ボリンジャー下限',
      'atr': 'ATR（14日）',
      'volume_ratio': '出来高比（20日平均比）',
      'obv': 'OBV',
      'stoch_k': 'ストキャスティクス %K',
      'adx': 'ADX（トレンド強度）',
      'week52_high': '52週高値',
      'week52_low': '52週安値',
      'range_position': '52週レンジ位置 %',
      'momentum_1m': 'モメンタム（1ヶ月）',
      'momentum_3m': 'モメンタム（3ヶ月）',
      'momentum_6m': 'モメンタム（6ヶ月）',
      // ファンダメンタル
      'per': 'PER（株価収益率）',
      'pbr': 'PBR（株価純資産倍率）',
      'roe': 'ROE（自己資本利益率）',
      'roa': 'ROA（総資産利益率）',
      'revenue_growth': '売上成長率',
      'eps_growth': 'EPS成長率',
      'operating_margin': '営業利益率',
      'debt_ratio': '負債比率（D/Eレシオ）',
      'equity_ratio': '株主資本（BPS）',
      'dividend_yield': '配当利回り',
      'fcf': 'フリーキャッシュフロー',
      'target_price': 'アナリスト目標株価',
      'analyst_rating': 'アナリスト評価',
      // マクロ
      'vix': 'VIX（恐怖指数）',
      'us10y': '米10年債利回り',
      'us2y': '米2年債利回り',
      'usd_jpy': 'ドル円',
      'dxy': 'ドル指数（DXY）',
      'oil_price': '原油（WTI）',
      'gold_price': '金（Gold）',
      'nikkei_trend': '日経平均トレンド',
      'sp500_trend': 'S&P500トレンド',
      'yield_spread': '金利差（10年−2年）',
      'margin_ratio': '信用倍率',
      'short_ratio': '空売り比率',
      // 騰落レシオ
      'advancers': '上昇銘柄数',
      'decliners': '下落銘柄数',
      'advance_decline_ratio': '騰落レシオ',
      'cache_key': 'キャッシュキー',
    };

    if (data.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'データなし',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: data.entries
                .where((e) => !e.key.startsWith('_') && e.key != 'cache_key')
                .map((e) {
                  final val = e.value;
                  final label = keyLabels[e.key] ?? e.key;
                  final isNull = val == null;
                  final dispVal = isNull ? '❌ 未取得' : '✅ $val';
                  final color = isNull
                      ? Colors.red.shade400
                      : Colors.green.shade700;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 165,
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            dispVal,
                            style: TextStyle(
                              fontSize: 11,
                              color: color,
                              fontWeight: isNull
                                  ? FontWeight.normal
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                })
                .toList(),
          ),
        ),
      ],
    );
  }

  String _getInfoText(String key) {
    final texts = {
      'verdict':
          '''【何を表しているか】
  AIが全データを総合的に分析した結果、今後${_selectedPeriod == '短期'
              ? '1〜2週間'
              : _selectedPeriod == '中期'
              ? '1〜3ヶ月'
              : '6ヶ月以上'}で株価が「上昇・様子見・下落」のどちらに動きやすいかを判定したものです。

  【判定の根拠】
  テクニカル指標（RSI・MACD・ボリンジャーバンド・移動平均）、ファンダメンタル指標（PER・PBR・ROE）、マクロ環境（VIX・ドル円・米金利・原油・金）、最近のニュースを総合的に評価しています。

  【注意点】
  AIの判定は参考情報です。過去のデータに基づく統計的な傾向であり、将来の株価を保証するものではありません。予期せぬニュースや市場変動により、判定と逆方向に動く可能性があります。投資判断は必ずご自身の責任で行ってください。''',

      'probability': '''【何を表しているか】
  上昇・様子見・下落それぞれのシナリオが実現する確率をAIが推計したものです。3つの確率の合計は必ず100%になります。

  【分析に使用している指標】
  ■ テクニカル指標（重み：高）
  ・RSI：30以下→売られすぎ（上昇↑）、70以上→買われすぎ（下落↑）
  ・MACD：プラス圏→買いシグナル、マイナス圏→売りシグナル
  ・ボリンジャーバンド：下限タッチ→反発の可能性、上限タッチ→過熱注意
  ・移動平均：MA5＞MA25→上昇トレンド、MA5＜MA25→下降トレンド

  ■ マクロ環境（重み：中）
  ・VIX（恐怖指数）・ドル円・米10年債・原油・金・S&P500

  ■ ファンダメンタル（重み：中）
  ・PER・PBR・ROE・売上成長率

  【取得できていないデータ】
  現在、信用買い残・空売り比率・騰落レシオは取得できていないため、需給面の分析が不完全です。これらが確率の不確実性の主な要因となっています。''',

      'price_strategy': '''【エントリー価格帯】
  どの価格で買い始めるのが適切かの目安です。
  ・サポートライン（過去に反発した水準）
  ・移動平均線（MA5・MA25）
  ・ボリンジャーバンド下限
  などを組み合わせて算出しています。

  【損切りライン（ストップロス）】
  ここまで下がったら損失を確定して撤退する価格です。
  「予想が外れた」と判断する技術的な節目（サポート割れなど）を基準にしています。

  【利確価格（テイクプロフィット）】
  ここで利益を確定する目標価格です。
  レジスタンスライン（上値の壁）や目標値幅を基準にしています。

  【リスクリワード比の目安】
  （利確 − エントリー）÷（エントリー − 損切り）
  一般的に2.0以上が推奨されます（1の損失リスクに対して2以上の利益期待）。

  【重要な注意】
  これはAIによる参考値です。実際の取引では自分のリスク許容度に合わせて調整してください。スリッページや板の薄さにより、想定価格で約定できない場合があります。''',

      'macro': '''【データソース（全てYahoo Finance経由・約15〜20分遅延）】
  ・VIX：S&P500オプション価格から計算される市場の不安度（^VIX）
  ・米10年債利回り：米国長期金利の基準（^TNX）
  ・ドル円：USD/JPY為替レート（USDJPY=X）
  ・原油（WTI）：世界の原油価格の基準（CL=F）
  ・金：安全資産の代表格（GC=F）
  ・日経平均・S&P500：直近5日間の騰落からトレンドを判定

  【各指標の解釈】
  ■ リスクモード
  ・リスクオン（VIX低・株高）：投資家が積極的にリスク資産を購入
  ・リスクオフ（VIX高・株安）：投資家が安全資産に逃げる環境

  ■ ドル円の影響
  ・円安：輸出企業（自動車・電機・精密機器）にプラス
  ・円高：輸入企業・内需企業にプラス

  ■ 金利の影響
  ・金利上昇：PERの高い成長株にネガティブ（割引率上昇）
  ・金利低下：株式全般にプラス（資金が株式市場に流入しやすい）''',

      'risk_factors': '''【リスク要因とは】
  株価下落の可能性がある要因をAIが分析したものです。
  以下の観点から導出しています：
  ・テクニカル：RSI高（買われすぎ）、高値圏、デッドクロス
  ・マクロ：VIX上昇、円高、金利上昇
  ・ファンダ：高PER（割高）、高負債、減収
  ・イベント：決算・SQ・FOMC前の不透明感

  【好材料とは】
  株価上昇を後押しする要因をAIが分析したものです：
  ・テクニカル：RSI低（売られすぎ）、ゴールデンクロス、安値圏
  ・マクロ：リスクオン環境、円安、金利低下
  ・ファンダ：低PER（割安）、高ROE、増収増益
  ・ポジティブなニュース

  【AIの分析方法】
  ニュースはタイトルと要約文からセンチメントを分析しています。記事の詳細まで読んでいるわけではないため、誤認識が生じる場合があります。重要な投資判断の前には実際のニュースをご確認ください。''',

      'confidence': '''【信頼度の定義】
  分析結果がどれだけ信頼できるかを3段階で示します。

  ■ 高（High）
  複数のテクニカル指標が同じ方向を示し、マクロ環境も一致している状態。
  データの欠損が少なく、シグナルが明確な場合に判定されます。

  ■ 中（Medium）
  一部の指標が反対方向を示している、またはデータに欠損がある状態。

  ■ 低（Low）
  指標が相反するシグナルを示している、または重要なデータが不足している状態。

  【現在取得できていないデータ（信頼度に影響）】
  ・信用買い残・信用売り残・信用倍率（J-Quants有料プランが必要）
  ・空売り比率（東証の別APIが必要）
  ・騰落レシオ（計算実装が必要）
  ・MACD シグナルライン
  ・出来高比率

  これらが揃うとより精度の高い分析が可能になります。

  【重要な注意】
  信頼度が「高」であっても分析が外れることは十分あります。これはあくまで参考情報です。市場は予測不可能であり、突発的なニュースや経済指標の発表で短時間で状況が変わることがあります。''',

      'trend_strength': '''【トレンド強度とは】
中期（1〜3ヶ月）における価格トレンドの勢いを「強い・弱い・中立」で評価したものです。

【判定基準】
■ 強い（Strong）
・MA25と比較して株価が明確に上または下に乖離している
・価格の方向性が一貫して継続している
・出来高が増加トレンドに伴っている

■ 弱い（Weak）
・MA25付近で推移し方向感がない
・上昇と下落を繰り返している
・出来高が減少している

■ 中立（Neutral）
・どちらとも言えない状態

【データソース】
・現在株価とMA25の比較
・直近の価格推移パターン
（注：MA75や出来高トレンドは現在未取得のため、MA25のみで判定しています）''',

      'price_outlook_mid': '''【価格見通し（1〜3ヶ月）とは】
中期の想定される株価の値幅（レンジ）をAIが推計したものです。

【算出方法】
・現在株価を基準に、上昇シナリオ・下落シナリオそれぞれの価格水準を推計
・ボラティリティ（過去の値動きの大きさ）を考慮
・サポートライン（下値支持）とレジスタンスライン（上値抵抗）を参考に算出

【注意点】
・あくまでAIによる参考値であり、実際の株価を保証するものではありません
・決算発表・重大ニュースなどのイベントにより大きく外れる可能性があります
・値幅が広いほど不確実性が高いことを意味します''',

      'funda_mid': '''【ファンダメンタル分析（中期）とは】
企業の財務・業績データから、中期（1〜3ヶ月）の株価に影響する要素を評価したものです。

■ 成長性（Growth）
売上成長率・ROEから企業の成長力を評価しています。
・高（High）：売上成長率10%以上、ROE15%以上
・中（Medium）：安定的な成長を維持
・低（Low）：減収または成長鈍化

■ バリュエーション（Valuation）
PER・PBRから株価の割安・割高を評価しています。
・割安（Undervalued）：PER15倍以下、PBR1倍以下
・適正（Fair）：業界平均水準
・割高（Overvalued）：PER30倍以上、PBR5倍以上

【データソース】
yfinance経由で取得（約15〜20分遅延）''',

      'funda_long': '''【ファンダメンタル分析（長期）とは】
長期投資において最も重要な企業の本質的な価値を3つの観点から評価したものです。

■ 成長性（Growth）
企業が中長期的に売上・利益を増やしていける力を評価します。
・高（High）：売上成長率10%以上で継続的な成長が期待できる
・中（Medium）：安定成長で大きな変動なし
・低（Low）：成長鈍化または減収傾向

■ 収益性（Profitability）
どれだけ効率よく利益を生み出しているかを評価します。
主にROE（自己資本利益率）で判断しています。
・高（High）：ROE15%以上（優良企業の基準）
・中（Medium）：ROE8〜15%
・低（Low）：ROE8%未満

■ 効率性（Efficiency）
資本・資産をどれだけ有効に活用しているかを評価します。
ROEを主な指標として使用しています。
（注：ROAや営業利益率は現在取得できていないため、ROEで代替しています）

【データソース】yfinance経由（約15〜20分遅延）''',

      'valuation_long': '''【バリュエーション（長期）とは】
株価が企業の本質的な価値に対して割安か割高かを評価したものです。長期投資において最も重要な判断基準の一つです。

■ 割安（Undervalued）
PER10倍以下またはPBR1倍以下の水準。
理論上は企業価値より安い価格で購入できている状態。
ただし「なぜ安いのか」の理由確認が重要です。

■ 適正（Fair）
業界平均的なPER・PBR水準。
現在の業績・成長性に対して妥当な価格と判断されます。

■ 割高（Overvalued）
PER30倍以上またはPBR5倍以上の水準。
将来の高い成長が既に株価に織り込まれている状態。
成長が鈍化すると株価調整リスクがあります。

【使用指標】
・PER（株価収益率）：株価 ÷ 1株あたり利益
・PBR（株価純資産倍率）：株価 ÷ 1株あたり純資産

【データソース】yfinance経由（約15〜20分遅延）''',

      'long_term_risk': '''【長期リスクとは】
6ヶ月〜数年の長期保有において株価下落・損失につながりうるリスクの総合水準を評価したものです。

■ 高（High）
以下のような重大なリスク要因が存在する場合：
・高PER・高PBRによる割高感（成長鈍化時の調整リスク）
・高負債比率（金利上昇時のコスト増加）
・売上減収・利益減少トレンド
・マクロ環境の悪化（金利上昇・円高・景気後退懸念）

■ 中（Medium）
・一部リスク要因はあるが致命的ではない状態
・業績は安定しているが成長性に疑問符

■ 低（Low）
・財務健全・割安水準・成長継続中の良好な状態
・マクロ環境も追い風

【注意点】
長期リスクが「低」でも、予期せぬ事業環境の変化・競合台頭・経営陣の変化などで状況が変わる可能性があります。定期的な見直しを推奨します。''',

      'price_trend_long': '''【長期価格トレンドとは】
6ヶ月〜数年の長期的な株価の方向性をAIが判断したものです。

■ 上昇トレンド（Uptrend）
企業の成長性・収益性・バリュエーションから長期的な株価上昇が期待できると判断。
配当の増加・自社株買いなどの株主還元も考慮。

■ 横ばい（Sideways）
成長は安定しているが大きな上昇・下落要因がなく、一定の範囲内での推移が予想される状態。

■ 下降トレンド（Downtrend）
業績悪化・割高感・マクロ逆風などにより、長期的な株価下落リスクが高いと判断。

【判断に使用している要素】
・企業の成長性（売上成長率・ROE）
・バリュエーション（PER・PBR）
・マクロ環境（金利・為替・景気）
・最近のニュース・決算動向

【重要な注意】
長期予測は不確実性が非常に高いです。数年単位の予測はAIでも困難であり、あくまで現時点のデータに基づく参考情報です。長期投資においては定期的な見直しが不可欠です。''',
    };
    return texts[key] ?? '';
  }
}

// 判定結果クラス
class _JudgeResult {
  final String label;
  final Color color;
  final String reason;
  const _JudgeResult(this.label, this.color, this.reason);
}

_JudgeResult? _perJudge(dynamic per) {
  if (per == null) return null;
  final v = (per as num).toDouble();
  if (v <= 0)
    return _JudgeResult(
      '計算不可',
      Colors.grey,
      'PERがマイナスまたはゼロです。赤字企業の場合、PERは計算できません。',
    );
  if (v <= 10)
    return _JudgeResult(
      '割安',
      Colors.red,
      'PER${v.toStringAsFixed(1)}倍は割安水準です。利益に対して株価が低い状態ですが、業績悪化の懸念がないか確認が必要です。',
    );
  if (v <= 15)
    return _JudgeResult(
      'やや割安',
      Colors.orange,
      'PER${v.toStringAsFixed(1)}倍はやや割安な水準です。日本株の平均PERは15倍前後であり、平均より低い水準です。',
    );
  if (v <= 25)
    return _JudgeResult(
      '適正水準',
      Colors.grey,
      'PER${v.toStringAsFixed(1)}倍は適正な水準です。市場平均的な評価が付いています。',
    );
  if (v <= 30)
    return _JudgeResult(
      'やや割高',
      Colors.teal,
      'PER${v.toStringAsFixed(1)}倍はやや割高な水準です。高い成長期待が株価に織り込まれています。',
    );
  return _JudgeResult(
    '割高',
    Colors.green,
    'PER${v.toStringAsFixed(1)}倍は割高な水準です。将来の高い成長が期待されていますが、成長が鈍化すると株価調整リスクがあります。',
  );
}

_JudgeResult? _pbrJudge(dynamic pbr) {
  if (pbr == null) return null;
  final v = (pbr as num).toDouble();
  if (v <= 1.0)
    return _JudgeResult(
      '解散価値以下・割安',
      Colors.red,
      'PBR${v.toStringAsFixed(1)}倍は解散価値以下の割安水準です。理論上、企業を清算すると株価以上の資産が戻ってきます。東証が改善を要請している水準です。',
    );
  if (v <= 1.5)
    return _JudgeResult(
      'やや割安',
      Colors.orange,
      'PBR${v.toStringAsFixed(1)}倍はやや割安な水準です。純資産より少し高い程度の評価が付いています。',
    );
  if (v <= 5.0)
    return _JudgeResult(
      '適正水準',
      Colors.grey,
      'PBR${v.toStringAsFixed(1)}倍は適正な水準です。',
    );
  return _JudgeResult(
    '割高',
    Colors.green,
    'PBR${v.toStringAsFixed(1)}倍は割高な水準です。ブランド価値・成長期待などの無形資産が高く評価されています。',
  );
}

_JudgeResult? _roeJudge(dynamic roe) {
  if (roe == null) return null;
  final v = (roe as num).toDouble() * 100;
  if (v >= 15)
    return _JudgeResult(
      '優良・高ROE',
      Colors.red,
      'ROE${v.toStringAsFixed(1)}%は外国人投資家が好む15%以上の優良水準です。株主資本を効率よく利益に変えている優良企業と評価されます。',
    );
  if (v >= 8)
    return _JudgeResult(
      '標準的',
      Colors.grey,
      'ROE${v.toStringAsFixed(1)}%は標準的な水準です。',
    );
  if (v >= 5)
    return _JudgeResult(
      'やや低い',
      Colors.orange,
      'ROE${v.toStringAsFixed(1)}%はやや低い水準です。資本効率の改善が期待されます。',
    );
  if (v >= 0)
    return _JudgeResult(
      '低ROE・注意',
      Colors.green,
      'ROE${v.toStringAsFixed(1)}%は低い水準です。自己資本を十分に活用できていない可能性があります。',
    );
  return _JudgeResult('赤字', Colors.green, 'ROEがマイナスです。当期純損失が発生しています。');
}

_JudgeResult? _roaJudge(dynamic roa) {
  if (roa == null) return null;
  final v = (roa as num).toDouble() * 100;
  if (v >= 10)
    return _JudgeResult(
      '非常に優秀',
      Colors.red,
      'ROA${v.toStringAsFixed(1)}%は非常に優秀な水準です。全資産を高効率で利益に変えています。',
    );
  if (v >= 5)
    return _JudgeResult(
      '優良',
      Colors.orange,
      'ROA${v.toStringAsFixed(1)}%は優良な水準です。',
    );
  if (v >= 3)
    return _JudgeResult(
      '標準的',
      Colors.grey,
      'ROA${v.toStringAsFixed(1)}%は標準的な水準です。',
    );
  return _JudgeResult(
    '低ROA・注意',
    Colors.green,
    'ROA${v.toStringAsFixed(1)}%は低い水準です。資産効率の改善が期待されます。',
  );
}

_JudgeResult? _dividendJudge(dynamic div) {
  if (div == null) return null;
  final v = (div as num).toDouble() * 100;
  if (v >= 3.0)
    return _JudgeResult(
      '高配当',
      Colors.red,
      '配当利回り${v.toStringAsFixed(2)}%は高配当水準です。インカム投資の観点から魅力的ですが、減配リスクがないか業績も確認しましょう。',
    );
  if (v >= 1.5)
    return _JudgeResult(
      '配当あり',
      Colors.orange,
      '配当利回り${v.toStringAsFixed(2)}%は標準的な水準です。',
    );
  if (v > 0)
    return _JudgeResult(
      '低配当',
      Colors.grey,
      '配当利回り${v.toStringAsFixed(2)}%は低い水準です。成長投資に資本を集中している企業の可能性があります。',
    );
  return _JudgeResult(
    '無配当',
    Colors.grey,
    '現在配当を出していません。成長投資優先か、業績上の理由が考えられます。',
  );
}

_JudgeResult? _revGrowthJudge(dynamic rev) {
  if (rev == null) return null;
  final v = (rev as num).toDouble() * 100;
  if (v >= 10)
    return _JudgeResult(
      '高成長',
      Colors.red,
      '売上成長率${v.toStringAsFixed(1)}%は高成長水準です。事業が順調に拡大しています。',
    );
  if (v >= 5)
    return _JudgeResult(
      '良好な成長',
      Colors.orange,
      '売上成長率${v.toStringAsFixed(1)}%は良好な成長水準です。',
    );
  if (v >= 0)
    return _JudgeResult(
      '微増・安定',
      Colors.grey,
      '売上成長率${v.toStringAsFixed(1)}%です。安定していますが成長は緩やかです。',
    );
  return _JudgeResult(
    '減収・注意',
    Colors.green,
    '売上成長率${v.toStringAsFixed(1)}%と減収です。業績悪化の可能性があります。',
  );
}

_JudgeResult? _debtJudge(dynamic debt) {
  if (debt == null) return null;
  final v = (debt as num).toDouble();
  if (v <= 50)
    return _JudgeResult(
      '低負債・安全',
      Colors.red,
      'D/Eレシオ${v.toStringAsFixed(0)}%は低負債で財務安全性が高い水準です。',
    );
  if (v <= 150)
    return _JudgeResult(
      '標準的',
      Colors.grey,
      'D/Eレシオ${v.toStringAsFixed(0)}%は標準的な水準です。',
    );
  return _JudgeResult(
    '高負債・注意',
    Colors.green,
    'D/Eレシオ${v.toStringAsFixed(0)}%は高負債な水準です。金利上昇・業績悪化時のリスクが高まります。',
  );
}
