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
}
