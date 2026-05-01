// ============================================================
// YoutubeDetailScreen
// YouTube動画のAI要約詳細を表示する画面。
//
// 表示する情報：
// ・動画タイトル・投稿日時
// ・センチメントバッジ（超強気〜超弱気）
// ・AI要約テキスト
// ・日経平均・米国市場の見通し
// ・推奨アクション（買い/売り/保有/注目）
// ・AI信頼度（1〜5段階）
// ・話題のトピック・言及銘柄
// ・YouTubeリンク
//
// 遷移元：YoutubeVideoListScreen（動画一覧）
// ============================================================

import 'package:flutter/material.dart';

class YoutubeDetailScreen extends StatelessWidget {
  /// YoutubeVideoListScreenから渡される要約データ
  /// summary・sentiment・nikkei_outlook等のキーを含むMap
  final Map<String, dynamic> summary;

  const YoutubeDetailScreen({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;

    return Scaffold(
      appBar: AppBar(
        title: Text(s['channel_name'] ?? '', overflow: TextOverflow.ellipsis),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 動画タイトル
            Text(
              s['title'] ?? '',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),

            // 投稿日時（存在する場合のみ表示）
            if ((s['published_at'] ?? '').isNotEmpty)
              Text(
                _formatDate(s['published_at']),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const SizedBox(height: 12),

            // センチメントバッジ（超強気〜超弱気）
            _sentimentBadge(s['sentiment'] ?? 'neutral'),
            const SizedBox(height: 16),

            // AI要約テキスト
            const Text(
              '📝 要約',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              s['summary'] ?? '',
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 16),

            const Divider(),
            const SizedBox(height: 12),

            // 日経平均の見通し
            _outlookRow(
              icon: Icons.show_chart,
              label: '日経平均',
              outlook: s['nikkei_outlook'] ?? 'not_mentioned',
              reason: s['nikkei_reason'] ?? '',
            ),
            const SizedBox(height: 10),

            // 米国市場の見通し
            _outlookRow(
              icon: Icons.language,
              label: '米国市場',
              outlook: s['us_market_outlook'] ?? 'not_mentioned',
              reason: '',
            ),
            const SizedBox(height: 10),

            // 推奨アクション（買い/売り/保有/注目/言及なし）
            _actionRow(s['recommended_action'] ?? 'not_mentioned'),
            const SizedBox(height: 16),

            // AI信頼度バー（1〜5段階）
            _confidenceBar(s['confidence'] ?? 0),
            const SizedBox(height: 16),

            // 話題のトピック（存在する場合のみ表示）
            if ((s['topics'] as List?)?.isNotEmpty == true) ...[
              const Text(
                '💬 話題',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: (s['topics'] as List)
                    .map(
                      (t) => Chip(
                        label: Text(
                          t.toString(),
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: Colors.blue.shade50,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],

            // 言及銘柄（存在する場合のみ表示）
            if ((s['key_stocks'] as List?)?.isNotEmpty == true) ...[
              const Text(
                '📈 言及銘柄',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: (s['key_stocks'] as List)
                    .map(
                      (t) => Chip(
                        label: Text(
                          t.toString(),
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: Colors.orange.shade50,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],

            // YouTubeリンクボタン（URLが存在する場合のみ表示）
            if ((s['url'] ?? '').isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // TODO: url_launcherでYouTubeを開く実装を追加する
                  },
                  icon: const Icon(Icons.play_circle, color: Colors.red),
                  label: const Text(
                    'YouTubeで見る',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ユーティリティ
  // ============================================================

  /// ISO 8601形式の日付文字列を「YYYY/MM/DD HH:MM」形式に変換する
  ///
  /// パース失敗時は元の文字列をそのまま返す。
  /// 例：「2024-01-15T09:00:00Z」→「2024/01/15 09:00」
  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  // ============================================================
  // UIパーツ
  // ============================================================

  /// センチメントバッジを構築する
  ///
  /// AIが判断した動画全体の強気・弱気度を色付きバッジで表示する。
  /// 値は「very_bullish・bullish・neutral・bearish・very_bearish」の5段階。
  ///
  /// 日本株の慣例と逆になっている点に注意：
  /// 強気（bullish）= 緑、弱気（bearish）= 赤
  /// （YouTube要約はAIが英語基準で出力するため）
  Widget _sentimentBadge(String sentiment) {
    final map = {
      'very_bullish': ('超強気', Colors.green.shade700),
      'bullish': ('強気', Colors.green),
      'neutral': ('中立', Colors.grey),
      'bearish': ('弱気', Colors.orange),
      'very_bearish': ('超弱気', Colors.red),
    };
    final (label, color) = map[sentiment] ?? ('不明', Colors.grey);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 相場見通し行を構築する（日経平均・米国市場用）
  ///
  /// 「言及なし（not_mentioned）」の場合はグレーバーで表示する。
  /// bullish=上昇・bearish=下落・neutral=横ばい
  ///
  /// [icon]    行頭のアイコン
  /// [label]   行のラベル（「日経平均」「米国市場」等）
  /// [outlook] 見通しの値（bullish/bearish/neutral/not_mentioned）
  /// [reason]  見通しの理由（任意）
  Widget _outlookRow({
    required IconData icon,
    required String label,
    required String outlook,
    required String reason,
  }) {
    final map = {
      'bullish': ('↑ 上昇', Colors.green),
      'bearish': ('↓ 下落', Colors.red),
      'neutral': ('→ 横ばい', Colors.orange),
      'not_mentioned': null, // 言及なしの場合はnull
    };
    final entry = map[outlook];

    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        if (entry == null) ...[
          // 言及なし：グレーのバーで表示
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '言及なし',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ] else ...[
          // 見通しあり：色付きバッジ＋理由テキスト
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: entry.$2.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.$1,
              style: TextStyle(
                color: entry.$2,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reason,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// 推奨アクション行を構築する
  ///
  /// AIが判断した推奨アクションをアイコン付きバッジで表示する。
  /// 「言及なし（not_mentioned）」の場合はグレーバーで表示する。
  Widget _actionRow(String action) {
    final map = {
      'buy': ('買い推奨', Colors.green, Icons.arrow_upward),
      'sell': ('売り推奨', Colors.red, Icons.arrow_downward),
      'hold': ('保有継続', Colors.blue, Icons.pause),
      'watch': ('要注目', Colors.orange, Icons.visibility),
      'not_mentioned': null, // 言及なしの場合はnull
    };
    final entry = map[action];

    return Row(
      children: [
        const Icon(Icons.recommend, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        const SizedBox(
          width: 70,
          child: Text(
            '推奨アクション',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        if (entry == null) ...[
          // 言及なし：グレーのバー
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '言及なし',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ] else
          // アクションあり：アイコン付きバッジ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: entry.$2.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(entry.$3, size: 12, color: entry.$2),
                const SizedBox(width: 4),
                Text(
                  entry.$1,
                  style: TextStyle(
                    color: entry.$2,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// AI信頼度バーを構築する（1〜5段階）
  ///
  /// 塗りつぶし円（●）と空円（○）で信頼度を視覚的に表示する。
  /// 例：信頼度3 → ●●●○○
  ///
  /// [confidence] 信頼度（1〜5の整数、またはその文字列）
  Widget _confidenceBar(dynamic confidence) {
    // int・String両方に対応
    final int level = (confidence is int)
        ? confidence
        : int.tryParse(confidence.toString()) ?? 0;

    return Row(
      children: [
        const Icon(Icons.bar_chart, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        const SizedBox(
          width: 70,
          child: Text(
            '信頼度',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        // 5つの円アイコンで信頼度を表示
        ...List.generate(
          5,
          (i) => Icon(
            i < level ? Icons.circle : Icons.circle_outlined,
            size: 14,
            // 塗りつぶし部分は青、空の部分はグレー
            color: i < level ? Colors.blue : Colors.grey.shade300,
          ),
        ),
      ],
    );
  }
}
