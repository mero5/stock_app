import 'package:flutter/material.dart';
import '../services/user_profile_service.dart';
import 'home_screen.dart';
import '../widgets/notice_dialog.dart';

// AI分析の優先度：項目キー → 表示名
const Map<String, String> kPriorityLabels = {
  'capital_flow': '資金流入・テーマ性',
  'sector_strength': 'セクター強度',
  'supply_demand': '需給',
  'trend': 'トレンド',
  'technical': 'テクニカル指標',
  'macro': 'マクロ環境',
  'fundamental': 'ファンダメンタル',
  'earnings_alert': '決算アラート',
  'news': 'ニュース・材料',
};

// 期間ごとのデフォルト優先順位（バックエンド services/technical.py の
// DEFAULT_PRIORITY と一致させること）
const Map<String, List<String>> kDefaultPriority = {
  '短期': [
    'capital_flow',
    'sector_strength',
    'supply_demand',
    'trend',
    'technical',
    'macro',
    'earnings_alert',
    'news',
    'fundamental',
  ],
  '中期': [
    'sector_strength',
    'capital_flow',
    'macro',
    'trend',
    'fundamental',
    'supply_demand',
    'technical',
    'earnings_alert',
    'news',
  ],
  '長期': [
    'fundamental',
    'macro',
    'sector_strength',
    'technical',
    'capital_flow',
    'trend',
    'news',
    'supply_demand',
    'earnings_alert',
  ],
};

const List<int> kShortMaxDayOptions = [7, 10, 14, 21];
const List<int> kMediumMaxDayOptions = [60, 90, 120];

class ProfileSetupScreen extends StatefulWidget {
  final String userId;
  final bool isInitial; // 初回かどうか
  const ProfileSetupScreen({
    super.key,
    required this.userId,
    this.isInitial = true,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  bool _isSaving = false;
  bool _isLoadingProfile = false;

  String _investmentStyle = '中期';
  String _tradeType = '現物のみ';
  String _shortSelling = 'しない';
  String _analysisStyle = 'バランス型';
  String _riskLevel = '中';
  String _experience = '中級';
  String _market = '両方';
  String _concentration = '分散派';

  // AI分析の優先度（期間ごと）
  String _priorityTab = '短期';
  final Map<String, List<String>> _priority = {
    '短期': List<String>.from(kDefaultPriority['短期']!),
    '中期': List<String>.from(kDefaultPriority['中期']!),
    '長期': List<String>.from(kDefaultPriority['長期']!),
  };

  // 期間の日数境界
  int _shortMaxDays = 14;
  int _mediumMaxDays = 90;

  @override
  void initState() {
    super.initState();
    if (!widget.isInitial) {
      _loadExistingProfile();
    }
  }

  Future<void> _loadExistingProfile() async {
    setState(() => _isLoadingProfile = true);
    final profile = await UserProfileService.getProfile(widget.userId);
    if (profile != null && mounted) {
      setState(() {
        _investmentStyle = profile['investment_style'] ?? _investmentStyle;
        _tradeType = profile['trade_type'] ?? _tradeType;
        _shortSelling = profile['short_selling'] ?? _shortSelling;
        _analysisStyle = profile['analysis_style'] ?? _analysisStyle;
        _riskLevel = profile['risk_level'] ?? _riskLevel;
        _experience = profile['experience'] ?? _experience;
        _market = profile['market'] ?? _market;
        _concentration = profile['concentration'] ?? _concentration;

        for (final period in ['短期', '中期', '長期']) {
          final key = period == '短期'
              ? 'priority_short'
              : period == '中期'
                  ? 'priority_medium'
                  : 'priority_long';
          final raw = profile[key];
          if (raw is List && raw.isNotEmpty) {
            // 未知のキーは除外し、抜けはデフォルトで補完（バックエンドと同じルール）
            final valid = raw
                .map((e) => e.toString())
                .where((k) => kPriorityLabels.containsKey(k))
                .toList();
            for (final k in kDefaultPriority[period]!) {
              if (!valid.contains(k)) valid.add(k);
            }
            _priority[period] = valid;
          }
        }
        _shortMaxDays =
            (profile['period_short_max_days'] as num?)?.toInt() ?? 14;
        _mediumMaxDays =
            (profile['period_medium_max_days'] as num?)?.toInt() ?? 90;
        if (_mediumMaxDays <= _shortMaxDays) {
          _mediumMaxDays = _shortMaxDays + 60;
        }
      });
    }
    if (mounted) setState(() => _isLoadingProfile = false);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final profile = {
      "investment_style": _investmentStyle,
      "trade_type": _tradeType,
      "short_selling": _shortSelling,
      "analysis_style": _analysisStyle,
      "risk_level": _riskLevel,
      "experience": _experience,
      "market": _market,
      "concentration": _concentration,
      "priority_short": _priority['短期'],
      "priority_medium": _priority['中期'],
      "priority_long": _priority['長期'],
      "period_short_max_days": _shortMaxDays,
      "period_medium_max_days": _mediumMaxDays,
    };
    final success = await UserProfileService.saveProfile(
      widget.userId,
      profile,
    );
    setState(() => _isSaving = false);

    if (!mounted) return;
    if (success) {
      if (widget.isInitial) {
        // 新規ユーザーに「新しくなりました」と伝える意味はないので、
        // ポップアップを出さずに既読扱いにしておく
        await NoticeDialog.markAsRead();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('プロファイルを保存しました')));
      }
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存に失敗しました。もう一度お試しください。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isInitial ? '投資スタイル設定' : 'プロファイル編集'),
        automaticallyImplyLeading: !widget.isInitial,
      ),
      body: _isLoadingProfile
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.isInitial) ...[
                    const Text(
                      'あなたの投資スタイルを教えてください',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'AI分析の精度向上に使用します。後から変更可能です。',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                  ],

                  _section(
                    '投資期間',
                    '主にどの期間で投資しますか？',
                    ['短期（数日〜2週間）', '中期（1〜3ヶ月）', '長期（6ヶ月以上）'],
                    _investmentStyle,
                    (v) => setState(() => _investmentStyle = v),
                  ),

                  _section(
                    '取引種別',
                    '信用取引を利用しますか？',
                    ['現物のみ', '信用あり'],
                    _tradeType,
                    (v) => setState(() => _tradeType = v),
                  ),

                  _section(
                    '空売り',
                    '空売りをしますか？',
                    ['しない', 'する'],
                    _shortSelling,
                    (v) => setState(() => _shortSelling = v),
                  ),

                  _section(
                    '分析スタイル',
                    '何を重視して分析しますか？',
                    ['テクニカル重視', 'ファンダ重視', 'バランス型'],
                    _analysisStyle,
                    (v) => setState(() => _analysisStyle = v),
                  ),

                  _section(
                    'リスク許容度',
                    '損失に対してどれくらい耐えられますか？',
                    ['低（守り重視）', '中', '高（積極的）'],
                    _riskLevel,
                    (v) => setState(() => _riskLevel = v),
                  ),

                  _section(
                    '投資経験',
                    '投資歴はどれくらいですか？',
                    ['初心者（1年未満）', '中級（1〜5年）', '上級（5年以上）'],
                    _experience,
                    (v) => setState(() => _experience = v),
                  ),

                  _section(
                    '投資対象',
                    '主にどこに投資していますか？',
                    ['日本株のみ', '米国株のみ', '両方'],
                    _market,
                    (v) => setState(() => _market = v),
                  ),

                  _section(
                    '分散方針',
                    '銘柄の集中度はどうしますか？',
                    ['分散派（多銘柄）', '集中派（少数銘柄）'],
                    _concentration,
                    (v) => setState(() => _concentration = v),
                  ),

                  const Text(
                    'AI分析の優先度',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '期間ごとに、AIが何を重視して分析するかの順番を設定できます',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  _buildPriorityEditor(),
                  const Divider(height: 32),

                  const Text(
                    '期間の日数設定',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '短期・中期・長期の境界となる日数を設定できます',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  _buildPeriodDaysEditor(),

                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              widget.isInitial ? '設定して始める' : '保存する',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _section(
    String title,
    String subtitle,
    List<String> options,
    String selected,
    Function(String) onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: options.map((opt) {
            final isSelected =
                selected == opt ||
                (opt.contains('（') && selected == opt.split('（')[0]);
            return GestureDetector(
              onTap: () {
                // 括弧なしの値を保存
                final val = opt.contains('（') ? opt.split('（')[0] : opt;
                onSelect(val);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  opt,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const Divider(height: 24),
      ],
    );
  }

  // AI分析の優先度エディタ：期間タブ＋順位ごとのプルダウン
  Widget _buildPriorityEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: ['短期', '中期', '長期'].map((p) {
            final selected = _priorityTab == p;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _priorityTab = p),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? Colors.blue : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? Colors.blue : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    p,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        ...List.generate(_priority[_priorityTab]!.length, (i) {
          final list = _priority[_priorityTab]!;
          final current = list[i];
          // 9項目すべてを選択肢に出し、選んだ項目と現在の項目を入れ替える
          final options = kPriorityLabels.keys.toList();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '${i + 1}位',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    // initialValueはFormFieldの仕様上、再ビルドしても表示が
                    // 追従しない（FormFieldState.didUpdateWidgetが見ていない）。
                    // 期間タブ切替・順位入れ替えで値が変わるためvalueを使う。
                    // ignore: deprecated_member_use
                    value: current,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: options
                        .map(
                          (k) => DropdownMenuItem(
                            value: k,
                            child: Text(
                              kPriorityLabels[k] ?? k,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null || v == current) return;
                      setState(() {
                        final target = _priority[_priorityTab]!;
                        // 選んだ項目が今いる順位に、現在の項目を移す（入れ替え）
                        final from = target.indexOf(v);
                        target[i] = v;
                        if (from != -1) target[from] = current;
                      });
                    },
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // 期間の日数境界エディタ
  Widget _buildPeriodDaysEditor() {
    final shortOptions = <int>{...kShortMaxDayOptions, _shortMaxDays}.toList()
      ..sort();
    final mediumOptions =
        <int>{...kMediumMaxDayOptions, _mediumMaxDays}
            .where((d) => d > _shortMaxDays)
            .toList()
          ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 90,
              child: Text('短期は', style: TextStyle(fontSize: 13)),
            ),
            DropdownButton<int>(
              value: _shortMaxDays,
              items: shortOptions
                  .map(
                    (d) => DropdownMenuItem(value: d, child: Text('$d日まで')),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _shortMaxDays = v;
                  if (_mediumMaxDays <= _shortMaxDays) {
                    _mediumMaxDays = kMediumMaxDayOptions.firstWhere(
                      (d) => d > _shortMaxDays,
                      orElse: () => _shortMaxDays + 60,
                    );
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 90,
              child: Text('中期は', style: TextStyle(fontSize: 13)),
            ),
            DropdownButton<int>(
              value: _mediumMaxDays,
              items: mediumOptions
                  .map(
                    (d) => DropdownMenuItem(value: d, child: Text('$d日まで')),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _mediumMaxDays = v);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '長期は$_mediumMaxDays日超',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
