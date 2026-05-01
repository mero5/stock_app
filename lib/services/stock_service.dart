// ============================================================
// StockService
// バックエンドAPI（FastAPI on EC2）との通信を一手に担うサービスクラス。
//
// 担当するAPI：
// ・銘柄検索・銘柄名取得・株価取得・詳細取得
// ・AI分析（スイング分析・相談）
// ・マーケット情報（セクター・イベント・日経平均）
// ・YouTube（チャンネル検索・動画一覧・要約）
//
// 設計方針：
// ・全メソッドはstaticメソッドとして定義（インスタンス不要）
// ・通信エラーは握り潰してデフォルト値を返す（UIをクラッシュさせない）
// ・エラーはdebugPrintでログに残す
// ============================================================

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/stock.dart';

class StockService {
  // ============================================================
  // 銘柄情報
  // ============================================================

  /// 銘柄コードから銘柄名を取得する
  ///
  /// 日本株はJ-Quantsマスタ、米国株はyfinanceから取得。
  /// エラーの場合はコードをそのまま返す（表示が途切れないようにする）。
  ///
  /// [code] 銘柄コード（例：7203、AAPL）
  static Future<String> getName(String code) async {
    try {
      final res = await http.get(
        Uri.parse(
          '${Constants.backendUrl}/stock/name?code=${Uri.encodeComponent(code)}',
        ),
      );
      final data = jsonDecode(res.body);
      return data['name']?.toString() ?? code;
    } catch (_) {
      // 取得失敗時はコードを銘柄名の代わりに使う
      return code;
    }
  }

  /// 株価と前日比を取得する（ホーム画面の一覧表示用・軽量版）
  ///
  /// 詳細APIより軽量で高速。price・change・change_pctを返す。
  /// エラーの場合は空Mapを返す。
  ///
  /// [code] 銘柄コード
  static Future<Map<String, dynamic>> getPrice(String code) async {
    try {
      final res = await http.get(
        Uri.parse(
          '${Constants.backendUrl}/stock/price?code=${Uri.encodeComponent(code)}',
        ),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {};
    }
  }

  /// 銘柄の詳細情報を取得する（詳細画面用）
  ///
  /// ローソク足・移動平均・RSI・MACD・PER・PBR・ニュース等を含む。
  /// エラー時は例外をそのままthrowする（DetailViewModelで処理）。
  ///
  /// [code] 銘柄コード
  static Future<Map<String, dynamic>> getDetail(String code) async {
    final res = await http.get(
      Uri.parse(
        '${Constants.backendUrl}/stock/detail?code=${Uri.encodeComponent(code)}',
      ),
    );
    return jsonDecode(res.body);
  }

  /// 銘柄を検索する
  ///
  /// 日本語入力 → J-Quantsマスタから部分一致検索
  /// 数字入力   → J-Quantsマスタからコード前方一致検索
  /// 英語入力   → yfinanceで米国株検索
  ///
  /// [keyword] 検索キーワード（銘柄名・コード・英語シンボル）
  static Future<List<Map<String, String>>> search(String keyword) async {
    final res = await http.get(
      Uri.parse(
        '${Constants.backendUrl}/search?q=${Uri.encodeComponent(keyword)}',
      ),
    );
    final List data = jsonDecode(res.body);
    return data
        .map<Map<String, String>>(
          (e) => {
            'code': e['code'].toString(),
            'name': e['name'].toString(),
            'market': e['market'].toString(),
          },
        )
        .toList();
  }

  /// ウォッチリスト用：銘柄コードからStockオブジェクトを生成する
  ///
  /// 銘柄名と株価を並行取得してStockモデルに詰めて返す。
  /// ホーム画面のウォッチリスト表示に使用する。
  ///
  /// [code] 銘柄コード（5桁の日本株・英字の米国株）
  static Future<Stock> getStockInfo(String code) async {
    // デフォルト値（取得失敗時に使う）
    String name = code;
    String price = '---';
    String change = '';
    String changePct = '';
    bool isPositive = true;

    try {
      // 銘柄名と株価を順番に取得
      name = await getName(code);
      final priceData = await getPrice(code);

      // 株価が取得できた場合のみ更新
      if (priceData['price'] != null) {
        price = (priceData['price'] as num).toStringAsFixed(0);
      }

      // 前日比が取得できた場合のみ更新
      if (priceData['change'] != null) {
        final c = priceData['change'] as num;
        final cp = priceData['change_pct'] as num;
        isPositive = c >= 0;
        // プラスの場合は「+」を付けて表示
        change = c >= 0 ? '+${c.toStringAsFixed(1)}' : c.toStringAsFixed(1);
        changePct = cp >= 0
            ? '+${cp.toStringAsFixed(2)}%'
            : '${cp.toStringAsFixed(2)}%';
      }
    } catch (_) {
      // エラー時はデフォルト値のまま返す（ウォッチリストが消えないようにする）
    }

    return Stock(
      code: code,
      name: name,
      price: price,
      change: change,
      changePct: changePct,
      isPositive: isPositive,
    );
  }

  /// 銘柄のイベント（決算・配当落ち日）を取得する
  ///
  /// スケジュール画面のウォッチリスト銘柄のイベント表示に使用。
  ///
  /// [codes] 銘柄コードのリスト
  static Future<List<Map<String, dynamic>>> getStockEvents(
    List<String> codes,
  ) async {
    try {
      // カンマ区切りのコード文字列に変換してクエリパラメータで送信
      final codesParam = codes.join(',');
      final res = await http.get(
        Uri.parse(
          '${Constants.backendUrl}/stock/events?codes=${Uri.encodeComponent(codesParam)}',
        ),
      );
      final List data = jsonDecode(res.body);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('イベント取得エラー: $e');
      return [];
    }
  }

  // ============================================================
  // AI分析
  // ============================================================

  /// AI分析（簡易版）を実行する
  ///
  /// ニュース取得・翻訳・センチメント分析を含む。
  /// DetailViewModelのloadNewsで使用する。
  ///
  /// [code] 銘柄コード
  static Future<Map<String, dynamic>> getAiAnalysis(String code) async {
    final res = await http.get(
      Uri.parse('${Constants.backendUrl}/stock/ai_analysis?code=$code'),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// AI相談を実行する
  ///
  /// ユーザーが選択した条件（方向・取引種別・期間・追加質問）を
  /// バックエンドに送信してGPT-4oによるアドバイスを取得する。
  static Future<Map<String, dynamic>> consult({
    required String code,
    required String name,
    required String direction, // 買い / 売り
    required String tradeType, // 現物 / 信用
    required String period, // 短期 / 中期 / 長期
    required List<String> extraQuestions, // 追加質問リスト
    dynamic price,
    dynamic rsi,
    dynamic macd,
    dynamic ma5,
    dynamic ma25,
    dynamic per,
    dynamic pbr,
    dynamic roe,
    dynamic high52,
    dynamic low52,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('${Constants.backendUrl}/stock/consult'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'name': name,
          'direction': direction,
          'trade_type': tradeType,
          'period': period,
          'extra_questions': extraQuestions,
          'price': price,
          'rsi': rsi,
          'macd': macd,
          'ma5': ma5,
          'ma25': ma25,
          'per': per,
          'pbr': pbr,
          'roe': roe,
          'high52': high52,
          'low52': low52,
        }),
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// スイング分析（詳細AI診断）を実行する
  ///
  /// 短期・中期・長期の期間を選んで詳細なAI分析を実行する。
  /// テクニカル・ファンダ・マクロ・セクターデータを総合して判断する。
  /// バックエンドでDynamoDBキャッシュを使用するため2回目以降は高速。
  ///
  /// [code]       銘柄コード
  /// [name]       銘柄名
  /// [detail]     詳細APIのレスポンス（PER・PBR等を含む）
  /// [lastCandle] 最新ローソク足データ（RSI・MACD等を含む）
  /// [checks]     分析に使う指標の選択状態
  /// [period]     分析期間（短期 / 中期 / 長期）
  /// [sectorData] セクタートレンドデータ（AIの精度向上のため）
  static Future<Map<String, dynamic>> runSwingAnalysis({
    required String code,
    required String name,
    required Map<String, dynamic> detail,
    required Map<String, dynamic> lastCandle,
    required Map<String, bool> checks,
    String period = '短期',
    Map<String, dynamic>? sectorData,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('${Constants.backendUrl}/stock/swing_analysis'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'name': name,
          'period': period,
          'price': detail['price'],
          'rsi': lastCandle['rsi'],
          'macd': lastCandle['macd'],
          'ma5': detail['candles']?.last?['ma5'],
          'ma25': detail['candles']?.last?['ma25'],
          'bb_upper': lastCandle['bb_upper'],
          'bb_mid': lastCandle['bb_middle'],
          'bb_lower': lastCandle['bb_lower'],
          'per': detail['per'],
          'pbr': detail['pbr'],
          'roe': detail['roe'],
          'revenue_growth': detail['revenue_growth'],
          'news': detail['news'] ?? [],
          'checks': checks,
          'sector_data': sectorData ?? {},
        }),
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ============================================================
  // マーケット情報
  // ============================================================

  /// マーケットイベント（祝日・FOMC・SQ等）を取得する
  ///
  /// スケジュール画面のカレンダー表示に使用する。
  ///
  /// [year]  取得する年
  /// [month] 取得する月
  static Future<List<Map<String, dynamic>>> getMarketEvents(
    int year,
    int month,
  ) async {
    try {
      final res = await http.get(
        Uri.parse(
          '${Constants.backendUrl}/market/events?year=$year&month=$month',
        ),
      );
      final List data = jsonDecode(res.body);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('マーケットイベント取得エラー: $e');
      return [];
    }
  }

  /// 日経平均の月次データを取得する
  ///
  /// スケジュール画面のカレンダーに日経平均の騰落を表示するために使用。
  ///
  /// [year]  取得する年
  /// [month] 取得する月
  static Future<Map<String, dynamic>> getNikkeiMonthly(
    int year,
    int month,
  ) async {
    try {
      final res = await http.get(
        Uri.parse(
          '${Constants.backendUrl}/nikkei/monthly?year=$year&month=$month',
        ),
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('日経平均取得エラー: $e');
      return {};
    }
  }

  /// セクタートレンドを取得する（日本・米国の主要セクターETF）
  ///
  /// マーケット画面のセクター騰落表示とAI分析のセクター情報に使用。
  /// DynamoDBキャッシュ非対応のため毎回yfinanceから取得する。
  ///
  /// [period] 取得期間（'5d'=5日間、'1mo'=1ヶ月）
  static Future<Map<String, dynamic>> getSectorTrends({
    String period = '5d',
  }) async {
    try {
      final res = await http.get(
        Uri.parse('${Constants.backendUrl}/market/sectors?period=$period'),
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      // エラー時は空のセクターデータを返す
      return {'jp': [], 'us': []};
    }
  }

  /// セクタートレンドのAI解説を取得する
  ///
  /// マーケット画面の「AI相場解説」に表示するコメントを取得する。
  /// GPT-4oが今日のセクター騰落を見て相場環境を解説する。
  ///
  /// [sectors] getSectorTrendsで取得したセクターデータ
  static Future<String> getSectorComment(Map<String, dynamic> sectors) async {
    try {
      final res = await http.post(
        Uri.parse('${Constants.backendUrl}/market/sector_comment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(sectors),
      );
      final data = jsonDecode(res.body);
      return data['comment'] ?? '';
    } catch (e) {
      return '';
    }
  }

  // ============================================================
  // YouTube
  // ============================================================

  /// YouTubeチャンネルを検索する
  ///
  /// YouTube Data APIを使用してチャンネル情報を取得する。
  /// YouTube画面の検索機能に使用する。
  ///
  /// [query] 検索キーワード
  static Future<List<Map<String, String>>> searchChannels(String query) async {
    try {
      final res = await http.get(
        Uri.parse(
          '${Constants.backendUrl}/channels/search?q=${Uri.encodeComponent(query)}',
        ),
      );
      final List data = jsonDecode(res.body);
      return data
          .map<Map<String, String>>(
            (e) => {
              'channel_id': e['channel_id'].toString(),
              'name': e['name'].toString(),
              'description': e['description'].toString(),
              'thumbnail': e['thumbnail'].toString(),
            },
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// YouTube動画の字幕をAIで要約する
  ///
  /// 動画のタイトルと字幕テキストをバックエンドに送信して
  /// Gemini 2.5 Flashによる要約・センチメント分析を取得する。
  ///
  /// [title]      動画タイトル
  /// [transcript] 動画の字幕テキスト
  static Future<String> summarize(String title, String transcript) async {
    try {
      final res = await http.post(
        Uri.parse('${Constants.backendUrl}/summarize'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'title': title, 'transcript': transcript}),
      );
      final data = jsonDecode(res.body);
      return data['summary'] ?? '要約できませんでした';
    } catch (e) {
      return 'エラーが発生しました: $e';
    }
  }

  /// YouTubeチャンネルの最新動画一覧を取得する
  ///
  /// チャンネルIDを指定して最新の動画リストを取得する。
  /// YouTube動画一覧画面に使用する。
  ///
  /// [channelId]  YouTubeチャンネルID
  /// [maxResults] 取得する動画数（デフォルト10件）
  static Future<List<Map<String, dynamic>>> getChannelVideos(
    String channelId, {
    int maxResults = 10,
  }) async {
    try {
      final res = await http.get(
        Uri.parse(
          '${Constants.backendUrl}/channels/$channelId/videos?max_results=$maxResults',
        ),
      );
      final data = jsonDecode(res.body);
      return List<Map<String, dynamic>>.from(data['videos'] ?? []);
    } catch (e) {
      return [];
    }
  }
}
