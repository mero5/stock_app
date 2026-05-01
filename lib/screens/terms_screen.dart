// ============================================================
// TermsScreen
// 利用規約・免責事項の同意画面。
//
// 初回ログイン後に表示され、全項目にチェックを入れると
// HomeScreenに遷移できる。
//
// 同意状態はSharedPreferencesに保存し、
// 次回起動時はこの画面をスキップする。
//
// 同意が必要な項目（6項目）：
// ・investment : 投資は自己責任
// ・accuracy   : データに誤りが含まれる場合がある
// ・ai         : AI分析は参考情報
// ・holiday    : 株価データの遅延・乖離がある
// ・service    : サービスが予告なく変更・停止される場合がある
// ・data       : データ管理・プライバシー
// ============================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  // ============================================================
  // 状態変数
  // ============================================================

  /// 各規約項目のチェック状態
  /// key: 項目ID、value: チェック済みかどうか
  final Map<String, bool> _checks = {
    'investment': false, // 投資は自己責任
    'accuracy': false, // データの誤り
    'ai': false, // AI分析は参考情報
    'holiday': false, // 株価データの遅延
    'service': false, // サービス変更・停止
    'data': false, // プライバシー
  };

  /// 同意ボタン押下後のローディングフラグ
  bool _isLoading = false;

  // ============================================================
  // 算出プロパティ
  // ============================================================

  /// 全項目がチェックされているかどうか
  /// 同意ボタンの活性・非活性制御に使用する
  bool get _allChecked => _checks.values.every((v) => v);

  /// チェック済みの項目数
  int get _checkedCount => _checks.values.where((v) => v).length;

  // ============================================================
  // アクション
  // ============================================================

  /// 全項目に同意してHomeScreenへ遷移する
  ///
  /// SharedPreferencesに同意済みフラグを保存することで
  /// 次回起動時にこの画面をスキップする。
  Future<void> _agree() async {
    if (!_allChecked) return;

    setState(() => _isLoading = true);

    // 同意済みフラグをSharedPreferencesに保存
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('terms_agreed', true);

    if (mounted) {
      // HomeScreenに遷移（戻れないようにpushReplacementを使う）
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  // ============================================================
  // build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('利用規約・免責事項'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        // 戻るボタンを非表示にする（同意前に戻れないようにする）
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // 規約項目一覧（スクロール可能）
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ヘッダー
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

                  // 規約項目（タップでチェック）
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
                    key: 'data',
                    icon: Icons.cloud,
                    color: Colors.teal,
                    title: 'データ管理・プライバシーについて理解しました',
                    body:
                        '本アプリでは、ログイン情報およびユーザーデータをAWS CognitoおよびDynamoDBなどのクラウドサービスを用いて安全に管理しています。パスワードは暗号化されて保存され、本アプリが直接参照することはありません。ユーザーの登録情報（メールアドレス・お気に入り銘柄等）は、システムの運用・保守・不具合対応の目的に限り、運営者がアクセスする場合があります。これらの情報は、法令に基づく場合を除き、ユーザーの同意なく第三者へ提供・公開されることはありません。',
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // 同意ボタンエリア（画面下部に固定）
          _buildAgreementFooter(),
        ],
      ),
    );
  }

  // ============================================================
  // UIパーツ
  // ============================================================

  /// 画面下部の同意ボタンエリアを構築する
  ///
  /// 進捗バー・チェック数・同意ボタンを表示する。
  /// 全項目チェック済みの場合のみ同意ボタンが活性化する。
  Widget _buildAgreementFooter() {
    return Container(
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
          // チェック進捗テキスト
          Text(
            '$_checkedCount / ${_checks.length} 確認済み',
            style: TextStyle(
              fontSize: 12,
              color: _allChecked ? Colors.blue : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // チェック進捗バー
          LinearProgressIndicator(
            value: _checkedCount / _checks.length,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              _allChecked ? Colors.blue : Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 12),

          // 同意ボタン（全項目チェック済みで活性化）
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
                  // 処理中はローディングスピナーを表示
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
    );
  }

  /// 規約項目カードを構築する
  ///
  /// タップするとチェック状態が切り替わる。
  /// チェック済みの場合はボーダーと背景色が変わる。
  ///
  /// [key]   項目のID（_checksのキーと対応）
  /// [icon]  項目のアイコン
  /// [color] 項目のテーマカラー
  /// [title] 項目のタイトル
  /// [body]  項目の詳細説明文
  Widget _termItem({
    required String key,
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    final checked = _checks[key] ?? false;

    return GestureDetector(
      // タップでチェック状態を切り替え
      onTap: () => setState(() => _checks[key] = !checked),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            // チェック済みはテーマカラー・未チェックはグレー
            color: checked ? color : Colors.grey.shade300,
            width: checked ? 2 : 1,
          ),
          // チェック済みはテーマカラーの薄い背景
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

              // タイトルと説明文
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        // チェック済みはテーマカラー・未チェックは黒
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

              // チェックアイコン（チェック済みで塗りつぶし）
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
