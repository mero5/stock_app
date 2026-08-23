// ============================================================
// SettingsScreen
// 設定画面。現在は投資プロファイルの確認・編集のみ担当する。
//
// 表示する情報：
// ・投資プロファイル（投資期間・取引種別・リスク許容度等）
//
// 遷移先：
// ・ProfileSetupScreen（プロファイル編集）
// ============================================================

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import 'profile_setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ============================================================
  // 状態変数
  // ============================================================

  /// ログイン中のユーザーID（Cognito sub）
  String? _userId;

  /// 取得したユーザープロファイル
  /// 未設定の場合はnull
  Map<String, dynamic>? _profile;

  /// データ取得中フラグ
  bool _isLoading = true;

  // ============================================================
  // ライフサイクル
  // ============================================================

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ============================================================
  // データ取得
  // ============================================================

  /// ユーザーIDとプロファイルをバックエンドから取得する
  ///
  /// ProfileSetupScreenから戻ってきた後にも呼ばれ、
  /// 最新のプロファイルを再取得して画面を更新する。
  Future<void> _load() async {
    final userId = await AuthService.getUserId();
    if (userId == null) return;

    final profile = await UserProfileService.getProfile(userId);

    setState(() {
      _userId = userId;
      _profile = profile;
      _isLoading = false;
    });
  }

  // ============================================================
  // build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_buildProfileCard()],
              ),
            ),
    );
  }

  // ============================================================
  // UIパーツ
  // ============================================================

  /// 投資プロファイルカードを構築する
  ///
  /// プロファイルが未設定の場合は「未設定」と表示する。
  /// 「編集」ボタンでProfileSetupScreenに遷移し、
  /// 戻ってきたら最新のプロファイルを再取得する。
  Widget _buildProfileCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー（タイトル＋編集ボタン）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '投資プロファイル',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                TextButton(
                  onPressed: () async {
                    if (_userId == null) return;

                    // ProfileSetupScreenに遷移（編集モード）
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileSetupScreen(
                          userId: _userId!,
                          isInitial: false, // 編集モード（初回設定ではない）
                        ),
                      ),
                    );

                    // 戻ってきたら最新のプロファイルを再取得
                    _load();
                  },
                  child: const Text('編集'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // プロファイル内容
            if (_profile == null)
              // 未設定の場合
              const Text('未設定', style: TextStyle(color: Colors.grey))
            else ...[
              // 設定済みの場合は各項目を表示
              _profileRow('投資期間', _profile!['investment_style']),
              _profileRow('取引種別', _profile!['trade_type']),
              _profileRow('空売り', _profile!['short_selling']),
              _profileRow('分析スタイル', _profile!['analysis_style']),
              _profileRow('リスク許容度', _profile!['risk_level']),
              _profileRow('投資経験', _profile!['experience']),
              _profileRow('投資対象', _profile!['market']),
              _profileRow('分散方針', _profile!['concentration']),
              const SizedBox(height: 4),
              _profileRow('分析期間の目安', _periodDaysSummary()),
              _profileRow('優先順位（短期）', _prioritySummary('priority_short')),
              _profileRow('優先順位（中期）', _prioritySummary('priority_medium')),
              _profileRow('優先順位（長期）', _prioritySummary('priority_long')),
            ],
          ],
        ),
      ),
    );
  }

  /// プロファイルの1行（ラベル＋値）を構築する
  ///
  /// [label] 項目名（例：「投資期間」「リスク許容度」）
  /// [value] 項目の値（nullの場合は「未設定」と表示）
  Widget _profileRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          // ラベル（固定幅で右揃え）
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          // 値
          Text(
            value?.toString() ?? '未設定',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  /// AI分析の期間日数設定を要約して返す（例：「〜14日 / 15〜90日 / 91日〜」）
  ///
  /// プロファイル未設定の場合はデフォルト（短期14日・中期90日）を表示する。
  String _periodDaysSummary() {
    final shortMax =
        (_profile?['period_short_max_days'] as num?)?.toInt() ?? 14;
    final mediumMax =
        (_profile?['period_medium_max_days'] as num?)?.toInt() ?? 90;
    return '〜$shortMax日 / ${shortMax + 1}〜$mediumMax日 / ${mediumMax + 1}日〜';
  }

  /// AI分析の優先順位（上位3項目）をラベルで要約して返す
  ///
  /// [profileKey] 'priority_short' / 'priority_medium' / 'priority_long'
  /// 未設定の場合は「未設定」と表示する。
  /// kPriorityLabelsはprofile_setup_screen.dartで定義されている。
  String _prioritySummary(String profileKey) {
    final list = (_profile?[profileKey] as List?)?.cast<String>();
    if (list == null || list.isEmpty) return '未設定';
    return list.take(3).map((k) => kPriorityLabels[k] ?? k).join(' > ');
  }
}
