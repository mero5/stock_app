// ============================================================
// PortfolioScreen
// ポートフォリオ診断画面のUIのみを担当するWidget。
// ロジック・状態管理はPortfolioViewModelに委譲している。
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/portfolio_viewmodel.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import '../services/stock_service.dart';
import '../widgets/api_error_banner.dart';
import '../theme/app_theme.dart';

class PortfolioScreen extends StatefulWidget {
  final bool apiAvailable;
  final String apiErrorMsg;

  const PortfolioScreen({
    super.key,
    this.apiAvailable = true,
    this.apiErrorMsg = '',
  });

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  // ============================================================
  // ライフサイクル
  // ============================================================

  @override
  void initState() {
    super.initState();
    // ViewModelはProviderから取得するためpostFrameCallbackを使う
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
    });
  }

  /// ユーザープロファイルを取得してViewModelにセットする
  Future<void> _loadProfile() async {
    final userId = await AuthService.getUserId();
    if (userId == null) return;
    final profile = await UserProfileService.getProfile(userId);
    if (mounted) {
      context.read<PortfolioViewModel>().setUserProfile(profile);
    }
  }

  /// 銘柄検索ダイアログを表示して選択結果をViewModelにセットする
  Future<void> _searchStock(int index) async {
    final result = await showSearch<Map<String, String>?>(
      context: context,
      delegate: _StockSearchDelegate(),
    );
    if (result != null && mounted) {
      context.read<PortfolioViewModel>().setStock(index, result);
    }
  }

  // ============================================================
  // build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // ViewModelを監視（状態変化で自動再描画）
    final vm = context.watch<PortfolioViewModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('ポートフォリオ診断')),
      body: Column(
        children: [
          // APIエラーバナー
          if (!widget.apiAvailable) ApiErrorBanner(message: widget.apiErrorMsg),

          // 結果画面 or 入力画面を切り替え
          Expanded(
            child: vm.result != null ? _buildResult(vm) : _buildInput(vm),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 入力画面
  // ============================================================

  Widget _buildInput(PortfolioViewModel vm) {
    return Column(
      children: [
        // プライバシー注意書き
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.warning.shade50,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: AppTheme.warning.shade200),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber, color: AppTheme.warning, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⚠️ 入力した銘柄情報はサーバーに保存されません。\nAIへの問い合わせにのみ使用されます。',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    color: AppTheme.warning,
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
              // 保有銘柄カード一覧
              ...vm.holdings.asMap().entries.map(
                (e) => _buildHoldingCard(e.key, vm),
              ),

              // 銘柄追加ボタン
              OutlinedButton.icon(
                onPressed: () =>
                    context.read<PortfolioViewModel>().addHolding(),
                icon: const Icon(Icons.add),
                label: const Text('銘柄を追加'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),

              // 診断期間選択
              _buildPeriodSelector(vm),
              const SizedBox(height: AppTheme.spaceMd),

              // 診断実行ボタン
              ElevatedButton.icon(
                onPressed:
                    vm.isAnalyzing ||
                        vm.holdings.isEmpty ||
                        !widget.apiAvailable
                    ? null
                    : () => context.read<PortfolioViewModel>().analyze(),
                icon: vm.isAnalyzing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(vm.isAnalyzing ? '診断中...' : '一括AI診断を実行'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
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

  // ============================================================
  // 期間選択UI
  // ============================================================

  Widget _buildPeriodSelector(PortfolioViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '診断期間',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTheme.fontXl,
          ),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Row(
          children: ['短期', '中期', '長期'].map((v) {
            final selected = vm.selectedPeriod == v;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => context.read<PortfolioViewModel>().setPeriod(v),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? Colors.blue : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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
                            color: selected
                                ? Colors.white
                                : AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          v == '短期'
                              ? '数日〜2週間'
                              : v == '中期'
                              ? '1〜3ヶ月'
                              : '6ヶ月以上',
                          style: TextStyle(
                            fontSize: AppTheme.fontXs,
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
      ],
    );
  }

  // ============================================================
  // 銘柄入力カード
  // ============================================================

  Widget _buildHoldingCard(int index, PortfolioViewModel vm) {
    final h = vm.holdings[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー（銘柄番号・削除ボタン）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '銘柄 ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTheme.fontLg,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () =>
                      context.read<PortfolioViewModel>().removeHolding(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceSm),

            // 銘柄検索フィールド
            GestureDetector(
              onTap: () => _searchStock(index),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  color: Colors.grey.shade50,
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        h['name'].toString().isNotEmpty
                            ? '${h['name']}  (${h['code']})'
                            : '銘柄を検索',
                        style: TextStyle(
                          fontSize: AppTheme.fontLg,
                          color: h['name'].toString().isNotEmpty
                              ? AppTheme.textPrimary
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // 取得単価・保有株数
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    label: '取得単価（任意）',
                    hint: '例：3500',
                    onChanged: (v) => context
                        .read<PortfolioViewModel>()
                        .updateHolding(index, 'cost_price', double.tryParse(v)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField(
                    label: '保有株数（任意）',
                    hint: '例：100',
                    onChanged: (v) => context
                        .read<PortfolioViewModel>()
                        .updateHolding(index, 'shares', int.tryParse(v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 取引種別・ポジション選択
            Row(
              children: [
                Expanded(
                  child: _toggleField(
                    label: '取引種別',
                    options: ['現物', '信用'],
                    selected: h['trade_type'],
                    onSelect: (v) => context
                        .read<PortfolioViewModel>()
                        .updateHolding(index, 'trade_type', v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _toggleField(
                    label: 'ポジション',
                    // 現物の場合は買いのみ選択可能
                    options: h['trade_type'] == '現物' ? ['買い'] : ['買い', '空売り'],
                    selected: h['position'],
                    onSelect: (v) => context
                        .read<PortfolioViewModel>()
                        .updateHolding(index, 'position', v),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 結果画面
  // ============================================================

  Widget _buildResult(PortfolioViewModel vm) {
    final market =
        vm.result!['market_environment'] as Map<String, dynamic>? ?? {};
    final holdings = vm.result!['holdings'] as List? ?? [];
    final analysis =
        vm.result!['portfolio_analysis'] as Map<String, dynamic>? ?? {};

    final riskMode = market['risk_mode'] ?? 'neutral';
    final riskColor = riskMode == 'risk_on'
        ? AppTheme.bullish
        : riskMode == 'risk_off'
        ? AppTheme.bearish
        : AppTheme.warning;
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
              // 市場環境カード
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
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
                              fontSize: AppTheme.fontXl,
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
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusXl,
                              ),
                              border: Border.all(
                                color: riskColor.withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              riskLabel,
                              style: TextStyle(
                                color: riskColor,
                                fontSize: AppTheme.fontMd,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spaceSm),
                      Text(
                        market['summary'] ?? '',
                        style: const TextStyle(
                          fontSize: AppTheme.fontLg,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spaceSm),

              // 各銘柄の診断結果
              ...holdings.map(
                (h) => _buildHoldingResult(h as Map<String, dynamic>),
              ),

              // ポートフォリオ総評
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
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
                          fontSize: AppTheme.fontXl,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if ((analysis['sector_balance'] ?? '').isNotEmpty) ...[
                        const Text(
                          'セクターバランス',
                          style: TextStyle(
                            fontSize: AppTheme.fontMd,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spaceXs),
                        Text(
                          analysis['sector_balance'],
                          style: const TextStyle(
                            fontSize: AppTheme.fontLg,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if ((analysis['concentration_risk'] ?? '')
                          .isNotEmpty) ...[
                        const Text(
                          '集中リスク',
                          style: TextStyle(
                            fontSize: AppTheme.fontMd,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spaceXs),
                        Text(
                          analysis['concentration_risk'],
                          style: const TextStyle(
                            fontSize: AppTheme.fontLg,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if ((analysis['overall_comment'] ?? '').isNotEmpty) ...[
                        const Text(
                          '総評',
                          style: TextStyle(
                            fontSize: AppTheme.fontMd,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spaceXs),
                        Text(
                          analysis['overall_comment'],
                          style: const TextStyle(
                            fontSize: AppTheme.fontLg,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
            ],
          ),
        ),

        // プロンプト確認ボタン
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => _showPromptSheet(vm),
              icon: const Icon(Icons.code, size: 16),
              label: const Text(
                'AIに渡したプロンプトを確認',
                style: TextStyle(fontSize: AppTheme.fontMd),
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
              onPressed: () => context.read<PortfolioViewModel>().resetResult(),
              icon: const Icon(Icons.edit),
              label: const Text('銘柄を編集して再診断'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // プロンプト確認シート
  // ============================================================

  void _showPromptSheet(PortfolioViewModel vm) {
    final prompt = vm.result?['_prompt']?.toString() ?? '取得できませんでした';
    final holdingsData = vm.result?['_holdings_data'] as List? ?? [];

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
              const Text(
                '📊 取得データ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: AppTheme.spaceSm),
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
                            fontSize: AppTheme.fontLg,
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
              const Text(
                '📝 AIプロンプト全文',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: AppTheme.spaceSm),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: SelectableText(
                  prompt,
                  style: const TextStyle(
                    fontSize: AppTheme.fontSm,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 銘柄診断結果カード
  // ============================================================

  Widget _buildHoldingResult(Map<String, dynamic> h) {
    final verdict = h['verdict'] ?? '様子見';
    final verdictMap = {
      '継続保有': (Colors.blue, Icons.pause_circle),
      '買い増し': (AppTheme.bullish, Icons.add_chart),
      '利確推奨': (AppTheme.bearish, Icons.trending_up),
      '損切り推奨': (AppTheme.bearish.shade800, Icons.trending_down),
    };
    final (color, icon) =
        verdictMap[verdict] ?? (Colors.grey, Icons.help_outline);

    final plPct = h['profit_loss_pct'];
    final plYen = h['profit_loss_yen'];
    final isProfit = plPct != null && plPct is num && (plPct as num) >= 0;
    final prob = h['probability'] as Map<String, dynamic>? ?? {};
    final confidence = h['confidence'] as Map<String, dynamic>? ?? {};
    final priceStrategy = h['price_strategy'] as Map<String, dynamic>? ?? {};
    final macroImpact = h['macro_impact'] as Map<String, dynamic>? ?? {};
    final positivePoints = h['positive_points'] as List? ?? [];
    final negativePoints = h['negative_points'] as List? ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 銘柄名・判定バッジ
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
                          fontSize: AppTheme.fontMd,
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
                          fontSize: AppTheme.fontMd,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceMd),

            // 株価・損益チップ
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip(
                  '現在値',
                  '¥${_fmt(h['current_price'])}',
                  AppTheme.textPrimary,
                ),
                if (plPct != null && plPct is num)
                  _infoChip(
                    '損益',
                    '${(plPct as num) >= 0 ? '+' : ''}${(plPct as num).toStringAsFixed(1)}%'
                        '${plYen != null ? '  ¥${_fmtInt(plYen)}' : ''}',
                    isProfit ? AppTheme.bullish : AppTheme.bearish,
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceMd),

            // 判断確率バー
            const Text(
              '📊 判断確率',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTheme.fontLg,
              ),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            ...['hold', 'add', 'take_profit', 'cut_loss'].map((key) {
              final labelMap = {
                'hold': ('継続保有', Colors.blue),
                'add': ('買い増し', AppTheme.bullish),
                'take_profit': ('利確', AppTheme.bearish),
                'cut_loss': ('損切り', AppTheme.warning),
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
                            style: const TextStyle(fontSize: AppTheme.fontMd),
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
                            fontSize: AppTheme.fontMd,
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
                            fontSize: AppTheme.fontSm,
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: AppTheme.spaceXs),

            // 信頼度
            if (confidence.isNotEmpty) ...[
              const Divider(),
              Row(
                children: [
                  const Text(
                    '信頼度：',
                    style: TextStyle(
                      fontSize: AppTheme.fontMd,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  _confidenceBadge(confidence['value'] ?? 'medium'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      confidence['reason'] ?? '',
                      style: const TextStyle(
                        fontSize: AppTheme.fontSm,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(),

            // 価格戦略
            const Text(
              '💰 価格戦略',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTheme.fontLg,
              ),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            if (priceStrategy['take_profit'] != null) ...[
              _strategyRow(
                '利確目安',
                '¥${_fmt((priceStrategy['take_profit'] as Map)['value'])}',
                (priceStrategy['take_profit'] as Map)['reason'] ?? '',
                AppTheme.bearish,
              ),
              const SizedBox(height: 6),
            ],
            if (priceStrategy['stop_loss'] != null)
              _strategyRow(
                '損切ライン',
                '¥${_fmt((priceStrategy['stop_loss'] as Map)['value'])}',
                (priceStrategy['stop_loss'] as Map)['reason'] ?? '',
                AppTheme.warning,
              ),
            const Divider(),

            // マクロ影響
            if (macroImpact.isNotEmpty) ...[
              Row(
                children: [
                  const Text(
                    '🌍 市場環境の影響：',
                    style: TextStyle(
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _macroImpactBadge(macroImpact['value'] ?? 'neutral'),
                ],
              ),
              const SizedBox(height: AppTheme.spaceXs),
              Text(
                macroImpact['reason'] ?? '',
                style: const TextStyle(
                  fontSize: AppTheme.fontMd,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const Divider(),
            ],

            // ポジティブポイント
            if (positivePoints.isNotEmpty) ...[
              const Text(
                '✅ 保有・買い増し根拠',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTheme.fontLg,
                ),
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
                        style: TextStyle(
                          color: AppTheme.bullish,
                          fontSize: AppTheme.fontLg,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          p.toString(),
                          style: const TextStyle(
                            fontSize: AppTheme.fontMd,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spaceSm),
            ],

            // ネガティブポイント
            if (negativePoints.isNotEmpty) ...[
              const Text(
                '⚠️ リスク・売却根拠',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTheme.fontLg,
                ),
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
                        style: TextStyle(
                          color: AppTheme.bearish,
                          fontSize: AppTheme.fontLg,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          p.toString(),
                          style: const TextStyle(
                            fontSize: AppTheme.fontMd,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
            ],

            // 総合サマリー
            const Text(
              '📝 総合サマリー',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTheme.fontLg,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              h['summary'] ?? '',
              style: const TextStyle(fontSize: AppTheme.fontLg, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 共通UIパーツ
  // ============================================================

  /// 数値入力フィールド（取得単価・保有株数用）
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
          style: const TextStyle(
            fontSize: AppTheme.fontSm,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        TextField(
          keyboardType: TextInputType.number,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: AppTheme.fontMd),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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

  /// トグル選択フィールド（現物/信用、買い/空売り用）
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
          style: const TextStyle(
            fontSize: AppTheme.fontSm,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
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
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    opt,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppTheme.fontMd,
                      color: isSelected ? Colors.white : AppTheme.textPrimary,
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

  /// 価格戦略の行（利確・損切り用）
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
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: AppTheme.fontXl,
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
                fontSize: AppTheme.fontSm,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }

  /// 信頼度バッジ（high/medium/low）
  Widget _confidenceBadge(String value) {
    final map = {
      'high': ('高', AppTheme.bearish),
      'medium': ('中', AppTheme.warning),
      'low': ('低', AppTheme.bullish),
    };
    final (label, color) = map[value] ?? ('中', AppTheme.warning);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTheme.fontSm,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// マクロ影響バッジ（positive/negative/neutral）
  Widget _macroImpactBadge(String value) {
    final map = {
      'positive': ('ポジティブ', AppTheme.bullish),
      'negative': ('ネガティブ', AppTheme.bearish),
      'neutral': ('中立', Colors.grey),
    };
    final (label, color) = map[value] ?? ('中立', Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTheme.fontSm,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 情報チップ（現在値・損益表示用）
  Widget _infoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: AppTheme.fontXs,
              color: AppTheme.textTertiary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: AppTheme.fontLg,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// データ行（プロンプト確認シート用）
  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: AppTheme.fontMd,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 数値フォーマット（小数点以下の処理）
  String _fmt(dynamic val) {
    if (val == null) return '---';
    if (val is String) return val;
    final n = (val as num).toDouble();
    return n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 1);
  }

  /// 整数フォーマット（3桁カンマ区切り）
  String _fmtInt(dynamic val) {
    if (val == null) return '---';
    if (val is String) return val;
    final n = (val as num).toInt();
    return n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }
}

// ============================================================
// 銘柄検索デリゲート
// SearchDelegateを継承した銘柄検索UI
// showSearch()で呼び出され、選択した銘柄をMapで返す
// ============================================================
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
