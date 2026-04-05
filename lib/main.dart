import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'amplifyconfiguration.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:candlesticks_plus/candlesticks_plus.dart';
import 'package:candlesticks_plus/src/models/candle_style.dart';

const backendUrl = "http://13.114.75.49:8000";

String formatNumber(dynamic value, {int decimals = 0}) {
  if (value == null) return "---";
  final num v = value is num ? value : num.parse(value.toString());
  final parts = v.toStringAsFixed(decimals).split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return decimals > 0 ? '$intPart.${parts[1]}' : intPart;
}

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

      String price = "---";
      String change = "";
      String changePct = "";
      bool isPositive = true;

      try {
        final priceRes = await http.get(
          Uri.parse(
            "$backendUrl/stock/price?code=${Uri.encodeComponent(code)}",
          ),
        );
        final priceData = jsonDecode(priceRes.body);
        if (priceData['price'] != null) {
          price = (priceData['price'] as num).toStringAsFixed(0);
        }
        if (priceData['change'] != null) {
          final c = priceData['change'] as num;
          final cp = priceData['change_pct'] as num;
          isPositive = c >= 0;
          change = c >= 0 ? "+${c.toStringAsFixed(1)}" : c.toStringAsFixed(1);
          changePct = cp >= 0
              ? "+${cp.toStringAsFixed(2)}%"
              : "${cp.toStringAsFixed(2)}%";
        }
      } catch (_) {}

      result.add({
        "code": code,
        "name": nameData["name"].toString(),
        "price": price,
        "change": change,
        "change_pct": changePct,
        "is_positive": isPositive ? "true" : "false",
      });
    } catch (e) {
      result.add({"code": code, "name": code, "price": "---"});
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
                trailing: _editMode
                    ? null
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            stock["price"] != null && stock["price"] != "---"
                                ? "¥${formatNumber(int.tryParse(stock["price"]!) ?? 0)}"
                                : "---",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (stock["change"] != null &&
                              stock["change"]!.isNotEmpty)
                            Text(
                              "${stock["change"]}  ${stock["change_pct"]}",
                              style: TextStyle(
                                fontSize: 11,
                                color: stock["is_positive"] == "true"
                                    ? Colors.red
                                    : Colors.green,
                              ),
                            ),
                        ],
                      ),
                onTap: _editMode
                    ? () => _toggleSelect(code)
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                StockDetailPage(code: code, name: name),
                          ),
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

class StockDetailPage extends StatefulWidget {
  final String code;
  final String name;

  const StockDetailPage({super.key, required this.code, required this.name});

  @override
  State<StockDetailPage> createState() => _StockDetailPageState();
}

class _StockDetailPageState extends State<StockDetailPage> {
  Map<String, dynamic>? detail;
  bool isLoading = true;
  String error = '';

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final res = await http.get(
        Uri.parse(
          "$backendUrl/stock/detail?code=${Uri.encodeComponent(widget.code)}",
        ),
      );
      setState(() {
        detail = jsonDecode(res.body);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
          ? Center(child: Text("エラー: $error"))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (detail == null || detail!.containsKey('error')) {
      return const Center(child: Text("データを取得できませんでした"));
    }

    final candles = List<Map<String, dynamic>>.from(detail!['candles'] ?? []);

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          _buildPriceCard(
            detail!['price'],
            detail!['change'],
            detail!['change_pct'],
          ),
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.candlestick_chart), text: "チャート"),
              Tab(icon: Icon(Icons.flag), text: "判断"),
              Tab(icon: Icon(Icons.bar_chart), text: "指標"),
              Tab(icon: Icon(Icons.smart_toy), text: "AI分析"),
            ],
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildChartTab(candles),
                _buildJudgeTab(candles),
                _buildIndicatorTab(),
                _buildAiTab(candles),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceCard(dynamic price, dynamic change, dynamic changePct) {
    final isPositive = change != null ? (change as num) >= 0 : true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.code,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  price != null ? "¥${formatNumber(price)}" : "---",
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (change != null)
                  Text(
                    "${isPositive ? '+' : ''}${(change as num).toStringAsFixed(1)}  "
                    "${isPositive ? '+' : ''}${(changePct as num).toStringAsFixed(2)}%",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isPositive ? Colors.red : Colors.green,
                    ),
                  ),
              ],
            ),
            const Icon(Icons.show_chart, size: 40, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildChartTab(List<Map<String, dynamic>> candles) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ローソク足チャート",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          _buildCandleChart(candles),
          const SizedBox(height: 16),
          const Text(
            "RSI",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            "30以下：売られすぎ  70以上：買われすぎ",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _buildRsiChart(candles),
        ],
      ),
    );
  }

  Widget _buildJudgeTab(List<Map<String, dynamic>> candles) {
    if (candles.isEmpty) return const Center(child: Text("データなし"));

    final closes = candles
        .map((c) => (c['close'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final latest = closes.last;
    final ma5 = (candles.last['ma5'] as num?)?.toDouble() ?? 0.0;
    final ma25 = (candles.last['ma25'] as num?)?.toDouble() ?? 0.0;
    final rsi = (candles.last['rsi'] as num?)?.toDouble() ?? 50.0;

    String crossSignal = "なし";
    Color crossColor = Colors.grey;
    if (candles.length >= 2) {
      final prevMa5 =
          (candles[candles.length - 2]['ma5'] as num?)?.toDouble() ?? 0.0;
      final prevMa25 =
          (candles[candles.length - 2]['ma25'] as num?)?.toDouble() ?? 0.0;
      if (prevMa5 < prevMa25 && ma5 > ma25) {
        crossSignal = "ゴールデンクロス（買いシグナル）";
        crossColor = Colors.red;
      } else if (prevMa5 > prevMa25 && ma5 < ma25) {
        crossSignal = "デッドクロス（売りシグナル）";
        crossColor = Colors.green;
      }
    }

    String rsiSignal;
    Color rsiColor;
    if (rsi <= 30) {
      rsiSignal = "売られすぎ（買いチャンス）";
      rsiColor = Colors.red;
    } else if (rsi >= 70) {
      rsiSignal = "買われすぎ（売りチャンス）";
      rsiColor = Colors.green;
    } else {
      rsiSignal = "中立";
      rsiColor = Colors.grey;
    }

    String maSignal;
    Color maColor;
    if (latest > ma5 && latest > ma25) {
      maSignal = "移動平均線の上（強気）";
      maColor = Colors.red;
    } else if (latest < ma5 && latest < ma25) {
      maSignal = "移動平均線の下（弱気）";
      maColor = Colors.green;
    } else {
      maSignal = "移動平均線付近（中立）";
      maColor = Colors.grey;
    }

    final highs = candles
        .map((c) => (c['high'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final lows = candles
        .map((c) => (c['low'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final high52 = highs.reduce((a, b) => a > b ? a : b);
    final low52 = lows.reduce((a, b) => a < b ? a : b);
    final distFromHigh = ((high52 - latest) / high52 * 100).toStringAsFixed(1);
    final distFromLow = ((latest - low52) / low52 * 100).toStringAsFixed(1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "売買シグナル",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          _buildSignalCard("📈 トレンド", crossSignal, crossColor),
          const SizedBox(height: 8),
          _buildSignalCard(
            "💹 RSI (${rsi.toStringAsFixed(1)})",
            rsiSignal,
            rsiColor,
          ),
          const SizedBox(height: 8),
          _buildSignalCard("📊 移動平均線", maSignal, maColor),
          const SizedBox(height: 16),
          const Text(
            "価格帯",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("高値から", style: TextStyle(color: Colors.grey)),
                      Text(
                        "-$distFromHigh%",
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("安値から", style: TextStyle(color: Colors.grey)),
                      Text(
                        "+$distFromLow%",
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 14)),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicatorTab() {
    final per = detail!['per'];
    final pbr = detail!['pbr'];
    final marketCap = detail!['market_cap'];

    String formatMarketCap(dynamic mc) {
      if (mc == null) return "---";
      final v = (mc as num).toDouble();
      if (v >= 1e12) return "${formatNumber(v / 1e12, decimals: 1)}兆円";
      if (v >= 1e8) return "${formatNumber(v / 1e8)}億円";
      return "¥${formatNumber(v)}";
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "バリュエーション指標",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          _buildIndicatorRow(
            "PER（株価収益率）",
            per != null ? "${formatNumber(per, decimals: 1)}倍" : "---",
            "株価が1株あたり利益の何倍か。低いほど割安",
          ),
          _buildIndicatorRow(
            "PBR（株価純資産倍率）",
            pbr != null ? "${formatNumber(pbr, decimals: 1)}倍" : "---",
            "1倍以下は解散価値以下で割安の目安",
          ),
          _buildIndicatorRow(
            "時価総額",
            formatMarketCap(marketCap),
            "市場が評価する会社全体の価値",
          ),
        ],
      ),
    );
  }

  Widget _buildIndicatorRow(String label, String value, String description) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiTab(List<Map<String, dynamic>> candles) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.smart_toy, size: 60, color: Colors.blue),
          SizedBox(height: 16),
          Text(
            "AI分析",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text("近日実装予定", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildCandleChart(List<Map<String, dynamic>> candles) {
    if (candles.isEmpty) return const Text("データなし");

    final data = candles.length > 60
        ? candles.sublist(candles.length - 60)
        : candles;

    final candleList = data.map((c) {
      return Candle(
        date: DateTime.parse(c['date']),
        open: (c['open'] as num?)?.toDouble() ?? 0.0,
        high: (c['high'] as num?)?.toDouble() ?? 0.0,
        low: (c['low'] as num?)?.toDouble() ?? 0.0,
        close: (c['close'] as num?)?.toDouble() ?? 0.0,
        volume: (c['volume'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    return SizedBox(
      height: 300,
      child: Candlesticks(
        candles: candleList,
        candleStyle: CandleStyle(
          bullColor: Colors.red,
          bearColor: Colors.green,
        ),
      ),
    );
  }

  Widget _buildRsiChart(List<Map<String, dynamic>> candles) {
    if (candles.isEmpty) return const Text("データなし");

    final data = candles.length > 30
        ? candles.sublist(candles.length - 30)
        : candles;

    final rsiSpots = data
        .asMap()
        .entries
        .where((e) => e.value['rsi'] != null)
        .map(
          (e) => FlSpot(e.key.toDouble(), (e.value['rsi'] as num).toDouble()),
        )
        .toList();

    return SizedBox(
      height: 120,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (value) {
              if (value == 30 || value == 70) {
                return const FlLine(
                  color: Colors.red,
                  strokeWidth: 1,
                  dashArray: [5, 5],
                );
              }
              return const FlLine(color: Colors.grey, strokeWidth: 0.5);
            },
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value == 30 || value == 70) {
                    return Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10, color: Colors.red),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            bottomTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: rsiSpots,
              isCurved: true,
              color: Colors.purple,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}
