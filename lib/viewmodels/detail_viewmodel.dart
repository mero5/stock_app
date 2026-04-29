// ============================================================
// DetailViewModel
// 銘柄詳細画面のロジックと状態を管理するViewModel。
//
// 担当する処理：
// ・銘柄詳細データの取得（チャート・RSI・PER等）
// ・AI分析の実行（短期・中期・長期）
// ・ニュースの取得
// ・分析期間・分析オプションの管理
// ・プログレスバーの進捗管理
//
// ChangeNotifierを継承しているため、notifyListeners()を呼ぶと
// このViewModelをlistenしているWidgetが自動で再描画される。
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/stock_service.dart';

class DetailViewModel extends ChangeNotifier {
  // ============================================================
  // 状態変数（State）
  // ============================================================

  /// 銘柄の詳細データ
  /// チャート・RSI・PER・PBR・ニュース等を含むMap
  /// 未取得の場合はnull
  Map<String, dynamic>? detail;

  /// 詳細データ取得中フラグ
  bool isLoading = true;

  /// エラーメッセージ（データ取得に失敗した場合に表示）
  String error = '';

  /// 選択中の分析期間（短期 / 中期 / 長期）
  String selectedPeriod = '短期';

  /// AI分析で使用する指標の選択状態
  /// key: 指標名, value: 使用するかどうか
  final Map<String, bool> analysisChecks = {
    'technical': true, // テクニカル分析（RSI・MACD等）
    'fundamental': true, // ファンダメンタル分析（PER・PBR等）
    'macro': false, // マクロ分析（VIX・ドル円等）
    'supply': false, // 需給分析（信用倍率・空売り比率等）
    'news': false, // ニュース分析
  };

  /// AI分析の結果
  /// 未実行の場合はnull
  Map<String, dynamic>? aiResult;

  /// AI分析中フラグ
  bool isAnalyzing = false;

  /// AI分析のプログレスバーの進捗（0.0〜1.0）
  double analysisProgress = 0.0;

  /// ニュース一覧
  List<Map<String, dynamic>> newsItems = [];

  /// ニュース取得中フラグ
  bool isLoadingNews = false;

  /// ニュース取得のプログレスバーの進捗（0.0〜1.0）
  double newsProgress = 0.0;

  // ============================================================
  // 銘柄詳細データの取得
  // ============================================================

  /// バックエンドから銘柄の詳細データを取得する
  ///
  /// 取得するデータ：
  /// ・ローソク足（3ヶ月分）
  /// ・移動平均（MA5・MA25）
  /// ・RSI・MACD・ボリンジャーバンド
  /// ・PER・PBR・ROE等のファンダメンタル指標
  /// ・直近ニュース
  Future<void> loadDetail(String code) async {
    // ローディング開始
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final data = await StockService.getDetail(code);
      detail = data;
    } catch (e) {
      // エラーメッセージをセットして画面に表示する
      error = e.toString();
      debugPrint('詳細取得エラー: $e');
    } finally {
      // 成功・失敗どちらでもローディングを終了
      isLoading = false;
      notifyListeners();
    }
  }

  // ============================================================
  // 分析期間・オプション
  // ============================================================

  /// 分析期間を変更する（短期 / 中期 / 長期）
  void setPeriod(String period) {
    selectedPeriod = period;
    notifyListeners();
  }

  /// 分析指標の使用フラグを切り替える
  /// 例：toggleCheck('macro') でマクロ分析のON/OFFを切り替え
  void toggleCheck(String key) {
    analysisChecks[key] = !(analysisChecks[key] ?? false);
    notifyListeners();
  }

  // ============================================================
  // AI分析
  // ============================================================

  /// AI分析を実行する
  ///
  /// 処理の流れ：
  /// 1. セクターデータを先に取得（AIの精度向上のため）
  /// 2. プログレスバーを擬似的に進める（APIの応答待ちの間）
  /// 3. バックエンドにリクエストを送信
  /// 4. 結果をaiResultに格納してUIを更新
  ///
  /// [lastCandle] チャートの最新ローソク足データ（RSI・MACD等を含む）
  /// [code]       銘柄コード
  /// [name]       銘柄名
  Future<void> runAiAnalysis({
    required String code,
    required String name,
    required Map<String, dynamic> lastCandle,
  }) async {
    if (detail == null) return;

    // ローディング開始・前回の結果をリセット
    isAnalyzing = true;
    aiResult = null;
    analysisProgress = 0.0;
    notifyListeners();

    // セクターデータを先に取得
    // AIがセクターの強弱を判断するために必要なデータ
    final sectorData = await StockService.getSectorTrends();

    // プログレスバーを擬似的に進めるタイマー
    // APIが応答するまでの待ち時間に進捗を見せるUX改善
    final progressTimer = Timer.periodic(const Duration(milliseconds: 450), (
      timer,
    ) {
      if (!isAnalyzing) {
        timer.cancel();
        return;
      }
      // 最大90%まで進める（100%は完了時に設定）
      if (analysisProgress < 0.9) {
        analysisProgress += 0.03;
        notifyListeners();
      }
    });

    try {
      final result = await StockService.runSwingAnalysis(
        code: code,
        name: name,
        detail: detail!,
        lastCandle: lastCandle,
        checks: analysisChecks,
        period: selectedPeriod,
        sectorData: sectorData,
      );

      // タイマー停止・進捗を100%にして完了
      progressTimer.cancel();
      analysisProgress = 1.0;
      aiResult = result;
      notifyListeners();

      // 完了表示を少し見せてからローディングを終了
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      progressTimer.cancel();
      debugPrint('AI分析エラー: $e');
    } finally {
      isAnalyzing = false;
      notifyListeners();
    }
  }

  // ============================================================
  // ニュース取得
  // ============================================================

  /// 銘柄に関連するニュースを取得する
  ///
  /// 処理の流れ：
  /// 1. プログレスバーを擬似的に進める
  /// 2. バックエンドからニュース一覧を取得
  /// 3. newsItemsに格納してUIを更新
  ///
  /// [code] 銘柄コード
  Future<void> loadNews(String code) async {
    // ローディング開始
    isLoadingNews = true;
    newsProgress = 0.0;
    notifyListeners();

    // プログレスバーを擬似的に進めるタイマー
    final progressTimer = Timer.periodic(const Duration(milliseconds: 300), (
      timer,
    ) {
      if (!isLoadingNews) {
        timer.cancel();
        return;
      }
      // 最大90%まで進める
      if (newsProgress < 0.9) {
        newsProgress += 0.018;
        notifyListeners();
      }
    });

    try {
      // ニュース取得はAI分析APIを流用
      // レスポンスの 'news' フィールドにニュース一覧が入っている
      final data = await StockService.getAiAnalysis(code);
      final news = data['news'] as List? ?? [];

      progressTimer.cancel();
      newsProgress = 1.0;
      newsItems = news.map((n) => n as Map<String, dynamic>).toList();
      notifyListeners();

      // 完了表示を少し見せる
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      progressTimer.cancel();
      debugPrint('ニュース取得エラー: $e');
    } finally {
      isLoadingNews = false;
      notifyListeners();
    }
  }

  // ============================================================
  // リソース解放
  // ============================================================

  /// ViewModelが破棄される際に呼ばれる
  /// タイマーなどのリソースを解放する
  @override
  void dispose() {
    // 現在はTimerをメンバ変数として持っていないが、
    // 将来的にタイマーをフィールドに持つ場合はここでcancelする
    super.dispose();
  }
}
