// ============================================================
// ScheduleScreen
// 株式市場のイベントカレンダーを表示する画面。
//
// 表示モードは2つ：
// ・カレンダー（月表示）
//   - 日経平均の日次騰落（赤=上昇・緑=下落・色の濃さで変動幅を表現）
//   - マーケットイベント（FOMC・日銀・SQ・祝日等）のドット
//   - ウォッチリスト銘柄の決算・配当落ち日のドット
//   - イベント一覧（月内の全イベントを日付順）
// ・直近の予定（リスト表示）
//   - 今日以降のイベントを種別で絞って一覧表示
//   - 「FOMCの次はいつか」を月をめくらずに確認できる
//   - 各イベントに「あと◯日」を表示
//
// どちらのモードでも、表示するイベント種別はフィルタで切り替えられる。
// フィルタ内容はSharedPreferencesに保存され、次回起動時も維持される。
//
// データソース：
// ・マーケットイベント   → バックエンド（/market/events）
// ・直近のマーケットイベント → バックエンド（/market/upcoming）
// ・日経平均月次データ   → バックエンド（/nikkei/monthly）
// ・銘柄イベント        → バックエンド（/stock/events）
// ・ウォッチリスト銘柄   → DynamoDB（WatchlistService）
// ・表示フィルタ         → SharedPreferences（EventFilterService）
// ============================================================

import 'package:flutter/material.dart';
import '../config/event_types.dart';
import '../services/stock_service.dart';
import '../services/watchlist_service.dart';
import '../services/event_filter_service.dart';
import '../widgets/api_error_banner.dart';

class ScheduleScreen extends StatefulWidget {
  /// APIが正常に使えるかどうかのフラグ
  final bool apiAvailable;

  /// APIエラー時のメッセージ
  final String apiErrorMsg;

  const ScheduleScreen({
    super.key,
    this.apiAvailable = true,
    this.apiErrorMsg = '',
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  // ============================================================
  // 状態変数
  // ============================================================

  /// 現在表示中の年月
  DateTime _focusedMonth = DateTime.now();

  /// ウォッチリスト銘柄の決算・配当落ち日イベント
  List<Map<String, dynamic>> _stockEvents = [];

  /// マーケットイベント（FOMC・日銀・SQ・祝日等）
  List<Map<String, dynamic>> _marketEvents = [];

  /// データ取得中フラグ
  bool _isLoading = false;

  /// 日経平均の月次騰落データ
  /// key: 「YYYY-MM-DD」形式の日付、value: {close・change・change_pct}
  Map<String, dynamic> _nikkeiData = {};

  /// 表示モード（false=カレンダー / true=直近の予定）
  bool _showUpcoming = false;

  /// 表示するイベントグループのキー（フィルタ）
  /// 初期値は全表示。読み込み後にSharedPreferencesの内容で上書きされる。
  Set<String> _visibleGroups = Set<String>.from(kAllEventGroupKeys);

  /// 「直近の予定」で絞り込み中のグループキー（nullなら全種別）
  String? _upcomingFilterKey;

  /// 今日以降のマーケットイベント（「直近の予定」用）
  List<Map<String, dynamic>> _upcomingMarketEvents = [];

  /// 「直近の予定」を読み込み済みか
  bool _upcomingLoaded = false;

  // ============================================================
  // ライフサイクル
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadFilter();
    _loadAllEvents();
  }

  /// 保存済みの表示フィルタを読み込む
  Future<void> _loadFilter() async {
    final groups = await EventFilterService.getVisibleGroups();
    if (!mounted) return;
    setState(() => _visibleGroups = groups);
  }

  // ============================================================
  // データ取得
  // ============================================================

  /// 表示中の月のイベントデータを全て並行取得する
  ///
  /// 取得するデータ：
  /// 1. マーケットイベント（FOMC・SQ・祝日等）
  /// 2. 日経平均月次データ
  /// 3. ウォッチリスト銘柄のイベント（決算・配当落ち日）
  ///
  /// Future.waitで並行取得してパフォーマンスを最適化している。
  Future<void> _loadAllEvents() async {
    setState(() => _isLoading = true);

    try {
      final year = _focusedMonth.year;
      final month = _focusedMonth.month;

      // ウォッチリストの銘柄コード一覧を取得
      final codes = await WatchlistService.getCodes();

      // 並行取得するFutureのリスト
      final futures = <Future>[
        StockService.getMarketEvents(year, month), // マーケットイベント
        StockService.getNikkeiMonthly(year, month), // 日経平均月次データ
        if (codes.isNotEmpty) StockService.getStockEvents(codes), // 銘柄イベント
      ];

      final results = await Future.wait(futures);

      setState(() {
        _marketEvents = results[0] as List<Map<String, dynamic>>;
        _nikkeiData = results[1] as Map<String, dynamic>;
        // ウォッチリストが空の場合は銘柄イベントを取得していないため空リスト
        _stockEvents = codes.isNotEmpty
            ? results[2] as List<Map<String, dynamic>>
            : [];
      });
    } catch (e) {
      debugPrint('スケジュール取得エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 「直近の予定」用のデータを取得する
  ///
  /// 今日以降のマーケットイベントを数ヶ月分まとめて取得する。
  /// 銘柄イベント（決算・配当）は _stockEvents に既に入っている。
  /// 一度取得したらタブを切り替えても再取得しない。
  Future<void> _loadUpcoming({bool force = false}) async {
    if (_upcomingLoaded && !force) return;
    setState(() => _isLoading = true);
    try {
      final events = await StockService.getUpcomingEvents(months: 6);
      if (!mounted) return;
      setState(() {
        _upcomingMarketEvents = events;
        _upcomingLoaded = true;
      });
    } catch (e) {
      debugPrint('直近の予定取得エラー: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // ユーティリティ
  // ============================================================

  /// DateTimeを「YYYY-MM-DD」形式の文字列に変換する
  ///
  /// イベントデータのdate文字列との比較に使用する。
  String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  /// イベントカラー名をColorに変換する
  ///
  /// バックエンドからは文字列でカラー名が返ってくるため
  /// このマップで対応するFlutterのColorに変換する。
  Color _eventColor(String colorName) {
    const map = {
      'red': Colors.red,
      'blue': Colors.blue,
      'green': Colors.green,
      'orange': Colors.orange,
      'deepOrange': Colors.deepOrange,
      'purple': Colors.purple,
      'teal': Colors.teal,
      'indigo': Colors.indigo,
      'brown': Colors.brown,
      'pink': Colors.pink,
      'blueGrey': Colors.blueGrey,
      'amber': Colors.amber,
      'grey': Colors.grey,
    };
    return map[colorName] ?? Colors.grey;
  }

  /// フィルタで表示ONになっているイベントかどうか
  ///
  /// 未知のtype（バックエンドに新しい種別が増えた場合）は
  /// 消えてしまわないよう表示する側に倒す。
  bool _isVisible(Map<String, dynamic> event) {
    final group = groupOfType(event['type']?.toString());
    if (group == null) return true;
    return _visibleGroups.contains(group.key);
  }

  /// フィルタを適用したイベントリストを返す
  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> events) =>
      events.where(_isVisible).toList();

  /// 日付文字列から「あと◯日」のラベルを作る
  String _daysToLabel(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return '';
    final now = DateTime.now();
    final days = date.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days < 0) return '終了';
    if (days == 0) return '今日';
    if (days == 1) return '明日';
    return 'あと$days日';
  }

  /// 指定日のイベント一覧を返す（マーケット＋銘柄／フィルタ適用済み）
  List<Map<String, dynamic>> _eventsForDay(DateTime day) {
    final dateStr = _fmt(day);
    final market = _marketEvents.where((e) => e['date'] == dateStr).toList();
    final stock = _stockEvents.where((e) => e['date'] == dateStr).toList();
    return _applyFilter([...market, ...stock]);
  }

  /// 表示中の月の全イベントを日付順にグループ化して返す
  ///
  /// カレンダー下部のイベント一覧表示に使用する。
  List<MapEntry<String, List<Map<String, dynamic>>>> _allEventsThisMonth() {
    final prefix =
        '${_focusedMonth.year}-'
        '${_focusedMonth.month.toString().padLeft(2, '0')}';

    // 当月の銘柄イベントだけ抽出
    final stock = _stockEvents
        .where((e) => (e['date'] as String).startsWith(prefix))
        .toList();

    // マーケットイベントと銘柄イベントをマージして日付でグループ化
    final all = _applyFilter([..._marketEvents, ...stock]);
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final e in all) {
      grouped.putIfAbsent(e['date'] as String, () => []).add(e);
    }

    // 日付順にソート
    return grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  }

  // ============================================================
  // build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // 全表示でない場合はフィルタアイコンに印を付けて気づけるようにする
    final isFiltered = _visibleGroups.length != kAllEventGroupKeys.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('スケジュール'),
        actions: [
          IconButton(
            tooltip: '表示するイベントを選ぶ',
            icon: Badge(
              isLabelVisible: isFiltered,
              backgroundColor: Colors.orange,
              smallSize: 8,
              child: const Icon(Icons.filter_alt_outlined),
            ),
            onPressed: _showFilterSheet,
          ),
          IconButton(
            tooltip: '再読み込み',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadAllEvents();
              _loadUpcoming(force: true);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // APIエラーバナー（エラーの時だけ表示）
          if (!widget.apiAvailable) ApiErrorBanner(message: widget.apiErrorMsg),

          // 表示モード切替（カレンダー / 直近の予定）
          _buildModeSwitch(),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _showUpcoming
                ? _buildUpcomingView()
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildCalendar(),
                        const Divider(height: 1),
                        _buildEventList(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 表示モード切替
  // ============================================================

  /// 「カレンダー」「直近の予定」を切り替えるセグメントコントロール
  Widget _buildModeSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            icon: Icon(Icons.calendar_month, size: 18),
            label: Text('カレンダー'),
          ),
          ButtonSegment(
            value: true,
            icon: Icon(Icons.event_available, size: 18),
            label: Text('直近の予定'),
          ),
        ],
        selected: {_showUpcoming},
        showSelectedIcon: false,
        onSelectionChanged: (selected) {
          setState(() => _showUpcoming = selected.first);
          if (_showUpcoming) _loadUpcoming();
        },
      ),
    );
  }

  // ============================================================
  // 表示フィルタ
  // ============================================================

  /// 表示するイベント種別を選ぶボトムシート
  ///
  /// 選択内容はSharedPreferencesに保存され、次回起動時も維持される。
  Future<void> _showFilterSheet() async {
    // シート内で編集する一時的なコピー（キャンセルしても元に戻せるようにする）
    final selected = Set<String>.from(_visibleGroups);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.filter_alt, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      '表示するイベント',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setSheetState(
                        () => selected
                          ..clear()
                          ..addAll(kAllEventGroupKeys),
                      ),
                      child: const Text('全て表示'),
                    ),
                  ],
                ),
                Text(
                  'カレンダーと直近の予定の両方に反映されます',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: kEventGroups.map((g) {
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: selected.contains(g.key),
                          activeColor: g.color,
                          title: Row(
                            children: [
                              Text(g.emoji),
                              const SizedBox(width: 8),
                              Text(
                                g.label,
                                style: const TextStyle(fontSize: 14),
                              ),
                              if (g.isStockEvent) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '（ウォッチリスト）',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          onChanged: (on) => setSheetState(() {
                            if (on == true) {
                              selected.add(g.key);
                            } else {
                              selected.remove(g.key);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('この内容で表示'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _visibleGroups = selected);
    await EventFilterService.saveVisibleGroups(selected);
  }

  // ============================================================
  // 直近の予定ビュー
  // ============================================================

  /// 今日以降のイベントを、種別で絞り込んで日付順に表示する
  ///
  /// 「FOMCの次はいつか」をカレンダーをめくらずに確認できるようにするのが目的。
  Widget _buildUpcomingView() {
    final events = _upcomingEvents();

    return Column(
      children: [
        // 種別チップ（タップで1種別だけに絞る／もう一度タップで解除）
        _buildUpcomingChips(),
        const Divider(height: 1),
        Expanded(
          child: events.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _visibleGroups.isEmpty
                          ? '表示するイベントが選ばれていません。\n右上のフィルタから選んでください。'
                          : '直近の予定はありません',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _buildUpcomingRow(events[index]),
                ),
        ),
      ],
    );
  }

  /// 「直近の予定」に出すイベントを組み立てる
  ///
  /// マーケットイベント（今日以降・数ヶ月分）と
  /// ウォッチリスト銘柄のイベント（決算・配当落ち日）をマージして
  /// フィルタ・絞り込みを適用し、日付順に並べる。
  List<Map<String, dynamic>> _upcomingEvents() {
    final now = DateTime.now();
    final todayStr = _fmt(DateTime(now.year, now.month, now.day));

    // 銘柄イベントは今日以降のものだけ
    final stock = _stockEvents
        .where((e) => (e['date']?.toString() ?? '').compareTo(todayStr) >= 0)
        .toList();

    var all = _applyFilter([..._upcomingMarketEvents, ...stock]);

    // チップで1種別に絞っている場合
    if (_upcomingFilterKey != null) {
      all = all
          .where((e) => groupOfType(e['type']?.toString())?.key == _upcomingFilterKey)
          .toList();
    }

    all.sort((a, b) => (a['date'] ?? '').toString().compareTo(
      (b['date'] ?? '').toString(),
    ));
    return all;
  }

  /// 種別を1つに絞り込むチップ列
  Widget _buildUpcomingChips() {
    // フィルタでONになっているグループだけをチップに出す
    final groups =
        kEventGroups.where((g) => _visibleGroups.contains(g.key)).toList();

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: const Text('すべて', style: TextStyle(fontSize: 12)),
              selected: _upcomingFilterKey == null,
              onSelected: (_) => setState(() => _upcomingFilterKey = null),
            ),
          ),
          ...groups.map(
            (g) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(
                  '${g.emoji} ${g.label}',
                  style: const TextStyle(fontSize: 12),
                ),
                selected: _upcomingFilterKey == g.key,
                selectedColor: g.color.withOpacity(0.25),
                onSelected: (on) => setState(
                  () => _upcomingFilterKey = on ? g.key : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 「直近の予定」の1行
  Widget _buildUpcomingRow(Map<String, dynamic> event) {
    final dateStr = event['date']?.toString() ?? '';
    final date = DateTime.tryParse(dateStr);
    final group = groupOfType(event['type']?.toString());
    final color = group?.color ?? _eventColor(event['color']?.toString() ?? '');
    final label = event['label']?.toString() ?? group?.label ?? 'イベント';
    final daysLabel = _daysToLabel(dateStr);

    // 7日以内は強調して「近い」と分かるようにする
    final isSoon =
        date != null &&
        date
                .difference(
                  DateTime(
                    DateTime.now().year,
                    DateTime.now().month,
                    DateTime.now().day,
                  ),
                )
                .inDays <=
            7;

    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];

    return ListTile(
      dense: true,
      leading: Container(
        width: 4,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      title: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        date == null
            ? dateStr
            : '${date.month}月${date.day}日（${weekdays[date.weekday - 1]}）',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSoon
              ? color.withOpacity(0.15)
              : Colors.grey.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          daysLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSoon ? FontWeight.bold : FontWeight.normal,
            color: isSoon ? color : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // カレンダーUI
  // ============================================================

  /// カレンダー全体を構築する
  ///
  /// 月ナビゲーション・曜日ヘッダー・日付グリッド・凡例を含む。
  Widget _buildCalendar() {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // 月の最初の日が何曜日か（日曜=0に変換）
    final startWeekday = firstDay.weekday % 7;

    return Column(
      children: [
        // 月ナビゲーション（＜ 2024年4月 ＞）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() => _focusedMonth = DateTime(year, month - 1, 1));
                  _loadAllEvents();
                },
              ),
              Text(
                '$year年$month月',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() => _focusedMonth = DateTime(year, month + 1, 1));
                  _loadAllEvents();
                },
              ),
            ],
          ),
        ),

        // 曜日ヘッダー（日〜土）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: ['日', '月', '火', '水', '木', '金', '土'].map((w) {
              // 日曜=赤・土曜=青・平日=黒
              Color c = Colors.black87;
              if (w == '日') c = Colors.red;
              if (w == '土') c = Colors.blue;
              return Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: c,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 4),

        // カレンダーグリッド（7列×N行）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.65,
            ),
            itemCount: startWeekday + daysInMonth,
            itemBuilder: (context, index) {
              // 月初より前のセルは空白
              if (index < startWeekday) return const SizedBox();

              final day = index - startWeekday + 1;
              final date = DateTime(year, month, day);
              final events = _eventsForDay(date);
              final now = DateTime.now();
              final isToday =
                  date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;

              return GestureDetector(
                // イベントがある日はタップで詳細モーダルを表示
                onTap: events.isNotEmpty
                    ? () => _showDayEvents(date, events)
                    : null,
                child: Container(
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    // 今日はブルーの背景＋枠線
                    color: isToday ? Colors.blue.withOpacity(0.15) : null,
                    borderRadius: BorderRadius.circular(6),
                    border: isToday
                        ? Border.all(color: Colors.blue, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),

                      // 日付数字
                      Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isToday
                              ? FontWeight.bold
                              : FontWeight.normal,
                          // 日曜=赤・土曜=青・平日=黒
                          color: date.weekday == DateTime.sunday
                              ? Colors.red
                              : date.weekday == DateTime.saturday
                              ? Colors.blue
                              : Colors.black87,
                        ),
                      ),

                      // 日経平均の騰落表示
                      // 赤=上昇・緑=下落、色の濃さで変動幅を表現
                      _buildNikkeiCell(date),

                      // イベントドット（最大3個＋超過数）
                      Wrap(
                        spacing: 1,
                        children: events.take(3).map((e) {
                          return Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(top: 1),
                            decoration: BoxDecoration(
                              color: _eventColor(e['color'] as String),
                              shape: BoxShape.circle,
                            ),
                          );
                        }).toList(),
                      ),
                      if (events.length > 3)
                        Text(
                          '+${events.length - 3}',
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // 凡例
        _buildLegend(),
        const SizedBox(height: 8),
      ],
    );
  }

  /// カレンダーセル内の日経平均騰落を表示するWidgetを構築する
  ///
  /// データがない日（休場日等）は空のSizedBoxを返す。
  /// 変動率が大きいほど色が濃くなる（最大±3%を基準）。
  Widget _buildNikkeiCell(DateTime date) {
    final nk = _nikkeiData[_fmt(date)];
    if (nk == null) return const SizedBox();

    final change = (nk['change'] as num).toDouble();
    final changePct = (nk['change_pct'] as num).toDouble();

    // 変動率に応じて色の透明度を調整（±3%で最大濃度）
    final intensity = (changePct.abs() / 3.0).clamp(0.2, 1.0);
    final color = change >= 0
        ? Colors.red.withOpacity(intensity) // 上昇=赤
        : Colors.green.withOpacity(intensity); // 下落=緑

    final sign = change >= 0 ? '+' : '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 1),
      padding: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        '$sign${changePct.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// カレンダーの凡例を構築する
  ///
  /// 日経平均の色の説明とイベントドットの色の説明を表示する。
  Widget _buildLegend() {
    // イベント種別と対応するカラー名の一覧
    final legends = [
      ('決算', 'red'),
      ('配当落ち', 'blue'),
      ('SQ', 'orange'),
      ('メジャーSQ', 'deepOrange'),
      ('日銀', 'brown'),
      ('FOMC', 'purple'),
      ('雇用統計', 'teal'),
      ('権利落ち', 'indigo'),
      ('満月', 'amber'),
      ('新月', 'grey'),
      ('祝日', 'pink'),
      ('米休場', 'blueGrey'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日経平均の騰落の説明
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                // 上昇サンプル
                Container(
                  width: 28,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Center(
                    child: Text(
                      '+1.2%',
                      style: TextStyle(
                        fontSize: 7,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  '上昇',
                  style: TextStyle(fontSize: 10, color: Colors.red),
                ),
                const SizedBox(width: 12),
                // 下落サンプル
                Container(
                  width: 28,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Center(
                    child: Text(
                      '-1.2%',
                      style: TextStyle(
                        fontSize: 7,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  '下落',
                  style: TextStyle(fontSize: 10, color: Colors.green),
                ),
                const SizedBox(width: 4),
                const Text(
                  '← 日経平均の騰落（色が濃いほど変動大）',
                  style: TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ),
          ),

          // イベントドットの凡例
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: legends.map((l) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _eventColor(l.$2),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    l.$1,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // イベント一覧UI
  // ============================================================

  /// カレンダー下部の月間イベント一覧を構築する
  ///
  /// 日付ごとにグループ化してリスト表示する。
  Widget _buildEventList() {
    final events = _allEventsThisMonth();

    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text('イベントなし', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final entry = events[index];
        final dateStr = entry.key;
        final dayEvents = entry.value;
        final dt = DateTime.parse(dateStr);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 日付・曜日
              SizedBox(
                width: 44,
                child: Column(
                  children: [
                    Text(
                      '${dt.day}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      ['日', '月', '火', '水', '木', '金', '土'][dt.weekday % 7],
                      style: TextStyle(
                        fontSize: 11,
                        color: dt.weekday == DateTime.sunday
                            ? Colors.red
                            : dt.weekday == DateTime.saturday
                            ? Colors.blue
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // イベント一覧
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: dayEvents.map((e) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _eventColor(e['color'] as String),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              e['label'] as String,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // 日付タップ時のモーダル
  // ============================================================

  /// 日付をタップした時のイベント詳細モーダルを表示する
  ///
  /// 日経平均のデータがある日はカード形式で騰落を表示する。
  /// その下にその日のイベント一覧を表示する。
  void _showDayEvents(DateTime date, List<Map<String, dynamic>> events) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 日付ヘッダー
            Text(
              '${date.year}年${date.month}月${date.day}日',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // 日経平均カード（データがある日のみ表示）
            _buildNikkeiDetailCard(date),

            // イベント一覧
            ...events.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _eventColor(e['color'] as String),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        e['label'] as String,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// モーダル内の日経平均詳細カードを構築する
  ///
  /// データがない日は空のSizedBoxを返す。
  Widget _buildNikkeiDetailCard(DateTime date) {
    final nk = _nikkeiData[_fmt(date)];
    if (nk == null) return const SizedBox();

    final change = (nk['change'] as num).toDouble();
    final changePct = (nk['change_pct'] as num).toDouble();
    final close = (nk['close'] as num).toDouble();
    final isPlus = change >= 0;
    final sign = isPlus ? '+' : '';
    final color = isPlus ? Colors.red : Colors.green;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '📈 日経平均',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 終値
                Text(
                  '¥${close.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: color,
                  ),
                ),
                // 前日比（円＋%）
                Text(
                  '$sign${change.toStringAsFixed(0)}円  '
                  '$sign${changePct.toStringAsFixed(2)}%',
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
