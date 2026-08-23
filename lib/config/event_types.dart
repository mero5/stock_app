// ============================================================
// EventTypes
// スケジュール画面で扱うイベント種別の定義。
//
// バックエンドは type 文字列（fomc / sq / holiday_jp 等）で返すが、
// 画面では「SQ・メジャーSQ」「祝日・休場」のようにまとめて
// 1つのチェックボックスで扱いたいので、ここでグループ化している。
//
// 表示フィルタ・「直近の予定」の絞り込みの両方でこの定義を使う。
// ============================================================

import 'package:flutter/material.dart';

/// イベントグループ1件
class EventGroup {
  /// 保存・識別に使うキー
  final String key;

  /// 画面に出す名前
  final String label;

  /// このグループに含まれるバックエンドのtype
  final List<String> types;

  /// チップやアイコンの色
  final Color color;

  /// 見出しに添える絵文字
  final String emoji;

  /// ウォッチリスト銘柄に紐づくイベントか
  /// （true のものは銘柄名を一緒に表示する）
  final bool isStockEvent;

  const EventGroup({
    required this.key,
    required this.label,
    required this.types,
    required this.color,
    required this.emoji,
    this.isStockEvent = false,
  });
}

/// 画面で扱う全イベントグループ
///
/// 並び順がそのままフィルタ・チップの並び順になる。
/// 相場への影響が大きいものから並べている。
const List<EventGroup> kEventGroups = [
  EventGroup(
    key: 'earnings',
    label: '決算発表',
    types: ['earnings'],
    color: Colors.red,
    emoji: '📊',
    isStockEvent: true,
  ),
  EventGroup(
    key: 'fomc',
    label: 'FOMC',
    types: ['fomc'],
    color: Colors.purple,
    emoji: '🇺🇸',
  ),
  EventGroup(
    key: 'boj',
    label: '日銀会合',
    types: ['boj'],
    color: Colors.brown,
    emoji: '🇯🇵',
  ),
  EventGroup(
    key: 'sq',
    label: 'SQ・メジャーSQ',
    types: ['sq', 'major_sq'],
    color: Colors.deepOrange,
    emoji: '📈',
  ),
  EventGroup(
    key: 'jobs',
    label: '米雇用統計',
    types: ['jobs'],
    color: Colors.teal,
    emoji: '💼',
  ),
  EventGroup(
    key: 'rights',
    label: '権利落ち日',
    types: ['rights'],
    color: Colors.indigo,
    emoji: '🎁',
  ),
  EventGroup(
    key: 'dividend',
    label: '配当落ち日',
    types: ['ex_dividend'],
    color: Colors.blue,
    emoji: '💰',
    isStockEvent: true,
  ),
  EventGroup(
    key: 'holiday',
    label: '祝日・休場',
    types: ['holiday_jp', 'holiday_us'],
    color: Colors.pink,
    emoji: '🏖',
  ),
  EventGroup(
    key: 'moon',
    label: '満月・新月',
    types: ['full_moon', 'new_moon'],
    color: Colors.amber,
    emoji: '🌕',
  ),
];

/// バックエンドのtype → 所属グループ を引くための逆引き表
final Map<String, EventGroup> kTypeToGroup = {
  for (final g in kEventGroups)
    for (final t in g.types) t: g,
};

/// 全グループのキー（デフォルトは全部表示）
final Set<String> kAllEventGroupKeys = kEventGroups.map((g) => g.key).toSet();

/// typeからグループを引く（未知のtypeはnull）
EventGroup? groupOfType(String? type) =>
    type == null ? null : kTypeToGroup[type];
