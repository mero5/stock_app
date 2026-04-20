import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  // 各項目のチェック状態
  final Map<String, bool> _checks = {
    'investment': false,
    'accuracy': false,
    'ai': false,
    'holiday': false,
    'service': false,
    'privacy': false,
  };
  bool _isLoading = false;

  // 全部チェックされているか
  bool get _allChecked => _checks.values.every((v) => v);

  Future<void> _agree() async {
    if (!_allChecked) return;
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('terms_agreed', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('利用規約・免責事項'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Icon(Icons.gavel, size: 48, color: Colors.blue),
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'ご利用前にお読みください',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                      '各項目をお読みの上、チェックしてください',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 24),

                  _termItem(
                    key: 'investment',
                    icon: Icons.account_balance,
                    color: Colors.blue,
                    title: '投資は自己責任で行います',
                    body:
                        '本アプリが提供する株価情報・AI分析・相談結果はあくまで参考情報です。実際の投資判断はご自身の責任で行ってください。本アプリの情報を基にした投資による損失について、一切の責任を負いません。',
                  ),
                  _termItem(
                    key: 'accuracy',
                    icon: Icons.warning_amber,
                    color: Colors.orange,
                    title: 'データに誤りが含まれる場合があることを理解しました',
                    body:
                        '株価・財務データ・ニュースは外部API（yfinance・J-Quants等）から取得しており、データの遅延・誤り・欠損が含まれる場合があります。',
                  ),
                  _termItem(
                    key: 'ai',
                    icon: Icons.smart_toy,
                    color: Colors.purple,
                    title: 'AI分析は参考情報であることを理解しました',
                    body:
                        'AIによる分析・スコア・アドバイスは必ずしも正確ではありません。将来の株価や市場動向を保証するものではありません。AIの回答を投資判断の唯一の根拠にしないでください。',
                  ),
                  _termItem(
                    key: 'holiday',
                    icon: Icons.calendar_today,
                    color: Colors.teal,
                    title: '株価データの遅延および乖離があることを理解しました',
                    body:
                        '株価データはyfinanceを通じたYahoo Financeのデータで、約15〜20分の遅延があります。東証の取引時間（平日：前場9:00〜11:30・後場12:30〜15:30）外や土日・祝日・年末年始は前回終値が表示されます。取引開始前（9:00以前）および取引直後の時間帯においては、当日の株価が反映されず、前日の終値等が表示される場合があります。',
                  ),
                  _termItem(
                    key: 'service',
                    icon: Icons.build,
                    color: Colors.grey,
                    title: 'サービスが予告なく変更・停止される場合があることを理解しました',
                    body:
                        '本アプリは個人が開発した非公式の投資情報アプリです。金融商品取引業者ではありません。予告なくサービス内容の変更・停止を行う場合があります。',
                  ),
                  _termItem(
                    key: 'privacy',
                    icon: Icons.lock,
                    color: Colors.indigo,
                    title: 'ログイン情報・データの管理方法を理解しました',
                    body:
                        'ログイン情報はAWS Cognitoで安全に管理されます。パスワードは暗号化されて保存され、本アプリが直接パスワードを参照することはありません。ウォッチリスト等のデータはAWS DynamoDBに保存されます。',
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // 同意ボタン
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // 進捗表示
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${_checks.values.where((v) => v).length} / ${_checks.length} 確認済み',
                      style: TextStyle(
                        fontSize: 12,
                        color: _allChecked ? Colors.blue : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _checks.values.where((v) => v).length / _checks.length,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _allChecked ? Colors.blue : Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 12),

                // ボタン
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _allChecked && !_isLoading ? _agree : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade500,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _allChecked ? '同意してアプリを始める' : '全ての項目を確認してください',
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
    );
  }

  Widget _termItem({
    required String key,
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    final checked = _checks[key] ?? false;
    return GestureDetector(
      onTap: () => setState(() => _checks[key] = !checked),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: checked ? color : Colors.grey.shade300,
            width: checked ? 2 : 1,
          ),
          color: checked ? color.withOpacity(0.05) : Colors.white,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // アイコン
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),

              // テキスト
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: checked ? color : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // チェックボックス
              Icon(
                checked ? Icons.check_circle : Icons.circle_outlined,
                color: checked ? color : Colors.grey.shade300,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
