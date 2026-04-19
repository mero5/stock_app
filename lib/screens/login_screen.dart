import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final codeController = TextEditingController();

  // 確認コード入力モードかどうか
  bool _showConfirmation = false;

  Future<void> signUp() async {
    try {
      await AuthService.signUp(emailController.text, passwordController.text);
      // 登録成功 → 確認コード入力画面に切り替え
      setState(() => _showConfirmation = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("確認コードをメールに送りました")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("登録エラー: $e")));
    }
  }

  Future<void> confirmSignUp() async {
    try {
      await Amplify.Auth.confirmSignUp(
        username: emailController.text,
        confirmationCode: codeController.text,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("認証完了！ログインしてください")));
      setState(() => _showConfirmation = false);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("認証エラー: $e")));
    }
  }

  Future<void> signIn() async {
    try {
      final success = await AuthService.signIn(
        emailController.text,
        passwordController.text,
      );
      if (success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("ログインエラー: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ログイン")),
      body: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(20),
          child: _showConfirmation
              ? _buildConfirmationForm()
              : _buildLoginForm(),
        ),
      ),
    );
  }

  // 通常のログイン・新規登録フォーム
  Widget _buildLoginForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text("株アプリ", style: TextStyle(fontSize: 24)),
        const SizedBox(height: 20),
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: "メールアドレス",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: passwordController,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(
            labelText: "パスワード",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(onPressed: signIn, child: const Text("ログイン")),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(onPressed: signUp, child: const Text("新規登録")),
        ),
      ],
    );
  }

  // 確認コード入力フォーム
  Widget _buildConfirmationForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mark_email_unread, size: 60, color: Colors.blue),
        const SizedBox(height: 16),
        const Text(
          "確認コードを入力",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          "${emailController.text} に送信された6桁のコードを入力してください",
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: const InputDecoration(
            labelText: "確認コード（6桁）",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: confirmSignUp,
            child: const Text("認証する"),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() => _showConfirmation = false),
          child: const Text("戻る"),
        ),
      ],
    );
  }
}
