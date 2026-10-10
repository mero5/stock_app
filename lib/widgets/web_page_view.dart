// ============================================================
// WebPageView
// バックエンドが返す画面（/web/...）を WebView で表示する部品。
//
// 画面の中身をバックエンドのHTMLにすると、見た目や表示の不具合を
// バックエンドのデプロイだけで直せる（アプリのリリースが要らない）。
// HTML・CSS・JS は backend/web/、どの画面を WebView にするかは
// backend/config/web_screens.py（アプリは AppConfigService.useWeb で確認する）。
//
// ・ログインのトークンはURLに入れない（サーバーのログに残るため）。ページが
//   JavaScriptChannel「StockAppBridge」で頼んできたら、その都度最新のものを渡す
//   （backend/web/static/bridge.js）
// ・開いてよいのはバックエンドの /web/ の下だけ。ほかのリンクは外部のブラウザで開く
// ・アプリのWeb版（kIsWeb）では WebView が使えないので、この部品は使わない
//   （呼ぶ側が AppConfigService.useWeb で分ける）
// ============================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/constants.dart';
import '../services/auth_service.dart';

class WebPageView extends StatefulWidget {
  /// 表示するページのパス（例：'/web/notices'）
  final String path;

  const WebPageView({super.key, required this.path});

  /// WebView の中で開いてよいURLなら true（バックエンドの /web/ の下だけ）
  @visibleForTesting
  static bool isAllowedUrl(String url) =>
      url.startsWith('${Constants.backendUrl}/web/');

  @override
  State<WebPageView> createState() => WebPageViewState();
}

class WebPageViewState extends State<WebPageView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isBackgroundSet = false;

  Uri get _pageUri => Uri.parse('${Constants.backendUrl}${widget.path}');

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('StockAppBridge', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            // 画像など一部の読み込み失敗は無視し、ページ自体が開けないときだけエラーにする
            if (error.isForMainFrame == false) return;
            debugPrint('WebViewの読み込みエラー: ${error.description}');
            _showError();
          },
          onHttpError: (error) {
            if (error.request?.uri != _pageUri) return;
            debugPrint('WebViewのHTTPエラー: ${error.response?.statusCode}');
            _showError();
          },
          onNavigationRequest: _onNavigationRequest,
        ),
      )
      ..loadRequest(_pageUri);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 読み込み中に白く光らないよう、画面の背景色に合わせる（テーマは initState では読めない）
    if (_isBackgroundSet) return;
    _isBackgroundSet = true;
    _controller.setBackgroundColor(
      Theme.of(context).scaffoldBackgroundColor,
    );
  }

  /// ページを読み込み直す（画面の「再読み込み」ボタン・エラーからの再試行）
  void reload() {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    _controller.loadRequest(_pageUri);
  }

  void _showError() {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _hasError = true;
    });
  }

  /// バックエンドの /web/ の下はそのまま開き、ほかは外部のブラウザに渡す
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    if (WebPageView.isAllowedUrl(request.url)) {
      return NavigationDecision.navigate;
    }
    final uri = Uri.tryParse(request.url);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      launchUrl(uri, mode: LaunchMode.externalApplication).catchError((e) {
        debugPrint('外部のブラウザで開けませんでした: $e');
        return false;
      });
    }
    return NavigationDecision.prevent;
  }

  /// ページからの依頼（JSON 文字列）を受け取る
  Future<void> _onMessage(JavaScriptMessage message) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('WebViewからの依頼を読めませんでした: $e');
      return;
    }
    if (data['type'] == 'token') {
      final token = await AuthService.getAccessToken();
      if (!mounted) return;
      // jsonEncode で文字列にして渡す（null もそのまま null になる）
      await _controller.runJavaScript(
        'window.StockApp && window.StockApp.receiveToken(${jsonEncode(token)});',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ページを読み込めませんでした。\n'
                '通信状況を確認してもう一度お試しください。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: reload, child: const Text('再読み込み')),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
