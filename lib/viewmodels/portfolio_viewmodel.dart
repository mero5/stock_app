// ============================================================
// PortfolioViewModel
// ポートフォリオ診断画面のロジックと状態を一手に担うViewModel。
// Screenクラス（UI）からロジックを切り離すことで、
// ・テストしやすくなる
// ・画面ファイルが肥大化しない
// というメリットがある。
//
// ChangeNotifierを継承しているため、notifyListeners()を呼ぶと
// このViewModelをlistenしているWidgetが自動で再描画される。
// ============================================================

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../services/stock_service.dart';

class PortfolioViewModel extends ChangeNotifier {
  // ============================================================
  // 状態変数（State）
  // これらの値が変わるとUIが再描画される
  // ============================================================

  /// 入力中の保有銘柄リスト
  /// 各要素は {code, name, ticker_code, cost_price, shares, trade_type, position} を持つMap
  List<Map<String, dynamic>> holdings = [];

  /// AI診断の結果（未実行の場合はnull）
  Map<String, dynamic>? result;

  /// 診断中フラグ（trueの間はローディング表示）
  bool isAnalyzing = false;

  /// 直近の診断エラー（成功した場合はnull）
  ///
  /// analyze() の完了後に画面側がこれを見てポップアップを出す。
  /// 以前はcatchでログを出すだけだったため、
  /// 失敗しても入力画面のまま何も表示されなかった。
  String? analysisError;

  /// 直近の診断エラーの技術的な詳細（ポップアップの折りたたみに表示）
  String? analysisErrorDetail;

  /// デバッグ用：最後にAIに送ったプロンプトのJSON文字列
  String lastPrompt = '';

  /// 選択中の診断期間（短期 / 中期 / 長期）
  String selectedPeriod = '中期';

  /// ログイン中ユーザーのプロファイル
  /// リスク許容度・投資スタイルなどを保持し、AIプロンプトに渡す
  Map<String, dynamic>? userProfile;

  // ============================================================
  // ユーザープロファイル
  // ============================================================

  /// ユーザープロファイルをセットする
  /// 画面初期化時にDBから取得したプロファイルをここに渡す
  void setUserProfile(Map<String, dynamic>? profile) {
    userProfile = profile;
    notifyListeners(); // UIに変更を通知
  }

  // ============================================================
  // 銘柄の追加・削除・更新
  // ============================================================

  /// 保有銘柄を1件追加する
  /// 最大10件まで追加可能。超えた場合は何もしない。
  void addHolding() {
    // 最大件数チェック
    if (holdings.length >= 10) return;

    // 初期値を持ったMapを追加
    holdings.add({
      'code': '', // 銘柄コード（例：7203、AAPL）
      'name': '', // 銘柄名（例：トヨタ自動車）
      'ticker_code': '', // yfinance用コード（例：7203.T）
      'cost_price': null, // 取得単価（任意入力）
      'shares': null, // 保有株数（任意入力）
      'trade_type': '現物', // 現物 / 信用
      'position': '買い', // 買い / 空売り
    });
    notifyListeners();
  }

  /// 指定インデックスの銘柄を削除する
  void removeHolding(int index) {
    holdings.removeAt(index);
    notifyListeners();
  }

  /// 銘柄の特定フィールドを更新する
  ///
  /// 例：updateHolding(0, 'cost_price', 3500.0)
  /// 取引種別を「現物」に変更した場合は空売りポジションを自動リセットする
  void updateHolding(int index, String key, dynamic value) {
    holdings[index][key] = value;

    // 現物に変更した場合は空売りが選択できないのでリセット
    if (key == 'trade_type' && value == '現物') {
      if (holdings[index]['position'] == '空売り') {
        holdings[index]['position'] = '買い';
      }
    }
    notifyListeners();
  }

  /// 検索で選んだ銘柄を指定インデックスにセットする
  ///
  /// codeからyfinance用のticker_codeも自動生成する
  void setStock(int index, Map<String, String> stock) {
    final code = stock['code'] ?? '';
    holdings[index]['code'] = code;
    holdings[index]['name'] = stock['name'] ?? '';
    holdings[index]['ticker_code'] = _toTickerCode(code); // yfinance形式に変換
    notifyListeners();
  }

  // ============================================================
  // 期間選択
  // ============================================================

  /// 診断期間を変更する（短期 / 中期 / 長期）
  void setPeriod(String period) {
    selectedPeriod = period;
    notifyListeners();
  }

  // ============================================================
  // 診断結果リセット
  // ============================================================

  /// 診断結果をクリアして入力画面に戻す
  void resetResult() {
    result = null;
    notifyListeners();
  }

  // ============================================================
  // ユーティリティ
  // ============================================================

  /// 銘柄コードをyfinance用のticker形式に変換する
  ///
  /// 4桁数字 → 末尾に「.T」を付ける（例：7203 → 7203.T）
  /// 5桁数字 → 末尾の「0」を除いて「.T」を付ける（例：72030 → 7203.T）
  /// 英字（米国株）→ そのまま返す（例：AAPL → AAPL）
  String _toTickerCode(String code) {
    if (RegExp(r'^\d{4}$').hasMatch(code)) return '$code.T';
    if (RegExp(r'^\d{5}$').hasMatch(code)) return '${code.substring(0, 4)}.T';
    return code;
  }

  // ============================================================
  // AI診断実行
  // ============================================================

  /// ポートフォリオのAI診断を実行する
  ///
  /// 処理の流れ：
  /// 1. 銘柄コードが未入力の銘柄を除外
  /// 2. セクターデータを取得（AIの精度向上のため）
  /// 3. バックエンドにPOSTリクエストを送信
  /// 4. レスポンスをresultに格納してUIを更新
  ///
  /// タイムアウトは120秒（GPT-4oの応答時間を考慮）
  Future<void> analyze() async {
    // コードが入力されている銘柄のみ対象にする
    final validHoldings = holdings
        .where((h) => h['code'].toString().isNotEmpty)
        .toList();

    // 有効な銘柄がなければ何もしない
    if (validHoldings.isEmpty) return;

    // ローディング開始
    isAnalyzing = true;
    result = null;
    analysisError = null;
    analysisErrorDetail = null;
    notifyListeners();

    try {
      // セクターデータを先に取得
      // AIがセクターの強弱を判断するために必要なデータ
      final sectorData = await StockService.getSectorTrends();

      // デバッグ用：送信するJSONをlastPromptに保存
      lastPrompt = jsonEncode({
        'user_profile': userProfile ?? {},
        'holdings': validHoldings,
        'period': selectedPeriod,
        'sector_data': sectorData,
      });

      // バックエンドにPOSTリクエストを送信
      final res = await http
          .post(
            Uri.parse('${Constants.backendUrl}/portfolio/diagnosis'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_profile': userProfile ?? {},
              'holdings': validHoldings,
              'period': selectedPeriod,
              'sector_data': sectorData,
            }),
          )
          .timeout(const Duration(seconds: 120)); // GPT-4oの応答を待つため長めに設定

      if (res.statusCode != 200) {
        // サーバーが500等を返した場合。
        // ステータスを見ずにjsonDecodeしていたため、
        // エラー本文を結果として扱って空の診断画面が出ていた。
        debugPrint('診断エラー: HTTP ${res.statusCode} / ${res.body}');
        analysisError = 'サーバーでエラーが発生しました（HTTP ${res.statusCode}）。'
            'しばらく待ってからもう一度お試しください。';
        analysisErrorDetail = res.body;
      } else {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final err = decoded['error'];
        if (err != null) {
          // バックエンドはエラーもHTTP 200で返すのでここで見分ける
          debugPrint('診断エラー: $err');
          analysisError = err.toString();
          analysisErrorDetail = decoded['error_detail']?.toString();
        } else {
          result = decoded;
        }
      }
    } catch (e) {
      debugPrint('診断エラー: $e');
      analysisError = e is TimeoutException
          ? '診断に時間がかかりすぎたため中断しました。'
                '銘柄数を減らすか、時間をおいて再度お試しください。'
          : 'サーバーに接続できませんでした。'
                'ネットワーク状況を確認してもう一度お試しください。';
      analysisErrorDetail = e.toString();
    } finally {
      // 成功・失敗どちらでもローディングを終了
      isAnalyzing = false;
      notifyListeners();
    }
  }
}
