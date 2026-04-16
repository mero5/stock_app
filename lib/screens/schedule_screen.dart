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
  List<Map<String, dynamic>> _marketEvents = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAllEvents();
  }

  Future<void> _loadAllEvents() async {
    setState(() => _isLoading = true);
    try {
      final year = _focusedMonth.year;
      final month = _focusedMonth.month;
      final codes = await WatchlistService.getCodes();

      final futures = <Future>[
        StockService.getMarketEvents(year, month),
        if (codes.isNotEmpty) StockService.getStockEvents(codes),
      ];
      final results = await Future.wait(futures);

      setState(() {
        _marketEvents = results[0] as List<Map<String, dynamic>>;
        _stockEvents = codes.isNotEmpty
            ? results[1] as List<Map<String, dynamic>>
            : [];
      });
    } catch (e) {
      print('スケジュール取得エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
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

  List<Map<String, dynamic>> _eventsForDay(DateTime day) {
    final dateStr = _fmt(day);
    final market = _marketEvents.where((e) => e['date'] == dateStr).toList();
    final stock = _stockEvents.where((e) => e['date'] == dateStr).toList();
    return [...market, ...stock];
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _allEventsThisMonth() {
    final prefix =
        '${_focusedMonth.year}-'
        '${_focusedMonth.month.toString().padLeft(2, '0')}';
    final stock = _stockEvents
        .where((e) => (e['date'] as String).startsWith(prefix))
        .toList();
    final all = [..._marketEvents, ...stock];
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final e in all) {
      grouped.putIfAbsent(e['date'] as String, () => []).add(e);
    }
    return grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('スケジュール'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllEvents,
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

  Widget _buildCalendar() {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7;

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
              final now = DateTime.now();
              final isToday =
                  date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;

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
        _buildLegend(),
        const SizedBox(height: 8),
      ],
    );
  }

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
