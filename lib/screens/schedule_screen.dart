import 'package:flutter/material.dart';
import '../services/stock_service.dart';
import '../services/watchlist_service.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _focusedMonth = DateTime.now();
  List<Map<String, dynamic>> _stockEvents = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStockEvents();
  }

  Future<void> _loadStockEvents() async {
    setState(() => _isLoading = true);
    try {
      final codes = await WatchlistService.getCodes();
      if (codes.isNotEmpty) {
        final events = await StockService.getStockEvents(codes);
        setState(() => _stockEvents = events);
      }
    } catch (e) {
      print('スケジュール取得エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── マーケットイベント（固定データ）──
  List<Map<String, dynamic>> _getMarketEvents(int year, int month) {
    final events = <Map<String, dynamic>>[];

    // 日本の祝日2025-2026
    final holidays = {
      '2025-01-01': '元日',
      '2025-01-13': '成人の日',
      '2025-02-11': '建国記念の日',
      '2025-02-23': '天皇誕生日',
      '2025-03-20': '春分の日',
      '2025-04-29': '昭和の日',
      '2025-05-03': '憲法記念日',
      '2025-05-04': 'みどりの日',
      '2025-05-05': 'こどもの日',
      '2025-07-21': '海の日',
      '2025-08-11': '山の日',
      '2025-09-15': '敬老の日',
      '2025-09-23': '秋分の日',
      '2025-10-13': 'スポーツの日',
      '2025-11-03': '文化の日',
      '2025-11-23': '勤労感謝の日',
      '2026-01-01': '元日',
      '2026-01-12': '成人の日',
      '2026-02-11': '建国記念の日',
      '2026-02-23': '天皇誕生日',
      '2026-03-20': '春分の日',
      '2026-04-29': '昭和の日',
      '2026-05-03': '憲法記念日',
      '2026-05-04': 'みどりの日',
      '2026-05-05': 'こどもの日',
      '2026-07-20': '海の日',
      '2026-08-11': '山の日',
      '2026-09-21': '敬老の日',
      '2026-09-23': '秋分の日',
      '2026-10-12': 'スポーツの日',
      '2026-11-03': '文化の日',
      '2026-11-23': '勤労感謝の日',
    };

    // 米国市場休場日2025-2026
    final usHolidays = {
      '2025-01-01': '米市場休場(元日)',
      '2025-01-20': '米市場休場(MLKの日)',
      '2025-02-17': '米市場休場(大統領の日)',
      '2025-04-18': '米市場休場(聖金曜日)',
      '2025-05-26': '米市場休場(メモリアルデー)',
      '2025-06-19': '米市場休場(奴隷解放記念日)',
      '2025-07-04': '米市場休場(独立記念日)',
      '2025-09-01': '米市場休場(労働者の日)',
      '2025-11-27': '米市場休場(感謝祭)',
      '2025-12-25': '米市場休場(クリスマス)',
      '2026-01-01': '米市場休場(元日)',
      '2026-01-19': '米市場休場(MLKの日)',
      '2026-02-16': '米市場休場(大統領の日)',
      '2026-04-03': '米市場休場(聖金曜日)',
      '2026-05-25': '米市場休場(メモリアルデー)',
      '2026-06-19': '米市場休場(奴隷解放記念日)',
      '2026-07-03': '米市場休場(独立記念日)',
      '2026-09-07': '米市場休場(労働者の日)',
      '2026-11-26': '米市場休場(感謝祭)',
      '2026-12-25': '米市場休場(クリスマス)',
    };

    // SQ・メジャーSQ（毎月第2金曜・3月6月9月12月がメジャー）
    final sqDates = _getSqDates(year, month);
    for (final d in sqDates) {
      final isMajor = [3, 6, 9, 12].contains(d.month);
      events.add({
        'date': _fmt(d),
        'label': isMajor ? 'メジャーSQ' : 'SQ',
        'type': isMajor ? 'major_sq' : 'sq',
        'color': isMajor ? 'deepOrange' : 'orange',
      });
    }

    // 日銀金融政策決定会合 2025-2026
    final bojDates = {
      '2025-01-23',
      '2025-01-24',
      '2025-03-18',
      '2025-03-19',
      '2025-04-30',
      '2025-05-01',
      '2025-06-16',
      '2025-06-17',
      '2025-07-30',
      '2025-07-31',
      '2025-09-18',
      '2025-09-19',
      '2025-10-28',
      '2025-10-29',
      '2025-12-18',
      '2025-12-19',
      '2026-01-22',
      '2026-01-23',
      '2026-03-18',
      '2026-03-19',
      '2026-04-27',
      '2026-04-28',
      '2026-06-15',
      '2026-06-16',
      '2026-07-29',
      '2026-07-30',
      '2026-09-16',
      '2026-09-17',
      '2026-10-27',
      '2026-10-28',
      '2026-12-17',
      '2026-12-18',
    };

    // FOMC 2025-2026
    final fomcDates = {
      '2025-01-28',
      '2025-01-29',
      '2025-03-18',
      '2025-03-19',
      '2025-05-06',
      '2025-05-07',
      '2025-06-17',
      '2025-06-18',
      '2025-07-29',
      '2025-07-30',
      '2025-09-16',
      '2025-09-17',
      '2025-10-28',
      '2025-10-29',
      '2025-12-09',
      '2025-12-10',
      '2026-01-27',
      '2026-01-28',
      '2026-03-17',
      '2026-03-18',
      '2026-04-28',
      '2026-04-29',
      '2026-06-09',
      '2026-06-10',
      '2026-07-28',
      '2026-07-29',
      '2026-09-15',
      '2026-09-16',
      '2026-10-27',
      '2026-10-28',
      '2026-12-15',
      '2026-12-16',
    };

    // 米雇用統計（毎月第1金曜）
    final jobsDates = _getFirstFridays(year, month);
    for (final d in jobsDates) {
      events.add({
        'date': _fmt(d),
        'label': '米雇用統計',
        'type': 'jobs',
        'color': 'teal',
      });
    }

    // 権利落ち日（毎月最終営業日の翌日≒25日前後）
    final rightsDate = _getRightsDate(year, month);
    if (rightsDate != null) {
      events.add({
        'date': _fmt(rightsDate),
        'label': '権利落ち日',
        'type': 'rights',
        'color': 'indigo',
      });
    }

    // 満月・新月
    final moonEvents = _getMoonPhases(year, month);
    events.addAll(moonEvents);

    // 祝日
    for (final e in holidays.entries) {
      if (e.key.startsWith('$year-${month.toString().padLeft(2, '0')}')) {
        events.add({
          'date': e.key,
          'label': '🇯🇵 ${e.value}',
          'type': 'holiday_jp',
          'color': 'pink',
        });
      }
    }

    // 米国休場
    for (final e in usHolidays.entries) {
      if (e.key.startsWith('$year-${month.toString().padLeft(2, '0')}')) {
        events.add({
          'date': e.key,
          'label': '🇺🇸 ${e.value}',
          'type': 'holiday_us',
          'color': 'blueGrey',
        });
      }
    }

    // 日銀・FOMC
    for (final d in bojDates) {
      if (d.startsWith('$year-${month.toString().padLeft(2, '0')}')) {
        events.add({
          'date': d,
          'label': '日銀会合',
          'type': 'boj',
          'color': 'brown',
        });
      }
    }
    for (final d in fomcDates) {
      if (d.startsWith('$year-${month.toString().padLeft(2, '0')}')) {
        events.add({
          'date': d,
          'label': 'FOMC',
          'type': 'fomc',
          'color': 'purple',
        });
      }
    }

    return events;
  }

  // SQ日（第2金曜）
  List<DateTime> _getSqDates(int year, int month) {
    final result = <DateTime>[];
    int friCount = 0;
    for (int d = 1; d <= 31; d++) {
      try {
        final dt = DateTime(year, month, d);
        if (dt.weekday == DateTime.friday) {
          friCount++;
          if (friCount == 2) {
            result.add(dt);
            break;
          }
        }
      } catch (_) {
        break;
      }
    }
    return result;
  }

  // 第1金曜（雇用統計）
  List<DateTime> _getFirstFridays(int year, int month) {
    for (int d = 1; d <= 7; d++) {
      final dt = DateTime(year, month, d);
      if (dt.weekday == DateTime.friday) return [dt];
    }
    return [];
  }

  // 権利落ち日（月末から3営業日前≒月の最終月曜日の翌日あたり）
  DateTime? _getRightsDate(int year, int month) {
    // 月末
    final lastDay = DateTime(year, month + 1, 0);
    // 月末から3営業日前を概算
    for (int i = 0; i < 10; i++) {
      final d = lastDay.subtract(Duration(days: i));
      if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) {
        // 3営業日前
        int bizCount = 0;
        DateTime cur = lastDay;
        while (bizCount < 2) {
          cur = cur.subtract(const Duration(days: 1));
          if (cur.weekday != DateTime.saturday &&
              cur.weekday != DateTime.sunday) {
            bizCount++;
          }
        }
        return cur;
      }
    }
    return null;
  }

  // 満月・新月（近似計算）
  List<Map<String, dynamic>> _getMoonPhases(int year, int month) {
    final result = <Map<String, dynamic>>[];
    // 既知の新月基準日から計算（朔望月 = 29.53059日）
    const lunarCycle = 29.53059;
    // 2000-01-06 を基準新月とする
    final baseNewMoon = DateTime(2000, 1, 6);

    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);

    double daysSinceBase = firstDay.difference(baseNewMoon).inDays.toDouble();
    double phase = daysSinceBase % lunarCycle;
    if (phase < 0) phase += lunarCycle;

    // 今月の新月・満月を探す
    for (double d = -lunarCycle; d <= lunarCycle * 2; d += lunarCycle / 2) {
      // 新月（phase=0）
      final newMoonOffset = lunarCycle - phase + d;
      final newMoonDate = firstDay.add(Duration(days: newMoonOffset.round()));
      if (newMoonDate.month == month && newMoonDate.year == year) {
        result.add({
          'date': _fmt(newMoonDate),
          'label': '🌑 新月',
          'type': 'new_moon',
          'color': 'grey',
        });
      }
      // 満月（phase=lunarCycle/2）
      final fullMoonOffset = lunarCycle / 2 - phase + d;
      final fullMoonDate = firstDay.add(Duration(days: fullMoonOffset.round()));
      if (fullMoonDate.month == month && fullMoonDate.year == year) {
        result.add({
          'date': _fmt(fullMoonDate),
          'label': '🌕 満月',
          'type': 'full_moon',
          'color': 'amber',
        });
      }
    }
    return result;
  }

  String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

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

  // 指定日のイベント一覧
  List<Map<String, dynamic>> _eventsForDay(DateTime day) {
    final dateStr = _fmt(day);
    final market = _getMarketEvents(
      day.year,
      day.month,
    ).where((e) => e['date'] == dateStr).toList();
    final stock = _stockEvents.where((e) => e['date'] == dateStr).toList();
    return [...market, ...stock];
  }

  // 今月のすべてのイベント（日付順）
  List<MapEntry<String, List<Map<String, dynamic>>>> _allEventsThisMonth() {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;
    final market = _getMarketEvents(year, month);
    final stock = _stockEvents
        .where(
          (e) =>
              e['date'].startsWith('$year-${month.toString().padLeft(2, '0')}'),
        )
        .toList();
    final all = [...market, ...stock];

    // 日付でグループ化
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final e in all) {
      grouped.putIfAbsent(e['date'] as String, () => []).add(e);
    }
    final sorted = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("スケジュール"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStockEvents,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildCalendar(),
                  const Divider(height: 1),
                  _buildEventList(),
                ],
              ),
            ),
    );
  }

  // カレンダー部分
  Widget _buildCalendar() {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7; // 0=日曜

    return Column(
      children: [
        // 月ナビゲーション
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() {
                  _focusedMonth = DateTime(year, month - 1, 1);
                }),
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
                onPressed: () => setState(() {
                  _focusedMonth = DateTime(year, month + 1, 1);
                }),
              ),
            ],
          ),
        ),

        // 曜日ヘッダー
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: ['日', '月', '火', '水', '木', '金', '土'].map((w) {
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

        // カレンダーグリッド
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.75,
            ),
            itemCount: startWeekday + daysInMonth,
            itemBuilder: (context, index) {
              if (index < startWeekday) return const SizedBox();
              final day = index - startWeekday + 1;
              final date = DateTime(year, month, day);
              final events = _eventsForDay(date);
              final isToday =
                  date.year == DateTime.now().year &&
                  date.month == DateTime.now().month &&
                  date.day == DateTime.now().day;

              return GestureDetector(
                onTap: events.isNotEmpty
                    ? () => _showDayEvents(date, events)
                    : null,
                child: Container(
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
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
                      Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isToday
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: date.weekday == DateTime.sunday
                              ? Colors.red
                              : date.weekday == DateTime.saturday
                              ? Colors.blue
                              : Colors.black87,
                        ),
                      ),
                      // イベントドット（最大3個）
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

  // 凡例
  Widget _buildLegend() {
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
      child: Wrap(
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
    );
  }

  // 月のイベント一覧
  Widget _buildEventList() {
    final events = _allEventsThisMonth();
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text("イベントなし", style: TextStyle(color: Colors.grey)),
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
              // 日付
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

  // 日付タップ時のモーダル
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
            Text(
              '${date.year}年${date.month}月${date.day}日',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
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
}
