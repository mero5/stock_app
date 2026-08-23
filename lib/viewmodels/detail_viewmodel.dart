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
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';

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

  /// 直近のAI分析エラー（成功した場合はnull）
  ///
  /// runAiAnalysis の完了後に画面側がこれを見てポップアップを出す。
  /// 以前は失敗しても画面に何も出ないことがあったため追加した。
  String? analysisError;

  /// 直近のAI分析エラーの技術的な詳細（ポップアップの折りたたみに表示）
  String? analysisErrorDetail;

  /// 直近のニュース取得エラー（成功した場合はnull）
  String? newsError;

  /// 直近のニュース取得エラーの技術的な詳細
  String? newsErrorDetail;

  /// ニュース一覧
  List<Map<String, dynamic>> newsItems = [];

  /// ニュース取得中フラグ
  bool isLoadingNews = false;

  /// ニュース取得のプログレスバーの進捗（0.0〜1.0）
  double newsProgress = 0.0;

  /// ユーザープロファイル（AI分析の優先順位・期間の日数設定等）
  /// 未取得・未設定の場合はnull（デフォルト設定で動作する）
  Map<String, dynamic>? userProfile;

  /// 直近の決算発表日（YYYY-MM-DD）。取得できない場合はnull
  ///
  /// AI分析に渡して決算アラート（決算跨ぎリスク）を出させるために使う。
  /// 以前は取得していながらAI分析に渡しておらず、
  /// 決算アラートが常に「なし」になっていた。
  String? earningsDate;

  /// 直近の配当落ち日（YYYY-MM-DD）。取得できない場合はnull
  String? dividendRecordDate;

  // ============================================================
  // ユーザープロファイル
  // ============================================================

  /// ユーザープロファイルを取得する
  ///
  /// AI分析の優先順位（priority_short/medium/long）・
  /// 期間の日数設定（period_short_max_days/period_medium_max_days）に使用する。
  /// 未ログイン・未設定の場合はnullのままとなり、バックエンド側のデフォルト値で動作する。
  Future<void> loadUserProfile() async {
    try {
      final userId = await AuthService.getUserId();
      if (userId == null) return;
      userProfile = await UserProfileService.getProfile(userId);
      notifyListeners();
    } catch (e) {
      debugPrint('プロファイル取得エラー: $e');
    }
  }

  // ============================================================
  // 銘柄イベント（決算日・配当落ち日）
  // ============================================================

  /// 決算発表日・配当落ち日を取得する
  ///
  /// `/stock/events` はスケジュール画面でも使っているAPI。
  /// ここで取得した決算日をAI分析に渡すことで、
  /// 「3日後に決算 → 様子見推奨」といった判断ができるようになる。
  ///
  /// 取得できなくてもAI分析は続行できるため、失敗は握り潰す。
  Future<void> loadEvents(String code) async {
    try {
      final events = await StockService.getStockEvents([code]);

      // 今日以降で一番近い日付を選ぶ（過去の決算日は意味がない）
      final today = DateTime.now();
      String? pickNearest(String type) {
        final dates =
            events
                .where((e) => e['type'] == type && e['date'] != null)
                .map((e) => e['date'].toString())
                .where((d) {
                  final dt = DateTime.tryParse(d);
                  return dt != null && !dt.isBefore(DateTime(today.year, today.month, today.day));
                })
                .toList()
              ..sort();
        return dates.isEmpty ? null : dates.first;
      }

      earningsDate = pickNearest('earnings');
      dividendRecordDate = pickNearest('ex_dividend');
      notifyListeners();
    } catch (e) {
      debugPrint('銘柄イベント取得エラー: $e');
    }
  }

  /// 分析期間の表示ラベルを返す（例：「14日以内」「15〜90日」「90日超」）
  ///
  /// プロファイルの期間日数設定を反映。未設定の場合は
  /// デフォルト（短期14日・中期90日）を使う。
  String periodLabel(String period) {
    final shortMax =
        (userProfile?['period_short_max_days'] as num?)?.toInt() ?? 14;
    final mediumMax =
        (userProfile?['period_medium_max_days'] as num?)?.toInt() ?? 90;
    if (period == '短期') return '$shortMax日以内';
    if (period == '中期') return '${shortMax + 1}〜$mediumMax日';
    return '$mediumMax日超';
  }

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

    // ローディング開始・前回の結果とエラーをリセット
    isAnalyzing = true;
    aiResult = null;
    analysisError = null;
    analysisErrorDetail = null;
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
        userProfile: userProfile,
        earningsDate: earningsDate,
        dividendRecordDate: dividendRecordDate,
        userId: await AuthService.getUserId(),
      );

      // タイマー停止・進捗を100%にして完了
      progressTimer.cancel();
      analysisProgress = 1.0;
      aiResult = result;

      // errorキーが入っていれば失敗扱いにする
      // （サーバーはエラーもHTTP 200で返すため、ここで見分ける必要がある）
      final err = result['error'];
      if (err != null) {
        analysisError = err.toString();
        analysisErrorDetail = result['error_detail']?.toString();
        debugPrint('AI分析エラー: $analysisError / $analysisErrorDetail');
      }
      notifyListeners();

      // 完了表示を少し見せてからローディングを終了
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      progressTimer.cancel();
      debugPrint('AI分析エラー: $e');
      analysisError = '予期せぬエラーが発生しました。しばらく待ってからもう一度お試しください。';
      analysisErrorDetail = e.toString();
      aiResult = {'error': analysisError, 'error_detail': analysisErrorDetail};
      analysisProgress = 0.0;
      notifyListeners();
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
    newsError = null;
    newsErrorDetail = null;
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

      progressTimer.cancel();
      newsProgress = 1.0;

      // errorキーがあれば失敗扱い
      // （以前はここを見ておらず、失敗しても空リストのまま
      //   「100%になったのに何も出ない」状態になっていた）
      final err = data['error'];
      if (err != null) {
        newsError = err.toString();
        newsErrorDetail = data['error_detail']?.toString();
        debugPrint('ニュース取得エラー: $newsError / $newsErrorDetail');
      } else {
        final news = data['news'] as List? ?? [];
        newsItems = news.map((n) => n as Map<String, dynamic>).toList();
      }
      notifyListeners();

      // 完了表示を少し見せる
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      progressTimer.cancel();
      debugPrint('ニュース取得エラー: $e');
      newsError = 'ニュースの取得に失敗しました。しばらく待ってからもう一度お試しください。';
      newsErrorDetail = e.toString();
      notifyListeners();
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
