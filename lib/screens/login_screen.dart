import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'terms_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'onboarding_screen.dart';
import 'profile_setup_screen.dart';
import '../services/user_profile_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final codeController = TextEditingController();

  bool _showConfirmation = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  // ── Cognitoエラーを日本語に変換 ──
  String _translateError(dynamic e) {
    final msg = e.toString().toLowerCase();

    if (msg.contains('usernameexistsexception') ||
        msg.contains('user already exists')) {
      return 'このメールアドレスはすでに登録されています。';
    }
    if (msg.contains('usernotconfirmedexception')) {
      return 'メールアドレスの確認が完了していません。\n確認コードを入力してください。';
    }
    if (msg.contains('notauthorizedexception') ||
        msg.contains('incorrect username or password')) {
      return 'メールアドレスまたはパスワードが正しくありません。';
    }
    if (msg.contains('usernotfoundexception') ||
        msg.contains('user does not exist')) {
      return 'このメールアドレスは登録されていません。';
    }
    if (msg.contains('invalidpasswordexception') ||
        msg.contains('password did not conform')) {
      return 'パスワードの形式が正しくありません。\n8文字以上・大文字・小文字・数字・記号をそれぞれ1つ以上含めてください。';
    }
    if (msg.contains('invalidparameterexception') ||
        msg.contains('invalid email')) {
      return 'メールアドレスの形式が正しくありません。';
    }
    if (msg.contains('codemismatchexception') ||
        msg.contains('invalid verification code')) {
      return '確認コードが正しくありません。もう一度確認してください。';
    }
    if (msg.contains('expiredcodeexception') ||
        msg.contains('code has expired')) {
      return '確認コードの有効期限が切れています。\n新しいコードを再送してください。';
    }
    if (msg.contains('limitexceededexception') ||
        msg.contains('attempt limit exceeded')) {
      return 'しばらく時間をおいてから再度お試しください。';
    }
    if (msg.contains('networkerror') ||
        msg.contains('connection') ||
        msg.contains('socket')) {
      return 'ネットワークエラーが発生しました。\nインターネット接続を確認してください。';
    }
    if (msg.contains('toomanyrequestsexception')) {
      return 'リクエストが多すぎます。しばらく時間をおいてから再度お試しください。';
    }
    return '予期しないエラーが発生しました。\nしばらく時間をおいてから再度お試しください。';
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('エラー', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> signUp() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      _showError('メールアドレスとパスワードを入力してください。');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await AuthService.signUp(
        emailController.text.trim(),
        passwordController.text,
      );
      setState(() => _showConfirmation = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('確認コードをメールに送りました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError(_translateError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> confirmSignUp() async {
    if (codeController.text.isEmpty) {
      _showError('確認コードを入力してください。');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await Amplify.Auth.confirmSignUp(
        username: emailController.text.trim(),
        confirmationCode: codeController.text.trim(),
      );
      setState(() => _showConfirmation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('認証完了！ログインしてください'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError(_translateError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> signIn() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      _showError('メールアドレスとパスワードを入力してください。');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final success = await AuthService.signIn(
        emailController.text.trim(),
        passwordController.text,
      );
      if (success && mounted) {
        final prefs = await SharedPreferences.getInstance();
        final agreed = prefs.getBool('terms_agreed') ?? false;
        if (!agreed) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
          );
          return;
        }
        // プロファイル確認
        final userId = await AuthService.getUserId();
        if (!mounted) return;
        final profile = await UserProfileService.getProfile(userId!);
        if (!mounted) return;
        if (profile == null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileSetupScreen(userId: userId),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else if (mounted) {
        _showError('ログインに失敗しました。メールアドレスとパスワードを確認してください。');
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      // 未確認の場合は確認コード画面に遷移
      if (msg.contains('usernotconfirmedexception')) {
        setState(() => _showConfirmation = true);
        _showError('メールアドレスの確認が完了していません。\n確認コードを入力してください。');
      } else {
        _showError(_translateError(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    try {
      await Amplify.Auth.resendSignUpCode(
        username: emailController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('確認コードを再送しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError(_translateError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _showConfirmation
                ? _buildConfirmationForm()
                : _buildLoginForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ロゴ・タイトル
        const Center(
          child: Column(
            children: [
              Icon(Icons.show_chart, size: 56, color: Colors.blue),
              SizedBox(height: 8),
              Text(
                '株アプリ',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                '投資情報をシンプルに',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // 注意書き
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '新規登録の際は、実在するメールアドレスを入力してください。確認コードをメールに送信します。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // メールアドレス
        const Text(
          'メールアドレス',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        AutofillGroup(
          child: Column(
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  hintText: 'example@email.com',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),

              // パスワード
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'パスワード',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: passwordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                onEditingComplete: () => TextInput.finishAutofillContext(),
                decoration: InputDecoration(
                  hintText: '8文字以上・大文字・小文字・数字・記号を含む',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
            ],
          ),
        ),

        // パスワード要件
        const SizedBox(height: 8),
        const Text(
          '※ 大文字・小文字・数字・記号（!@#\$など）をそれぞれ1つ以上含む8文字以上',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 24),

        // ログインボタン
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : signIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
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
                : const Text(
                    'ログイン',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        const SizedBox(height: 12),

        // 新規登録ボタン
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _isLoading ? null : signUp,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('新規登録', style: TextStyle(fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmationForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mark_email_unread, size: 64, color: Colors.blue),
        const SizedBox(height: 16),
        const Text(
          '確認コードを入力',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '${emailController.text}\nに6桁の確認コードを送信しました',
          style: const TextStyle(fontSize: 13, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        TextField(
          controller: codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, letterSpacing: 10),
          maxLength: 6,
          decoration: InputDecoration(
            hintText: '000000',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: Colors.grey.shade50,
            counterText: '',
          ),
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : confirmSignUp,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
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
                : const Text(
                    '認証する',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        const SizedBox(height: 12),

        // コード再送
        TextButton.icon(
          onPressed: _resendCode,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('確認コードを再送する'),
        ),
        TextButton(
          onPressed: () => setState(() => _showConfirmation = false),
          child: const Text('戻る', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}
