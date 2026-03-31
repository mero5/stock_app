import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'amplifyconfiguration.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> saveFavorites(List<String> stocks) async {
  final user = await Amplify.Auth.getCurrentUser();

  final url =
      "https://b5srqu1twf.execute-api.ap-northeast-1.amazonaws.com/save";

  final body = {"userId": user.userId, "stocks": stocks};

  print("=== 送信URL ===");
  print(url);

  print("=== 送信BODY ===");
  print(body);

  final response = await http.post(
    Uri.parse(url),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode(body),
  );

  print("=== レスポンス ===");
  print(response.body);
}

Future<List<String>> getFavorites() async {
  final user = await Amplify.Auth.getCurrentUser();

  final response = await http.get(
    Uri.parse(
      "https://3nbvb44ku4.execute-api.ap-northeast-1.amazonaws.com/get?userId=${user.userId}",
    ),
  );

  print("ユーザーID: ${user.userId}");
  print("レスポンス生データ: ${response.body}");

  final data = jsonDecode(response.body);

  return data.map<String>((item) => item['stock'].toString()).toList();
}

void main() {
  runApp(const StockApp());
}

class StockApp extends StatelessWidget {
  const StockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: LoginPage());
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isAmplifyConfigured = false;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _configureAmplify();
    await _checkLogin();
  }

  Future<void> _configureAmplify() async {
    try {
      if (!Amplify.isConfigured) {
        await Amplify.addPlugin(AmplifyAuthCognito());
        await Amplify.configure(amplifyconfig);
      }
      setState(() {
        _isAmplifyConfigured = true;
      });
    } catch (e) {
      print("Amplify設定エラー: $e");
    }
  }

  Future<void> _checkLogin() async {
    final session = await Amplify.Auth.fetchAuthSession();
    if (session.isSignedIn) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    }
  }

  // サインアップ
  Future<void> signUp() async {
    try {
      final res = await Amplify.Auth.signUp(
        username: emailController.text,
        password: passwordController.text,
        options: SignUpOptions(
          userAttributes: {AuthUserAttributeKey.email: emailController.text},
        ),
      );

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("登録完了: $res")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("登録エラー: $e")));
    }
  }

  // ⭐ 修正版ログイン
  Future<void> signIn() async {
    try {
      final res = await Amplify.Auth.signIn(
        username: emailController.text,
        password: passwordController.text,
      );

      print("ログイン結果: $res");

      // 成功
      if (res.isSignedIn) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("ログイン成功")));

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
        return;
      }

      // ⭐ 未完了の場合（ここ重要）
      final nextStep = res.nextStep.signInStep;

      if (nextStep == AuthSignInStep.confirmSignInWithNewPassword) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("初回ログイン：パスワード変更が必要")));

        // 仮対応：同じパスワードで確定
        await Amplify.Auth.confirmSignIn(
          confirmationValue: passwordController.text,
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("ログイン未完了: $nextStep")));
      }
    } catch (e) {
      print("ログインエラー: $e");

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("株アプリ", style: TextStyle(fontSize: 24)),
              const SizedBox(height: 20),

              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: "メールアドレス",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "パスワード",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _isAmplifyConfigured ? signIn : null,
                child: const Text("ログイン"),
              ),

              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: _isAmplifyConfigured ? signUp : null,
                child: const Text("新規登録"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  List<String> watchList = [];

  // 画面リスト
  List<Widget> _pages() => [
    // ① ホーム（一覧）
    ListView.builder(
      itemCount: watchList.length,
      itemBuilder: (context, index) {
        return ListTile(title: Text(watchList[index]));
      },
    ),

    // ② 銘柄追加
    AddStockPage(
      watchList: watchList,
      onAdd: (value) async {
        await loadFavorites();
        setState(() {
          watchList.addAll(value);
          _currentIndex = 0; // 追加後ホームへ戻る
        });
      },
    ),

    // ③ ログアウト画面
    Center(
      child: ElevatedButton(
        onPressed: () async {
          await Amplify.Auth.signOut();

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        },
        child: const Text("ログアウト"),
      ),
    ),
  ];

  @override
  void initState() {
    super.initState();
    loadFavorites();
  }

  Future<void> loadFavorites() async {
    final list = await getFavorites();

    print("取得データ: $list");

    setState(() {
      watchList = list;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("株アプリ")),

      body: _pages()[_currentIndex],

      // ⭐ フッター
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) async {
          if (index == 0) {
            await loadFavorites(); // ⭐ ホーム押したらDB再取得
          }
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "ホーム"),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: "追加"),
          BottomNavigationBarItem(icon: Icon(Icons.logout), label: "ログアウト"),
        ],
      ),
    );
  }
}

// ⭐ 銘柄追加画面（少し改造）
class AddStockPage extends StatefulWidget {
  final Function(List<String>) onAdd;
  final List<String> watchList;

  const AddStockPage({super.key, required this.onAdd, required this.watchList});

  @override
  State<AddStockPage> createState() => _AddStockPageState();
}

class _AddStockPageState extends State<AddStockPage> {
  final controller = TextEditingController();

  final List<String> allStocks = [
    "トヨタ 7203",
    "ソニー 6758",
    "任天堂 7974",
    "ソフトバンク 9984",
    "キーエンス 6861",
  ];

  List<String> filteredStocks = [];
  List<String> selectedStocks = [];

  void search(String keyword) {
    if (keyword.isEmpty) {
      setState(() {
        filteredStocks = []; // ⭐ 空なら何も出さない
      });
      return;
    }

    setState(() {
      filteredStocks = allStocks
          .where((stock) => stock.contains(keyword))
          .toList();
    });
  }

  void toggleSelect(String stock) {
    // ⭐ すでに登録済みは無視
    if (widget.watchList.contains(stock)) return;

    setState(() {
      if (selectedStocks.contains(stock)) {
        selectedStocks.remove(stock);
      } else {
        selectedStocks.add(stock);
      }
    });
  }

  void handleAdd() async {
    await saveFavorites(selectedStocks); // ⭐ ここでAPIに保存
    widget.onAdd(selectedStocks);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(
            controller: controller,
            onChanged: search,
            decoration: const InputDecoration(
              labelText: "銘柄名 or コード",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: ListView.builder(
              itemCount: filteredStocks.length,
              itemBuilder: (context, index) {
                final stock = filteredStocks[index];

                final isSelected = selectedStocks.contains(stock);
                final isAlreadyAdded = widget.watchList.contains(stock);

                return ListTile(
                  title: Text(stock),

                  // ⭐ 状態分岐
                  trailing: Icon(
                    isAlreadyAdded
                        ? Icons
                              .check_box // 既に登録済み
                        : isSelected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                  ),

                  // ⭐ 登録済みは押せない
                  onTap: isAlreadyAdded ? null : () => toggleSelect(stock),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          ElevatedButton(
            onPressed: selectedStocks.isNotEmpty ? handleAdd : null,
            child: const Text("追加"),
          ),
        ],
      ),
    );
  }
}
