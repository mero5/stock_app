import 'package:flutter/material.dart';
import 'terms_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingPage> _pages = [
    _OnboardingPage(
      icon: Icons.show_chart,
      color: Colors.blue,
      title: 'ウォッチリスト管理',
      description: '気になる日本株・米国株をウォッチリストに追加して\n株価をまとめて確認できます。',
      highlights: ['日本株・米国株に対応', 'リアルタイムに近い株価を表示', '前日比・騰落率を一目で確認'],
    ),
    _OnboardingPage(
      icon: Icons.smart_toy,
      color: Colors.purple,
      title: 'AI分析・相談',
      description: 'AIがテクニカル・ファンダメンタルを分析。\n買い・売りの判断をサポートします。',
      highlights: ['総合スコアで投資判断を補助', '短期・中期・長期で相談可能', 'ウォッチリスト全銘柄を一括診断'],
    ),
    _OnboardingPage(
      icon: Icons.calendar_month,
      color: Colors.teal,
      title: 'マーケットスケジュール',
      description: '決算・配当・FOMC・日銀会合など\n投資に重要なイベントをカレンダーで管理。',
      highlights: ['日経平均の騰落をカレンダーで表示', 'SQ・権利落ち日・満月も確認', 'ウォッチリスト銘柄の決算日を表示'],
    ),
    _OnboardingPage(
      icon: Icons.play_circle,
      color: Colors.red,
      title: 'YouTube要約',
      description: '投資系YouTubeチャンネルの最新動画を\nAIが自動で要約します。',
      highlights: ['チャンネルを登録してまとめて確認', 'AIが動画内容を日本語で要約', '日経・米国市場への見通しを分析'],
    ),
    _OnboardingPage(
      icon: Icons.bar_chart,
      color: Colors.orange,
      title: 'セクタートレンド',
      description: '日本・米国の主要セクターの\n騰落状況をリアルタイムで確認。',
      highlights: ['AIセクター・金融・エネルギーなど', '本日の上昇・下落セクターを表示', '5日間のトレンドも確認可能'],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _goToTerms();
    }
  }

  void _goToTerms() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TermsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // スキップボタン
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _goToTerms,
                  child: const Text(
                    'スキップ',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),

            // ページコンテンツ
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemCount: _pages.length,
                itemBuilder: (context, index) => _buildPage(_pages[index]),
              ),
            ),

            // インジケーター＋ボタン
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                children: [
                  // ドットインジケーター
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _currentPage ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _currentPage
                              ? _pages[_currentPage].color
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 次へ・始めるボタン
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pages[_currentPage].color,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _currentPage == _pages.length - 1 ? '利用規約を確認する' : '次へ',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // アイコン
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: page.color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 64, color: page.color),
          ),
          const SizedBox(height: 32),

          // タイトル
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // 説明
          Text(
            page.description,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black54,
              height: 1.7,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // ハイライト（機能リスト）
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: page.color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: page.color.withOpacity(0.2)),
            ),
            child: Column(
              children: page.highlights.map((h) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: page.color, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          h,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final List<String> highlights;

  const _OnboardingPage({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.highlights,
  });
}
