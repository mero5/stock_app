import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'amplifyconfiguration.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

const backendUrl = "http://13.114.75.49:8000";

Future<void> saveFavorites(List<String> stocks) async {
  final user = await Amplify.Auth.getCurrentUser();
  final url =
      "https://b5srqu1twf.execute-api.ap-northeast-1.amazonaws.com/save";
  final body = {"userId": user.userId, "stocks": stocks};
  await http.post(
    Uri.parse(url),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode(body),
  );
}

Future<void> deleteFavorite(String stock) async {
  final user = await Amplify.Auth.getCurrentUser();
  final url =
      "https://b5srqu1twf.execute-api.ap-northeast-1.amazonaws.com/delete";
  final response = await http.delete(
    Uri.parse(url),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({"userId": user.userId, "stock": stock}),
  );
  print("削除レスポンス: ${response.body}");
}

Future<List<Map<String, String>>> getFavorites() async {
  final user = await Amplify.Auth.getCurrentUser();
  final response = await http.get(
    Uri.parse(
      "https://3nbvb44ku4.execute-api.ap-northeast-1.amazonaws.com/get?userId=${user.userId}",
    ),
  );
  final data = jsonDecode(response.body);
  final codes = data.map<String>((item) => item['stock'].toString()).toList();

  List<Map<String, String>> result = [];
  for (final code in codes) {
    try {
      final nameRes = await http.get(
        Uri.parse("$backendUrl/stock/name?code=${Uri.encodeComponent(code)}"),
      );
      final nameData = jsonDecode(nameRes.body);
      result.add({"code": code, "name": nameData["name"].toString()});
    } catch (e) {
      result.add({"code": code, "name": code});
    }
  }
  return result;
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
      setState(() => _isAmplifyConfigured = true);
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

  Future<void> signIn() async {
    try {
      final res = await Amplify.Auth.signIn(
        username: emailController.text,
        password: passwordController.text,
      );
      if (res.isSignedIn) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
        return;
      }
      final nextStep = res.nextStep.signInStep;
      if (nextStep == AuthSignInStep.confirmSignInWithNewPassword) {
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
  List<Map<String, String>> watchList = [];
  bool _editMode = false;
  List<String> _selectedCodes = [];

  @override
  void initState() {
    super.initState();
    loadFavorites();
  }

  Future<void> loadFavorites() async {
    try {
      final list = await getFavorites();
      setState(() => watchList = list);
    } catch (e) {
      print("お気に入り取得エラー: $e");
    }
  }

  void _toggleEditMode() {
    setState(() {
      _editMode = !_editMode;
      _selectedCodes = [];
    });
  }

  void _toggleSelect(String code) {
    setState(() {
      if (_selectedCodes.contains(code)) {
        _selectedCodes.remove(code);
      } else {
        _selectedCodes.add(code);
      }
    });
  }

  Future<void> _deleteSelected() async {
    for (final code in _selectedCodes) {
      await deleteFavorite(code);
    }
    await loadFavorites();
    setState(() {
      _editMode = false;
      _selectedCodes = [];
    });
  }

  Widget _buildHomeTab() {
    if (watchList.isEmpty) {
      return const Center(child: Text("銘柄を追加してください"));
    }
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: watchList.length,
            itemBuilder: (context, index) {
              final stock = watchList[index];
              final code = stock["code"]!;
              final name = stock["name"] ?? code;
              final isSelected = _selectedCodes.contains(code);

              return ListTile(
                leading: _editMode
                    ? Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleSelect(code),
                      )
                    : const Icon(Icons.show_chart),
                title: Text(name),
                subtitle: Text(code),
                trailing: _editMode ? null : const Icon(Icons.chevron_right),
                onTap: _editMode
                    ? () => _toggleSelect(code)
                    : () {
                        // 詳細画面へ（後で実装）
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("$name の詳細（実装予定）")),
                        );
                      },
              );
            },
          ),
        ),
        if (_editMode && _selectedCodes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _deleteSelected,
                icon: const Icon(Icons.delete),
                label: Text("${_selectedCodes.length}件削除"),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("株アプリ"),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              icon: Icon(_editMode ? Icons.check : Icons.edit),
              onPressed: _toggleEditMode,
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          AddStockPage(
            watchList: watchList,
            onAdd: (codes) async {
              await loadFavorites();
              setState(() => _currentIndex = 0);
            },
          ),
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
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) async {
          if (index == 0) await loadFavorites();
          setState(() {
            _currentIndex = index;
            _editMode = false;
            _selectedCodes = [];
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

class AddStockPage extends StatefulWidget {
  final Function(List<String>) onAdd;
  final List<Map<String, String>> watchList;

  const AddStockPage({super.key, required this.onAdd, required this.watchList});

  @override
  State<AddStockPage> createState() => _AddStockPageState();
}

class _AddStockPageState extends State<AddStockPage> {
  final controller = TextEditingController();
  List<Map<String, String>> filteredStocks = [];
  List<Map<String, String>> selectedStocks = [];
  bool isLoading = false;

  Future<void> search(String keyword) async {
    if (keyword.isEmpty) {
      setState(() => filteredStocks = []);
      return;
    }
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        Uri.parse("$backendUrl/search?q=${Uri.encodeComponent(keyword)}"),
      );
      final List data = jsonDecode(res.body);
      setState(() {
        filteredStocks = data
            .map<Map<String, String>>(
              (e) => {
                "code": e["code"].toString(),
                "name": e["name"].toString(),
                "market": e["market"].toString(),
              },
            )
            .toList();
      });
    } catch (e) {
      print("検索エラー: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  void toggleSelect(Map<String, String> stock) {
    final code = stock["code"]!;
    if (widget.watchList.any((s) => s["code"] == code)) return;
    setState(() {
      final idx = selectedStocks.indexWhere((s) => s["code"] == code);
      if (idx >= 0) {
        selectedStocks.removeAt(idx);
      } else {
        selectedStocks.add(stock);
      }
    });
  }

  void handleAdd() async {
    final codes = selectedStocks.map((s) => s["code"]!).toList();
    await saveFavorites(codes);
    widget.onAdd(codes);
    setState(() {
      selectedStocks = [];
      filteredStocks = [];
      controller.clear();
    });
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
              labelText: "銘柄名 or コード（例: トヨタ, 7203, AAPL）",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          if (isLoading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: filteredStocks.length,
              itemBuilder: (context, index) {
                final stock = filteredStocks[index];
                final code = stock["code"]!;
                final name = stock["name"]!;
                final market = stock["market"]!;
                final isSelected = selectedStocks.any((s) => s["code"] == code);
                final isAlreadyAdded = widget.watchList.any(
                  (s) => s["code"] == code,
                );

                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: market == "JP"
                          ? Colors.red.shade100
                          : Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      market,
                      style: TextStyle(
                        color: market == "JP"
                            ? Colors.red.shade800
                            : Colors.blue.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text(code),
                  trailing: Icon(
                    isAlreadyAdded || isSelected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color: isAlreadyAdded ? Colors.grey : Colors.blue,
                  ),
                  onTap: isAlreadyAdded ? null : () => toggleSelect(stock),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          if (selectedStocks.isNotEmpty)
            Text(
              "${selectedStocks.length}件選択中",
              style: const TextStyle(color: Colors.blue),
            ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            onPressed: selectedStocks.isNotEmpty ? handleAdd : null,
            icon: const Icon(Icons.add),
            label: const Text("ウォッチリストに追加"),
          ),
        ],
      ),
    );
  }
}
