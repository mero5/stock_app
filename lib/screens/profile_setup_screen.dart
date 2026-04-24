import 'package:flutter/material.dart';
import '../services/user_profile_service.dart';
import 'home_screen.dart';

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

  String _investmentStyle = '中期';
  String _tradeType = '現物のみ';
  String _shortSelling = 'しない';
  String _analysisStyle = 'バランス型';
  String _riskLevel = '中';
  String _experience = '中級';
  String _market = '両方';
  String _concentration = '分散派';

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
    };
    final success = await UserProfileService.saveProfile(
      widget.userId,
      profile,
    );
    setState(() => _isSaving = false);

    if (!mounted) return;
    if (success) {
      if (widget.isInitial) {
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
      body: SingleChildScrollView(
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
}
