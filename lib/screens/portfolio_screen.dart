import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import '../services/stock_service.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final List<Map<String, dynamic>> _holdings = [];
  Map<String, dynamic>? _result;
  bool _isAnalyzing = false;
  String? _userId;
  Map<String, dynamic>? _userProfile;
  String _lastPrompt = '';
  String _selectedPeriod = '中期';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final userId = await AuthService.getUserId();
    if (userId == null) return;
    final profile = await UserProfileService.getProfile(userId);
    setState(() {
      _userId = userId;
      _userProfile = profile;
    });
  }

  void _addHolding() {
    if (_holdings.length >= 10) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('最大10銘柄まで追加できます')));
      return;
    }
    setState(() {
      _holdings.add({
        "code": "",
        "name": "",
        "ticker_code": "",
        "cost_price": null,
        "shares": null,
        "trade_type": "現物",
        "position": "買い",
      });
    });
  }

  void _removeHolding(int index) {
    setState(() => _holdings.removeAt(index));
  }

  Future<void> _searchStock(int index) async {
    final result = await showSearch<Map<String, String>?>(
      context: context,
      delegate: _StockSearchDelegate(),
    );
    if (result != null) {
      setState(() {
        _holdings[index]['code'] = result['code'] ?? '';
        _holdings[index]['name'] = result['name'] ?? '';
        final code = result['code'] ?? '';
        _holdings[index]['ticker_code'] = () {
          if (RegExp(r'^\d{4}$').hasMatch(code)) return '$code.T';
          if (RegExp(r'^\d{5}$').hasMatch(code))
            return '${code.substring(0, 4)}.T';
          return code;
        }();
      });
    }
  }

  Future<void> _analyze() async {
    // 銘柄が1つも設定されていない場合
    if (_holdings.isEmpty ||
        _holdings.every((h) => h['code'].toString().isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('銘柄を1つ以上追加してください')));
      return;
    }
    // 銘柄コード未設定のカードを除外
    final validHoldings = _holdings
        .where((h) => h['code'].toString().isNotEmpty)
        .toList();

    setState(() {
      _isAnalyzing = true;
      _result = null;
    });

    try {
      _lastPrompt = jsonEncode({
        "user_profile": _userProfile ?? {},
        "holdings": validHoldings,
        "period": _selectedPeriod,
      });
      final res = await http.post(
        Uri.parse("${Constants.backendUrl}/portfolio/diagnosis"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_profile": _userProfile ?? {},
          "holdings": validHoldings,
        }),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() => _result = data);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('診断に失敗しました: $e')));
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ポートフォリオ診断')),
      body: _result != null ? _buildResult() : _buildInput(),
    );
  }

  // ── 入力画面 ──
  Widget _buildInput() {
    return Column(
      children: [
        // 注意書き
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⚠️ 入力した銘柄情報はサーバーに保存されません。\nAIへの問い合わせにのみ使用されます。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              ..._holdings.asMap().entries.map((e) => _buildHoldingCard(e.key)),
              // 追加ボタン
              OutlinedButton.icon(
                onPressed: _addHolding,
                icon: const Icon(Icons.add),
                label: const Text('銘柄を追加'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 期間選択
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '診断期間',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
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
                  ],
                ),
              ),
              // 診断ボタン
              ElevatedButton.icon(
                onPressed: _isAnalyzing || _holdings.isEmpty ? null : _analyze,
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
                label: Text(_isAnalyzing ? '診断中...' : '一括AI診断を実行'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHoldingCard(int index) {
    final h = _holdings[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '銘柄 ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () => _removeHolding(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 銘柄検索
            GestureDetector(
              onTap: () => _searchStock(index),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade50,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        h['name'].toString().isNotEmpty
                            ? '${h['name']}  (${h['code']})'
                            : '銘柄を検索',
                        style: TextStyle(
                          fontSize: 13,
                          color: h['name'].toString().isNotEmpty
                              ? Colors.black87
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // 取得単価・株数
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    label: '取得単価（任意）',
                    hint: '例：3500',
                    onChanged: (v) =>
                        _holdings[index]['cost_price'] = double.tryParse(v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField(
                    label: '保有株数（任意）',
                    hint: '例：100',
                    onChanged: (v) =>
                        _holdings[index]['shares'] = int.tryParse(v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 取引種別・ポジション
            Row(
              children: [
                Expanded(
                  child: _toggleField(
                    label: '取引種別',
                    options: ['現物', '信用'],
                    selected: h['trade_type'],
                    onSelect: (v) =>
                        setState(() => _holdings[index]['trade_type'] = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _toggleField(
                    label: 'ポジション',
                    options: ['買い', '空売り'],
                    selected: h['position'],
                    onSelect: (v) =>
                        setState(() => _holdings[index]['position'] = v),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField({
    required String label,
    required String hint,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 4),
        TextField(
          keyboardType: TextInputType.number,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _toggleField({
    required String label,
    required List<String> options,
    required String selected,
    required Function(String) onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 4),
        Row(
          children: options.map((opt) {
            final isSelected = selected == opt;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(opt),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    opt,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── 結果画面 ──
  Widget _buildResult() {
    final market =
        _result!['market_environment'] as Map<String, dynamic>? ?? {};
    final holdings = _result!['holdings'] as List? ?? [];
    final analysis =
        _result!['portfolio_analysis'] as Map<String, dynamic>? ?? {};

    final riskMode = market['risk_mode'] ?? 'neutral';
    final riskColor = riskMode == 'risk_on'
        ? Colors.red
        : riskMode == 'risk_off'
        ? Colors.green
        : Colors.orange;
    final riskLabel = riskMode == 'risk_on'
        ? '🟢 リスクオン'
        : riskMode == 'risk_off'
        ? '🔴 リスクオフ'
        : '🟡 中立';

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // 市場環境
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                color: riskColor.withOpacity(0.05),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '🌍 市場環境',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: riskColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: riskColor.withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              riskLabel,
                              style: TextStyle(
                                color: riskColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        market['summary'] ?? '',
                        style: const TextStyle(fontSize: 13, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 各銘柄
              ...holdings.map(
                (h) => _buildHoldingResult(h as Map<String, dynamic>),
              ),

              // ポートフォリオ総評
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📝 ポートフォリオ総評',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if ((analysis['sector_balance'] ?? '').isNotEmpty) ...[
                        const Text(
                          'セクターバランス',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          analysis['sector_balance'],
                          style: const TextStyle(fontSize: 13, height: 1.6),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if ((analysis['concentration_risk'] ?? '')
                          .isNotEmpty) ...[
                        const Text(
                          '集中リスク',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          analysis['concentration_risk'],
                          style: const TextStyle(fontSize: 13, height: 1.6),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if ((analysis['overall_comment'] ?? '').isNotEmpty) ...[
                        const Text(
                          '総評',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          analysis['overall_comment'],
                          style: const TextStyle(fontSize: 13, height: 1.6),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        // プロンプト確認ボタン
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => _showPromptSheet(),
              icon: const Icon(Icons.code, size: 16),
              label: const Text(
                'AIに渡したプロンプトを確認',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
        // 再診断ボタン
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _result = null),
              icon: const Icon(Icons.edit),
              label: const Text('銘柄を編集して再診断'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showPromptSheet() {
    final prompt = _result?['_prompt']?.toString() ?? '取得できませんでした';
    final holdingsData = _result?['_holdings_data'] as List? ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 取得データ一覧
              const Text(
                '📊 取得データ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              ...holdingsData.map((h) {
                final m = h as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m['name']}（${m['code']}）',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _dataRow('現在株価', '${m['current_price']}円'),
                        _dataRow('RSI(14)', '${m['rsi']}'),
                        _dataRow('MACD', '${m['macd']}'),
                        _dataRow('MA5', '${m['ma5']}円'),
                        _dataRow('MA25', '${m['ma25']}円'),
                        _dataRow(
                          '損益率',
                          m['profit_loss_pct'] != null
                              ? '${m['profit_loss_pct']}%'
                              : '未入力（取得単価なし）',
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const Divider(height: 24),
              // プロンプト全文
              const Text(
                '📝 AIプロンプト全文',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  prompt,
                  style: const TextStyle(fontSize: 11, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildHoldingResult(Map<String, dynamic> h) {
    final verdict = h['verdict'] ?? '様子見';
    final verdictMap = {
      '継続保有': (Colors.blue, Icons.pause_circle),
      '買い増し': (Colors.red, Icons.add_chart),
      '利確推奨': (Colors.green, Icons.trending_up),
      '損切り推奨': (Colors.green.shade800, Icons.trending_down),
    };
    final (color, icon) =
        verdictMap[verdict] ?? (Colors.grey, Icons.help_outline);

    final plPct = h['profit_loss_pct'];
    final plYen = h['profit_loss_yen'];
    final isProfit = plPct != null && (plPct as num) >= 0;

    final prob = h['probability'] as Map<String, dynamic>? ?? {};
    final confidence = h['confidence'] as Map<String, dynamic>? ?? {};
    final priceStrategy = h['price_strategy'] as Map<String, dynamic>? ?? {};
    final macroImpact = h['macro_impact'] as Map<String, dynamic>? ?? {};
    final positivePoints = h['positive_points'] as List? ?? [];
    final negativePoints = h['negative_points'] as List? ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 銘柄名・判定バッジ ──
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h['name'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        h['code'] ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: color),
                      const SizedBox(width: 4),
                      Text(
                        verdict,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 株価・損益 ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip(
                  '現在値',
                  '¥${_fmt(h['current_price'])}',
                  Colors.black87,
                ),
                if (plPct != null)
                  _infoChip(
                    '損益',
                    '${(plPct as num) >= 0 ? '+' : ''}${plPct.toStringAsFixed(1)}%'
                        '${plYen != null ? '  ¥${_fmtInt(plYen)}' : ''}',
                    isProfit ? Colors.red : Colors.green,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 確率バー ──
            const Text(
              '📊 判断確率',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            ...['hold', 'add', 'take_profit', 'cut_loss'].map((key) {
              final labelMap = {
                'hold': ('継続保有', Colors.blue),
                'add': ('買い増し', Colors.red),
                'take_profit': ('利確', Colors.green),
                'cut_loss': ('損切り', Colors.orange),
              };
              final (label, barColor) = labelMap[key]!;
              final entry = prob[key] as Map<String, dynamic>? ?? {};
              final val = (entry['value'] as num?)?.toInt() ?? 0;
              final reason = entry['reason'] ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: val / 100,
                                child: Container(
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: barColor.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$val%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: barColor,
                          ),
                        ),
                      ],
                    ),
                    if (reason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 60, top: 2),
                        child: Text(
                          reason,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),

            // ── 信頼度 ──
            if (confidence.isNotEmpty) ...[
              const Divider(),
              Row(
                children: [
                  const Text(
                    '信頼度：',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  _confidenceBadge(confidence['value'] ?? 'medium'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      confidence['reason'] ?? '',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(),

            // ── 価格戦略 ──
            const Text(
              '💰 価格戦略',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (priceStrategy['take_profit'] != null) ...[
              _strategyRow(
                '利確目安',
                '¥${_fmt((priceStrategy['take_profit'] as Map)['value'])}',
                (priceStrategy['take_profit'] as Map)['reason'] ?? '',
                Colors.green,
              ),
              const SizedBox(height: 6),
            ],
            if (priceStrategy['stop_loss'] != null) ...[
              _strategyRow(
                '損切ライン',
                '¥${_fmt((priceStrategy['stop_loss'] as Map)['value'])}',
                (priceStrategy['stop_loss'] as Map)['reason'] ?? '',
                Colors.orange,
              ),
            ],
            const Divider(),

            // ── マクロ影響 ──
            if (macroImpact.isNotEmpty) ...[
              Row(
                children: [
                  const Text(
                    '🌍 市場環境の影響：',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  _macroImpactBadge(macroImpact['value'] ?? 'neutral'),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                macroImpact['reason'] ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const Divider(),
            ],

            // ── ポジティブ・ネガティブ ──
            if (positivePoints.isNotEmpty) ...[
              const Text(
                '✅ 保有・買い増し根拠',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              ...positivePoints.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '・',
                        style: TextStyle(color: Colors.red, fontSize: 13),
                      ),
                      Expanded(
                        child: Text(
                          p.toString(),
                          style: const TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (negativePoints.isNotEmpty) ...[
              const Text(
                '⚠️ リスク・売却根拠',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              ...negativePoints.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '・',
                        style: TextStyle(color: Colors.green, fontSize: 13),
                      ),
                      Expanded(
                        child: Text(
                          p.toString(),
                          style: const TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
            ],

            // ── サマリー ──
            const Text(
              '📝 総合サマリー',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              h['summary'] ?? '',
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _strategyRow(String label, String value, String reason, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        if (reason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              reason,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _confidenceBadge(String value) {
    final map = {
      'high': ('高', Colors.green),
      'medium': ('中', Colors.orange),
      'low': ('低', Colors.red),
    };
    final (label, color) = map[value] ?? ('中', Colors.orange);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _macroImpactBadge(String value) {
    final map = {
      'positive': ('ポジティブ', Colors.red),
      'negative': ('ネガティブ', Colors.green),
      'neutral': ('中立', Colors.grey),
    };
    final (label, color) = map[value] ?? ('中立', Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.black45),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(dynamic val) {
    if (val == null) return '---';
    final n = (val as num).toDouble();
    return n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 1);
  }

  String _fmtInt(dynamic val) {
    if (val == null) return '---';
    final n = (val as num).toInt();
    return n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }
}

// 銘柄検索デリゲート
class _StockSearchDelegate extends SearchDelegate<Map<String, String>?> {
  List<Map<String, String>> _results = [];
  bool _isSearching = false;

  @override
  String get searchFieldLabel => '銘柄名 or コードで検索';

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.length < 2) {
      return const Center(
        child: Text('2文字以上入力してください', style: TextStyle(color: Colors.grey)),
      );
    }
    _doSearch(context);
    return _buildList(context);
  }

  void _doSearch(BuildContext context) async {
    if (_isSearching) return;
    _isSearching = true;
    try {
      final results = await StockService.search(query);
      _results = results
          .map<Map<String, String>>(
            (e) => {
              'code': e['code']?.toString() ?? '',
              'name': e['name']?.toString() ?? '',
            },
          )
          .toList();
    } catch (_) {}
    _isSearching = false;
  }

  Widget _buildList(BuildContext context) {
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final r = _results[i];
        return ListTile(
          title: Text(r['name'] ?? ''),
          subtitle: Text(r['code'] ?? ''),
          onTap: () => close(context, r),
        );
      },
    );
  }
}
