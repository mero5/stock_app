// ============================================================
// main.dart
// アプリのエントリーポイント。
//
// ProviderはViewModelをWidget全体で共有するための仕組み。
// MultiProviderで複数のViewModelを一括登録することで、
// どの画面からでもViewModelにアクセスできる。
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'amplifyconfiguration.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'viewmodels/home_viewmodel.dart';
import 'viewmodels/portfolio_viewmodel.dart';
import '../theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureAmplify();
  runApp(const MyApp());
}

/// Amplify（AWS Cognito認証）の初期化
Future<void> _configureAmplify() async {
  try {
    final authPlugin = AmplifyAuthCognito();
    await Amplify.addPlugin(authPlugin);
    await Amplify.configure(amplifyconfig);
  } catch (e) {
    debugPrint('Amplify設定エラー: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ホーム画面のViewModel
        // HomeScreenとその子Widgetからアクセス可能
        ChangeNotifierProvider(create: (_) => HomeViewModel()),

        // ポートフォリオ診断画面のViewModel
        ChangeNotifierProvider(create: (_) => PortfolioViewModel()),
      ],
      child: MaterialApp(
        title: '株アプリ',
        theme: AppTheme.themeData,
        home: const AuthWrapper(),
      ),
    );
  }
}

/// ログイン状態に応じて表示画面を切り替えるWidget
/// ログイン済み → HomeScreen
/// 未ログイン   → LoginScreen
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoggedIn = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  /// Cognitoのセッションを確認してログイン状態を判定する
  Future<void> _checkAuthStatus() async {
    try {
      final result = await Amplify.Auth.fetchAuthSession();
      setState(() {
        _isLoggedIn = result.isSignedIn;
        _isChecking = false;
      });
    } catch (e) {
      setState(() {
        _isLoggedIn = false;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 確認中はローディング表示
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return _isLoggedIn ? const HomeScreen() : const LoginScreen();
  }
}
