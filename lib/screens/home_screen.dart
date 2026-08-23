// ============================================================
// HomeScreen
// ホーム画面のUIのみを担当するWidget。
//
// ロジック（データ取得・状態管理）はHomeViewModelに委譲している。
// このファイルはUIの描画に専念する。
//
// context.watch<HomeViewModel>() でViewModelの状態変化を監視し、
// 状態が変わると自動で再描画される。
// context.read<HomeViewModel>() はイベント時にメソッドを呼ぶだけで
// 再描画は不要な場合に使用する。
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import '../viewmodels/home_viewmodel.dart';
import '../models/stock.dart';
import '../services/stock_service.dart';
import '../utils/formatter.dart';
import 'login_screen.dart';
import 'search_screen.dart';
import 'detail_screen.dart';
import 'youtube_screen.dart';
import 'schedule_screen.dart';
import 'market_screen.dart';
import 'settings_screen.dart';
import 'portfolio_screen.dart';
import '../widgets/api_error_banner.dart';
import 'package:provider/provider.dart';
import '../viewmodels/detail_viewmodel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ============================================================
  // 画面固有の状態
  // ViewModelで管理する必要がない純粋なUI状態のみここに持つ
  // ============================================================

  /// 現在選択中のボトムナビゲーションのインデックス
  int _currentIndex = 0;

  // ============================================================
  // ログアウト
  // ============================================================

  /// ログアウト確認ダイアログを表示して実行する
  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ログアウト', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await Amplify.Auth.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  // ============================================================
  // AI診断モーダル
  // ============================================================

  /// ウォッチリスト全銘柄をAI一括診断するモーダルを表示する
  void _showAiDiagnosis(List<Stock> watchList) {
    // モーダル内の状態はStatefulBuilderで管理
    String selectedPeriod = '短期';
    bool isAnalyzing = false;
    List<Map<String, dynamic>> results = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (_, scrollController) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ヘッダー
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🤖 AI診断',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 期間選択ボタン
                const Text(
                  '診断期間を選択',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['短期', '中期', '長期'].map((v) {
                    final selected = selectedPeriod == v;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () => setModalState(() => selectedPeriod = v),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
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
                const SizedBox(height: 16),

                // 診断実行ボタン
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isAnalyzing || watchList.isEmpty
                        ? null
                        : () async {
                            setModalState(() => isAnalyzing = true);
                            final res = <Map<String, dynamic>>[];
                            for (final stock in watchList) {
                              try {
                                final result = await StockService.consult(
                                  code: stock.displayCode,
                                  name: stock.name,
                                  direction: '買い',
                                  tradeType: '現物取引',
                                  period: selectedPeriod,
                                  extraQuestions: [],
                                  price: double.tryParse(
                                    stock.price.replaceAll(',', ''),
                                  ),
                                );
                                res.add({
                                  'code': stock.displayCode,
                                  'name': stock.name,
                                  'price': stock.price,
                                  'change': stock.change,
                                  'isPositive': stock.isPositive,
                                  ...result,
                                });
                              } catch (e) {
                                debugPrint('AI診断エラー ${stock.displayCode}: $e');
                              }
                            }
                            setModalState(() {
                              results = res;
                              isAnalyzing = false;
                            });
                          },
                    icon: isAnalyzing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      isAnalyzing
                          ? '診断中... (${watchList.length}銘柄)'
                          : 'ウォッチリストを一括診断',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 診断結果一覧
                Expanded(
                  child: results.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 48,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                watchList.isEmpty
                                    ? 'ウォッチリストに銘柄を追加してください'
                                    : '期間を選択して診断してください',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: results.length,
                          itemBuilder: (_, i) =>
                              _buildDiagnosisCard(results[i]),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 診断結果カード（AI一括診断用）
  // ============================================================

  /// AI一括診断の結果を1銘柄分表示するカード
  Widget _buildDiagnosisCard(Map<String, dynamic> r) {
    final judgment = r['judgment'] as String? ?? '';
    final judgeMap = {
      '適切': (Colors.red, Icons.trending_up, '買い有利'),
      '要注意': (Colors.orange, Icons.warning, '要注意'),
      '不適切': (Colors.green, Icons.trending_down, '見送り'),
    };
    final (color, icon, label) =
        judgeMap[judgment] ?? (Colors.grey, Icons.help, '不明');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 左：銘柄情報・判断理由
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    r['code'],
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  if ((r['judgment_reason'] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        r['judgment_reason'],
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 右：判定バッジ
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
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

  // ============================================================
  // ホームタブのUI
  // ============================================================

  /// ウォッチリストを表示するホームタブ
  /// ViewModelから状態を受け取ってUIを描画する
  Widget _buildHomeTab(HomeViewModel vm) {
    if (vm.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // APIエラーバナー（エラーの時だけ表示）
        if (!vm.apiAvailable) ApiErrorBanner(message: vm.apiErrorMsg),

        // ウォッチリスト
        if (vm.watchList.isEmpty)
          const Expanded(child: Center(child: Text('銘柄を追加してください')))
        else
          Expanded(
            child: ListView.builder(
              itemCount: vm.watchList.length,
              itemBuilder: (context, index) {
                final stock = vm.watchList[index];
                final isSelected = vm.selectedCodes.contains(stock.displayCode);

                return ListTile(
                  // 編集モード時はチェックボックス、通常時はチャートアイコン
                  leading: vm.editMode
                      ? Checkbox(
                          value: isSelected,
                          onChanged: (_) => context
                              .read<HomeViewModel>()
                              .toggleSelect(stock.displayCode),
                        )
                      : const Icon(Icons.show_chart),
                  title: Text(stock.name),
                  subtitle: Text(stock.displayCode),
                  trailing: vm.editMode
                      ? null
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              stock.price != '---' ? '¥${stock.price}' : '---',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (stock.change.isNotEmpty)
                              Text(
                                '${stock.change}  ${stock.changePct}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: stock.isPositive
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ),
                          ],
                        ),
                  onTap: vm.editMode
                      ? () => context.read<HomeViewModel>().toggleSelect(
                          stock.displayCode,
                        )
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider(
                              create: (_) => DetailViewModel(),
                              child: DetailScreen(
                                code: stock.displayCode,
                                name: stock.name,
                              ),
                            ),
                          ),
                        ),
                );
              },
            ),
          ),

        // 削除ボタン（編集モード且つ選択中の銘柄がある場合のみ表示）
        if (vm.editMode && vm.selectedCodes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.read<HomeViewModel>().deleteSelected(),
                icon: const Icon(Icons.delete),
                label: Text('${vm.selectedCodes.length}件削除'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ============================================================
  // メインのbuild
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // ViewModelを監視（状態変化で自動再描画）
    final vm = context.watch<HomeViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('株アプリ'),
        actions: [
          // ホームタブのみアクションボタンを表示
          if (_currentIndex == 0) ...[
            // 銘柄追加ボタン
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '銘柄を追加',
              onPressed: () async {
                // 編集モードをリセット
                context.read<HomeViewModel>().toggleEditMode();
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SearchScreen(
                      watchList: vm.watchList,
                      onAdd: (_) async =>
                          context.read<HomeViewModel>().loadFavorites(),
                    ),
                  ),
                );
                // 戻ってきた時もリスト更新
                if (mounted) {
                  context.read<HomeViewModel>().loadFavorites();
                }
              },
            ),

            // 編集モード切り替えボタン
            IconButton(
              icon: Icon(vm.editMode ? Icons.check : Icons.edit),
              onPressed: () => context.read<HomeViewModel>().toggleEditMode(),
            ),

            // AI一括診断ボタン
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'AI一括診断',
              onPressed: () => _showAiDiagnosis(vm.watchList),
            ),
          ],

          // ログアウトメニュー
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'logout') _confirmLogout();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text('ログアウト', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),

      // 各タブのコンテンツ
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(vm),
          const YoutubeScreen(),
          ScheduleScreen(
            apiAvailable: vm.apiAvailable,
            apiErrorMsg: vm.apiErrorMsg,
          ),
          MarketScreen(
            apiAvailable: vm.apiAvailable,
            apiErrorMsg: vm.apiErrorMsg,
          ),
          const SettingsScreen(),
          PortfolioScreen(
            apiAvailable: vm.apiAvailable,
            apiErrorMsg: vm.apiErrorMsg,
          ),
        ],
      ),

      // ボトムナビゲーション
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) async {
          // ホームタブに戻った時はリスト更新
          if (index == 0) {
            context.read<HomeViewModel>().loadFavorites();
          }
          setState(() {
            _currentIndex = index;
          });
          // タブ切り替え時は編集モードをリセット
          context.read<HomeViewModel>().toggleEditMode();
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ホーム'),
          BottomNavigationBarItem(
            icon: Icon(Icons.play_circle),
            label: 'YouTube',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: 'スケジュール',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'マーケット'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定'),
          BottomNavigationBarItem(
            icon: Icon(Icons.pie_chart),
            label: 'ポートフォリオ',
          ),
        ],
      ),
    );
  }
}
