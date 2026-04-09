import 'package:flutter/material.dart';

class YoutubeDetailScreen extends StatelessWidget {
  final Map<String, dynamic> summary;

  const YoutubeDetailScreen({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Scaffold(
      appBar: AppBar(
        title: Text(s["channel_name"] ?? "", overflow: TextOverflow.ellipsis),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // タイトル
            Text(
              s["title"] ?? "",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),

            // 投稿日時
            if ((s["published_at"] ?? "").isNotEmpty)
              Text(
                _formatDate(s["published_at"]),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const SizedBox(height: 12),

            // センチメントバッジ
            _sentimentBadge(s["sentiment"] ?? "neutral"),
            const SizedBox(height: 16),

            // 要約
            const Text(
              "📝 要約",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              s["summary"] ?? "",
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 16),

            const Divider(),
            const SizedBox(height: 12),

            // 日経平均
            _outlookRow(
              icon: Icons.show_chart,
              label: "日経平均",
              outlook: s["nikkei_outlook"] ?? "not_mentioned",
              reason: s["nikkei_reason"] ?? "",
            ),
            const SizedBox(height: 10),

            // 米国市場
            _outlookRow(
              icon: Icons.language,
              label: "米国市場",
              outlook: s["us_market_outlook"] ?? "not_mentioned",
              reason: "",
            ),
            const SizedBox(height: 10),

            // 推奨アクション
            _actionRow(s["recommended_action"] ?? "not_mentioned"),
            const SizedBox(height: 16),

            // 信頼度
            _confidenceBar(s["confidence"] ?? 0),
            const SizedBox(height: 16),

            // トピック
            if ((s["topics"] as List?)?.isNotEmpty == true) ...[
              const Text(
                "💬 話題",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: (s["topics"] as List)
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

            // 言及銘柄
            if ((s["key_stocks"] as List?)?.isNotEmpty == true) ...[
              const Text(
                "📈 言及銘柄",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: (s["key_stocks"] as List)
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

            // YouTubeリンク
            if ((s["url"] ?? "").isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.play_circle, color: Colors.red),
                  label: const Text(
                    "YouTubeで見る",
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return "${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} "
          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return iso;
    }
  }

  Widget _sentimentBadge(String sentiment) {
    final map = {
      "very_bullish": ("超強気", Colors.green.shade700),
      "bullish": ("強気", Colors.green),
      "neutral": ("中立", Colors.grey),
      "bearish": ("弱気", Colors.orange),
      "very_bearish": ("超弱気", Colors.red),
    };
    final (label, color) = map[sentiment] ?? ("不明", Colors.grey);
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

  Widget _outlookRow({
    required IconData icon,
    required String label,
    required String outlook,
    required String reason,
  }) {
    final map = {
      "bullish": ("↑ 上昇", Colors.green),
      "bearish": ("↓ 下落", Colors.red),
      "neutral": ("→ 横ばい", Colors.orange),
      "not_mentioned": null,
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
            "言及なし",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ] else ...[
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _actionRow(String action) {
    final map = {
      "buy": ("買い推奨", Colors.green, Icons.arrow_upward),
      "sell": ("売り推奨", Colors.red, Icons.arrow_downward),
      "hold": ("保有継続", Colors.blue, Icons.pause),
      "watch": ("要注目", Colors.orange, Icons.visibility),
      "not_mentioned": null,
    };
    final entry = map[action];
    return Row(
      children: [
        const Icon(Icons.recommend, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        const SizedBox(
          width: 70,
          child: Text(
            "推奨アクション",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        if (entry == null) ...[
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
            "言及なし",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ] else
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

  Widget _confidenceBar(dynamic confidence) {
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
            "信頼度",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        ...List.generate(
          5,
          (i) => Icon(
            i < level ? Icons.circle : Icons.circle_outlined,
            size: 14,
            color: i < level ? Colors.blue : Colors.grey.shade300,
          ),
        ),
      ],
    );
  }
}
