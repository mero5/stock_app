import 'package:flutter/material.dart';
import '../services/stock_service.dart';

class MarketScreen extends StatefulWidget {
  final bool apiAvailable;
  final String apiErrorMsg;
  const MarketScreen({
    super.key,
    this.apiAvailable = true,
    this.apiErrorMsg = '',
  });

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic> _sectorData = {"jp": [], "us": []};
  bool _isLoading = false;
  String _selectedPeriod = '5d';
  String _sectorComment = '';
  bool _isLoadingComment = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await StockService.getSectorTrends(period: _selectedPeriod);
      setState(() => _sectorData = data);
    } catch (e) {
      print('マーケットデータ取得エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadComment() async {
    setState(() => _isLoadingComment = true);
    try {
      final comment = await StockService.getSectorComment(_sectorData);
      setState(() => _sectorComment = comment);
    } finally {
      setState(() => _isLoadingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('マーケット'),
        actions: [
          ToggleButtons(
            isSelected: [_selectedPeriod == '5d', _selectedPeriod == '1mo'],
            onPressed: (i) {
              setState(() => _selectedPeriod = i == 0 ? '5d' : '1mo');
              _loadData();
            },
            borderRadius: BorderRadius.circular(8),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 32),
            children: const [
              Text('5日', style: TextStyle(fontSize: 12)),
              Text('1ヶ月', style: TextStyle(fontSize: 12)),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '🇯🇵 日本'),
            Tab(text: '🇺🇸 米国'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildSectorList('jp'), _buildSectorList('us')],
            ),
    );
  }

  Widget _buildSectorList(String market) {
    final sectors = List<Map<String, dynamic>>.from(_sectorData[market] ?? []);

    if (sectors.isEmpty) {
      return const Center(child: Text('データなし'));
    }

    // トップ上昇・下落セクター
    final topGainer = sectors.first;
    final topLoser = sectors.last;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI相場解説
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'AI相場解説',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _isLoadingComment ? null : _loadComment,
                        child: _isLoadingComment
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                '解説を取得',
                                style: TextStyle(fontSize: 12),
                              ),
                      ),
                    ],
                  ),
                  if (_sectorComment.isNotEmpty)
                    Text(
                      _sectorComment,
                      style: const TextStyle(fontSize: 12, height: 1.6),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // トレンドサマリー
          Row(
            children: [
              Expanded(
                child: _trendBadge(
                  '🔥 本日の上昇',
                  topGainer['name'],
                  topGainer['change_pct'],
                  Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _trendBadge(
                  '📉 本日の下落',
                  topLoser['name'],
                  topLoser['change_pct'],
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // セクター一覧
          const Text(
            'セクター騰落率（本日）',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...sectors.map((s) => _sectorRow(s)),
          const SizedBox(height: 20),

          // 5日トレンド
          Text(
            '${_selectedPeriod == "1mo" ? "1ヶ月" : "5日間"}トレンド',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...(() {
            final sorted = List<Map<String, dynamic>>.from(sectors)
              ..sort(
                (a, b) => (b['trend'] as num? ?? b['trend_5d'] as num? ?? 0)
                    .compareTo(
                      a['trend'] as num? ?? a['trend_5d'] as num? ?? 0,
                    ),
              );
            return sorted.map((s) => _sectorRow(s, use5d: true));
          })(),
        ],
      ),
    );
  }

  Widget _trendBadge(String label, String name, num changePct, Color color) {
    final sign = changePct >= 0 ? '+' : '';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Text(
              '$sign${changePct.toStringAsFixed(2)}%',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectorRow(Map<String, dynamic> s, {bool use5d = false}) {
    final pct = (use5d ? s['trend_5d'] : s['change_pct']) as num;
    final isUp = pct >= 0;
    final color = isUp ? Colors.red : Colors.green;
    final sign = isUp ? '+' : '';

    // バーの幅（最大±5%を100%とする）
    final barWidth = (pct.abs() / 5.0).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // セクター名
          SizedBox(
            width: 90,
            child: GestureDetector(
              onTap: () => _showSectorInfo(context, s['name']),
              child: Row(
                children: [
                  Text(
                    s['name'],
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Icon(Icons.info_outline, size: 12, color: Colors.grey),
                ],
              ),
            ),
          ),
          // バー
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: barWidth,
                  child: Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 数値
          SizedBox(
            width: 56,
            child: Text(
              '$sign${pct.toStringAsFixed(2)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSectorInfo(BuildContext context, String sectorName) {
    final info = {
      '銀行':
          '三菱UFJ・三井住友・みずほなど。\n金利が上がると貸出金利も上がり利益が増えるため、金利上昇局面で買われやすい。逆に景気後退・不良債権増加時は売られやすい。日銀の政策変更に特に敏感。',
      '電気機器':
          'ソニー・キーエンス・オムロン・日立など。\n輸出比率が高く円安になると業績が上がりやすい。半導体・AI関連の設備投資が増えると恩恵を受ける。世界の景気動向に敏感な景気敏感セクター。',
      '自動車':
          'トヨタ・ホンダ・日産・スズキなど。\n円安になると海外収益を円換算した際に増益になる。現在はEV（電気自動車）への移行期で、テスラなど海外勢との競争が激化。中国市場の動向にも注意。',
      '不動産':
          '三井不動産・住友不動産・三菱地所など。\n金利が上がると住宅ローンの負担が増え不動産需要が落ちるため逆風になりやすい。インフレ時は資産価値が上がるプラス面もある。都市部と地方で状況が異なる。',
      '食品':
          '味の素・日清食品・キッコーマンなど。\n食料品は景気が悪くても需要が落ちにくいディフェンシブセクター。ただし原材料費・物流費の上昇が利益を圧迫しやすい。円安は輸入原料コスト増につながる。',
      '医薬品':
          '武田薬品・アステラス・第一三共など。\n景気に左右されにくいディフェンシブセクター。新薬開発の成否が株価を大きく動かす。円安は海外売上の円換算増益につながる。後発薬（ジェネリック）との競争も影響。',
      '情報通信':
          'NTT・KDDI・ソフトバンクなど。\n通信インフラは生活インフラのため景気に左右されにくい。安定した配当を出す企業が多くインカム投資家に人気。5G投資など設備投資負担が大きい側面もある。',
      '素材':
          '信越化学・旭化成・住友化学など。\n素材・化学品は景気が良い時に需要が増える景気敏感セクター。原油・ナフサなどの原料価格に利益が左右されやすい。半導体材料など高付加価値品は景気に関わらず需要が強い。',
      'テクノロジー':
          'Apple・NVIDIA・Microsoft・Metaなど。\nAI・クラウド・半導体などの成長テーマを含む。景気敏感だが長期トレンドは強い。金利上昇時は将来利益の割引率が上がるため売られやすい傾向がある。',
      'ヘルスケア':
          'J&J・UnitedHealth・Eli Lillyなど。\n医療・保険・製薬を含むディフェンシブセクター。景気後退時も比較的安定。GLP-1（肥満治療薬）など新薬テーマで注目度が高い。政策変更（薬価規制など）に敏感。',
      '金融':
          'JPMorgan・Goldman Sachs・Visa・Mastercardなど。\n銀行・証券・保険・決済を含む広いセクター。金利上昇で銀行部門は恩恵、景気好調で証券・カード決済も伸びる。景気後退・信用リスク上昇で売られやすい。',
      'エネルギー':
          'ExxonMobil・Chevron・ConocoPhillipsなど。\n原油・天然ガスの価格に利益が直結する。地政学リスク（中東情勢など）で原油価格が上がると買われやすい。脱炭素・再生可能エネルギーへの移行が長期リスク。',
      '一般消費財':
          'Amazon・Tesla・Nike・Home Depotなど。\n景気が良い時に消費者が多く買い物をするため景気敏感。消費者信頼感指数や雇用統計に敏感。高金利環境では消費者ローン負担増で逆風になりやすい。',
      '生活必需品':
          'P&G・Coca-Cola・Walmart・Costcoなど。\n食料品・日用品など生活に不可欠なものを扱うディフェンシブセクター。景気後退・株式市場下落時に資金が逃げ込む「守りの銘柄」。インフレ時は価格転嫁できれば利益を守れる。',
      '公益':
          'NextEra・Duke Energy・Southern Companyなど。\n電力・ガス・水道などインフラを運営。安定した収益・配当が特徴だが、金利上昇時は配当の魅力が低下し売られやすい。再生可能エネルギーへの投資負担も大きい。',
      '通信':
          'AT&T・Verizon・T-Mobileなど。\n携帯・固定通信インフラを運営。安定した配当が特徴のディフェンシブセクター。5G設備投資の負担が重く、成長性は限定的。金利上昇時は高配当株として比較されるため売られやすい。',
      '資本財':
          'Caterpillar・Honeywell・Boeing・Deereなど。\n建設機械・航空機・産業機器など。景気拡大期・インフラ投資増加時に恩恵。製造業PMIや設備投資動向に敏感。米国の財政支出（インフラ法など）が追い風になりやすい。',
      'AI/半導体':
          'NVIDIA・AMD・Qualcomm・ASMLなど。\nAI需要の爆発的拡大で注目度が最も高いセクターの一つ。データセンター向けGPU需要がNVIDIAを中心に急拡大。高成長期待の反面、バリュエーションが高く調整も大きい高ボラティリティセクター。',
      '鉄鋼・非鉄':
          '日本製鉄・三菱マテリアル・住友金属鉱山など。\n鉄鋼・アルミ・銅などの素材を生産。中国の鉄鋼需要・資源価格に利益が直結する景気敏感セクター。インフラ投資増加時に恩恵。電気自動車向け非鉄金属（銅・リチウム）の需要増も注目。',
      '化学':
          '信越化学・旭化成・住友化学・東レなど。\n石油化学・特殊化学品・繊維など幅広い。半導体材料（信越化学のシリコンウェーハなど）は景気に関わらず需要が強い。汎用化学品は原料の原油価格変動に利益が左右されやすい。',
      '機械':
          'コマツ・ダイキン・SMC・ファナックなど。\n建設機械・空調・産業用ロボットなど。設備投資・建設需要が増える景気拡大期に買われやすい。中国の建設需要（コマツなど）への依存度が高い企業も多い。工場自動化（FA）需要は長期的に拡大傾向。',
      '小売':
          'イオン・セブン&アイ・ファーストリテイリング（ユニクロ）など。\n国内消費動向に左右される内需セクター。賃金上昇・個人消費拡大時に恩恵。ユニクロのように海外展開が進む企業は円安メリットもある。EC（ネット通販）との競争が続く。',
      'サービス':
          'リクルート・オリエンタルランド・電通など。\n人材・広告・レジャーなど幅広いサービス業。景気拡大・雇用好調時に恩恵を受けやすい。インバウンド（訪日外国人）需要の恩恵を受けるレジャー・ホテル系企業も含む。',
      '海運・空運':
          '日本郵船・商船三井・川崎汽船・ANAなど。\n国際貿易量・旅行需要に連動。コンテナ運賃・燃料費（重油・航空燃料）の変動で利益が大きく変わる。地政学リスク（スエズ運河問題など）でスポット運賃が急騰することがある。',
      '鉱業':
          '三菱マテリアル・DOWA・住友金属鉱山など。\n金・銀・銅などの資源採掘・精製。金価格上昇局面では金鉱株が大きく動く。資源ナショナリズムや採掘権リスクなど地政学的要因にも敏感。',
      '建設':
          '大林組・鹿島・清水建設・大成建設など。\n公共投資・民間設備投資の動向に連動。政府のインフラ投資・復興需要で恩恵を受ける。人手不足・資材価格高騰がコスト上昇要因。都市再開発・マンション建設の受注状況も重要。',
      '水産・農林':
          'マルハニチロ・日本水産・ニッスイなど。\n水産加工・養殖・食品を手がける。漁獲量・魚価・飼料コストに利益が左右される。健康志向の高まりで魚介類・健康食品の需要は長期的に底堅い。円安は輸入飼料コスト増につながる。',
    };

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
              sectorName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              info[sectorName] ?? 'セクター情報なし',
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
