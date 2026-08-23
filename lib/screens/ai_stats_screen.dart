// ============================================================
// AiStatsScreen
// AI予測がどれくらい当たっているかを表示する画面。
//
// なぜこの画面が必要か：
//   プロンプトを改良しても、的中率を測っていなければ
//   良くなったのか悪くなったのか分からない。
//   ここが精度改善の出発点になる。
//
// 表示する内容：
// ・全体の的中率（判定済みの件数ベース）
// ・期間別（短期/中期/長期）・判定別・確信度別の的中率
// ・プロンプトのバージョン別の的中率（改良の効果を見る）
// ・キャリブレーション（「上昇70%」と言った時に本当に7割上がったか）
// ・直近の予測履歴（当たり/外れ付き）
//
// 判定の基準：
//   予測時の株価から ±3% を超えて動いたら「上昇」「下落」、
//   それ以内なら「様子見」として答え合わせする。
// ============================================================

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/stock_service.dart';

class AiStatsScreen extends StatefulWidget {
  const AiStatsScreen({super.key});

  @override
  State<AiStatsScreen> createState() => _AiStatsScreenState();
}

class _AiStatsScreenState extends State<AiStatsScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final userId = await AuthService.getUserId() ?? '';
      // 成績APIは呼ばれたタイミングで答え合わせも行うため、先に完了を待つ
      final stats = await StockService.getAccuracyStats(userId: userId);
      final history = await StockService.getPredictionHistory(limit: 30);
      if (!mounted) return;
      setState(() {
        if (stats['error'] != null) {
          _error = stats['error'].toString();
        } else {
          _stats = stats;
          _history = history;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI予測の成績'),
        actions: [
          IconButton(
            tooltip: '再判定して更新',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    '期限が来た予測を答え合わせ中...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            )
          : _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'エラー: $_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final s = _stats ?? {};
    final evaluated = (s['evaluated'] as num?)?.toInt() ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeadline(s),
        const SizedBox(height: 12),

        // 判定がまだ0件のときは、これから何が起きるかを説明する
        if (evaluated == 0) _buildEmptyGuide(s) else ...[
          _buildBreakdown('期間別', s['by_period']),
          _buildBreakdown('判定別', s['by_verdict'], labelMap: _verdictLabels),
          _buildBreakdown('確信度別', s['by_confidence']),
          _buildBreakdown('プロンプト別', s['by_prompt_version']),
          _buildCalibration(s['calibration']),
        ],

        const SizedBox(height: 8),
        _buildUsage(s),
        const SizedBox(height: 16),
        _buildHistory(),
      ],
    );
  }

  // ============================================================
  // 全体の的中率
  // ============================================================

  Widget _buildHeadline(Map<String, dynamic> s) {
    final accuracy = (s['accuracy'] as num?)?.toDouble();
    final evaluated = (s['evaluated'] as num?)?.toInt() ?? 0;
    final pending = (s['pending'] as num?)?.toInt() ?? 0;
    final threshold = (s['threshold_pct'] as num?)?.toDouble() ?? 3.0;

    // 3択なのでランダムなら33%。そこを超えているかで色を変える
    final color = accuracy == null
        ? Colors.grey
        : accuracy >= 55
        ? Colors.green
        : accuracy >= 34
        ? Colors.orange
        : Colors.red;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              '全体の的中率',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              accuracy == null ? '—' : '${accuracy.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '判定済み $evaluated件 / 判定待ち $pending件',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '予測時の株価から±${threshold.toStringAsFixed(0)}%を超えて動いたら「上昇」「下落」、'
                    'それ以内なら「様子見」として判定しています。\n'
                    '3択なので、当てずっぽうだと約33%になります。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// まだ1件も判定できていないときの案内
  Widget _buildEmptyGuide(Map<String, dynamic> s) {
    final pending = (s['pending'] as num?)?.toInt() ?? 0;
    final next = s['next_evaluate_at']?.toString();

    return Card(
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.hourglass_empty, size: 18, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'まだ判定できる予測がありません',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              pending == 0
                  ? 'AI分析を実行すると、その予測がここに記録されます。\n'
                        '分析期間が過ぎたら自動で答え合わせされ、的中率が出ます。'
                  : '$pending件の予測を記録済みです。\n'
                        '分析期間が過ぎると答え合わせされます。'
                        '${next != null ? '\n最初の判定予定日：$next' : ''}',
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 内訳
  // ============================================================

  static const _verdictLabels = {
    'up': '上昇と予測',
    'sideways': '様子見と予測',
    'down': '下落と予測',
  };

  Widget _buildBreakdown(
    String title,
    dynamic data, {
    Map<String, String>? labelMap,
  }) {
    if (data is! Map || data.isEmpty) return const SizedBox.shrink();

    // 件数が多い順に並べる
    final entries = data.entries.toList()
      ..sort((a, b) {
        final at = ((a.value as Map)['total'] as num?)?.toInt() ?? 0;
        final bt = ((b.value as Map)['total'] as num?)?.toInt() ?? 0;
        return bt.compareTo(at);
      });

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 10),
            ...entries.map((e) {
              final v = e.value as Map;
              final total = (v['total'] as num?)?.toInt() ?? 0;
              final acc = (v['accuracy'] as num?)?.toDouble();
              final label = labelMap?[e.key] ?? e.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (acc ?? 0) / 100,
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            (acc ?? 0) >= 55 ? Colors.green : Colors.blue,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 74,
                      child: Text(
                        acc == null
                            ? '— ($total件)'
                            : '${acc.toStringAsFixed(0)}% ($total件)',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // キャリブレーション
  // ============================================================

  /// 「上昇◯%」と言った予測が、実際にどれくらい上昇したかの対応表
  ///
  /// 的中率よりこちらの方が実用的な指標になる。
  /// 「上昇70%」と言った時に本当に7割上がるなら、外れても判断材料として使える。
  Widget _buildCalibration(dynamic data) {
    if (data is! List || data.isEmpty) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '確率の正直さ（キャリブレーション）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'AIが「上昇◯%」と言った時に、実際にどれくらい上昇したか。'
              '2つの数字が近いほど、確率が信頼できます。',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            ...data.map((row) {
              final m = row as Map;
              final said = (m['said_avg'] as num?)?.toDouble() ?? 0;
              final actual = (m['actual_pct'] as num?)?.toDouble() ?? 0;
              final count = (m['count'] as num?)?.toInt() ?? 0;
              final gap = (said - actual).abs();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        '${m['range']}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'AI ${said.toStringAsFixed(0)}%  →  実際 ${actual.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: gap <= 10
                              ? FontWeight.normal
                              : FontWeight.bold,
                          color: gap <= 10 ? Colors.black87 : Colors.deepOrange,
                        ),
                      ),
                    ),
                    Text(
                      '$count件',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // トークン使用量
  // ============================================================

  Widget _buildUsage(Map<String, dynamic> s) {
    final usage = s['tokens'];
    if (usage is! Map) return const SizedBox.shrink();
    final input = (usage['prompt'] as num?)?.toInt() ?? 0;
    final output = (usage['completion'] as num?)?.toInt() ?? 0;
    if (input == 0 && output == 0) return const SizedBox.shrink();

    final total = (s['total'] as num?)?.toInt() ?? 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '累計トークン使用量',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              '入力 ${_comma(input)} / 出力 ${_comma(output)}',
              style: const TextStyle(fontSize: 12),
            ),
            if (total > 0) ...[
              const SizedBox(height: 4),
              Text(
                '1回あたり平均：入力 ${_comma(input ~/ total)} / 出力 ${_comma(output ~/ total)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _comma(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  // ============================================================
  // 履歴
  // ============================================================

  Widget _buildHistory() {
    if (_history.isEmpty) return const SizedBox.shrink();

    const verdictLabel = {'up': '上昇', 'sideways': '様子見', 'down': '下落'};
    const verdictColor = {
      'up': Colors.red,
      'sideways': Colors.grey,
      'down': Colors.green,
    };

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '直近の予測',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            ..._history.map((p) {
              final done = p['status'] == 'evaluated';
              final correct = p['is_correct'] == true;
              final predicted = p['verdict']?.toString() ?? '';
              final actual = p['actual_verdict']?.toString() ?? '';
              final changePct = (p['actual_change_pct'] as num?)?.toDouble();
              final predictedAt =
                  p['predicted_at']?.toString().split('T').first ?? '';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    // 当たり/外れ/判定待ち
                    Icon(
                      !done
                          ? Icons.schedule
                          : correct
                          ? Icons.check_circle
                          : Icons.cancel,
                      size: 18,
                      color: !done
                          ? Colors.grey
                          : correct
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p['name'] ?? p['code']}（${p['period'] ?? ''}）',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            done
                                ? '予測: ${verdictLabel[predicted] ?? predicted}'
                                      ' → 実際: ${verdictLabel[actual] ?? actual}'
                                      '（${changePct?.toStringAsFixed(1) ?? '—'}%）'
                                : '予測: ${verdictLabel[predicted] ?? predicted}'
                                      ' → ${p['evaluate_at']}に判定',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          verdictLabel[predicted] ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: verdictColor[predicted] ?? Colors.grey,
                          ),
                        ),
                        Text(
                          predictedAt,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
