// ============================================================
// HomeViewModel
// ホーム画面のロジックと状態を管理するViewModel。
//
// 担当する処理：
// ・APIの疎通確認（ヘルスチェック）
// ・ウォッチリストの取得・削除
// ・編集モードの管理
//
// ChangeNotifierを継承しているため、notifyListeners()を呼ぶと
// このViewModelをlistenしているWidgetが自動で再描画される。
// ============================================================

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/stock.dart';
import '../services/stock_service.dart';
import '../services/watchlist_service.dart';
import '../config/constants.dart';

class HomeViewModel extends ChangeNotifier {
  // ============================================================
  // 状態変数（State）
  // ============================================================

  /// ウォッチリストの銘柄一覧
  /// Stock型はcode/name/price/change/changePctを持つ
  List<Stock> watchList = [];

  /// データ取得中フラグ（trueの間はローディング表示）
  bool isLoading = true;

  /// APIが正常に使えるかどうかのフラグ
  /// falseの場合はバナーでユーザーに通知する
  bool apiAvailable = true;

  /// APIエラー時のメッセージ
  /// 例：「Yahoo Finance・J-Quantsに接続できません」
  String apiErrorMsg = '';

  /// 編集モードフラグ
  /// trueの場合はチェックボックスと削除ボタンが表示される
  bool editMode = false;

  /// 編集モードで選択中の銘柄コードリスト
  List<String> selectedCodes = [];

  // ============================================================
  // コンストラクタ
  // ViewModelが生成されたタイミングで初期化処理を実行する
  // ============================================================

  HomeViewModel() {
    // APIの疎通確認とウォッチリスト取得を並行して実行
    checkApiHealth();
    loadFavorites();
  }

  // ============================================================
  // API疎通確認
  // ============================================================

  /// バックエンドの /health エンドポイントを叩いて
  /// yfinanceとJ-Quantsが正常に動いているか確認する
  ///
  /// どちらかがエラーの場合はapiAvailableをfalseにして
  /// 画面上部にエラーバナーを表示する
  Future<void> checkApiHealth() async {
    try {
      final res = await http
          .get(Uri.parse('${Constants.backendUrl}/health'))
          .timeout(const Duration(seconds: 10)); // 10秒でタイムアウト

      final data = jsonDecode(res.body);
      final yf = data['yfinance'] == 'ok'; // Yahoo Finance疎通確認
      final jq = data['jquants'] == 'ok'; // J-Quants疎通確認

      // どちらかがエラーの場合はエラー状態をセット
      if (!yf || !jq) {
        apiAvailable = false;
        apiErrorMsg =
            [if (!yf) 'Yahoo Finance', if (!jq) 'J-Quants'].join('・') +
            'に接続できません';
        notifyListeners();
      }
    } catch (_) {
      // タイムアウトや接続エラーの場合
      apiAvailable = false;
      apiErrorMsg = 'サーバーに接続できません';
      notifyListeners();
    }
  }

  // ============================================================
  // ウォッチリスト取得
  // ============================================================

  /// DynamoDBからウォッチリストのコード一覧を取得し、
  /// 各銘柄の名前・株価・前日比を並行取得してwatchListに格納する
  ///
  /// Future.waitで全銘柄を並行取得することで高速化している
  Future<void> loadFavorites() async {
    // ローディング開始
    isLoading = true;
    notifyListeners();

    try {
      // DynamoDBから銘柄コードの一覧を取得
      final codes = await WatchlistService.getCodes();

      // 各コードの銘柄情報を並行取得
      // （直列だと銘柄数分の時間がかかるため並行処理）
      final stocks = await Future.wait(
        codes.map((code) => StockService.getStockInfo(code)),
      );

      watchList = stocks;
    } catch (e) {
      debugPrint('ウォッチリスト取得エラー: $e');
    } finally {
      // 成功・失敗どちらでもローディングを終了
      isLoading = false;
      notifyListeners();
    }
  }

  // ============================================================
  // 編集モード
  // ============================================================

  /// 編集モードのON/OFFを切り替える
  /// OFFにした場合は選択中の銘柄もリセットする
  void toggleEditMode() {
    editMode = !editMode;
    selectedCodes = []; // 編集モード終了時は選択状態をリセット
    notifyListeners();
  }

  /// 銘柄の選択状態を切り替える
  /// すでに選択済みなら解除、未選択なら選択する
  void toggleSelect(String code) {
    if (selectedCodes.contains(code)) {
      selectedCodes.remove(code);
    } else {
      selectedCodes.add(code);
    }
    notifyListeners();
  }

  // ============================================================
  // 銘柄削除
  // ============================================================

  /// 選択中の銘柄をウォッチリストから削除する
  ///
  /// 処理の流れ：
  /// 1. 選択中の各コードをDynamoDBから削除
  /// 2. 選択状態・編集モードをリセット
  /// 3. ウォッチリストを再取得して画面を更新
  Future<void> deleteSelected() async {
    // 選択中の銘柄を順番に削除
    for (final code in selectedCodes) {
      await WatchlistService.delete(code);
    }

    // 削除後は選択状態と編集モードをリセット
    selectedCodes = [];
    editMode = false;
    notifyListeners();

    // ウォッチリストを再取得して画面を更新
    await loadFavorites();
  }
}
