import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'profile_setup_screen.dart';
import '../services/user_profile_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _userId;
  Map<String, dynamic>? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
                children: [
                  // プロファイルカード
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '投資プロファイル',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  if (_userId == null) return;
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ProfileSetupScreen(
                                        userId: _userId!,
                                        isInitial: false,
                                      ),
                                    ),
                                  );
                                  _load();
                                },
                                child: const Text('編集'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_profile == null)
                            const Text(
                              '未設定',
                              style: TextStyle(color: Colors.grey),
                            )
                          else ...[
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
                  ),
                ],
              ),
            ),
    );
  }

  Widget _profileRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          Text(
            value?.toString() ?? '未設定',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
