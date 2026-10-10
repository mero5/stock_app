// ============================================================
// PriceAlertSheet
// 株価アラートを作る・直すための画面（下から出るシート）。
//
// 銘柄の詳細画面の🔔と、株価アラート一覧の各行から開く。
// ・条件：株価が○円以上／以下、前日比 ±○%（急騰・急落）
// ・繰り返し：毎日（1日1回まで）／1回だけ（通知したら OFF）
// ・今の株価と「あと何%」を出して、金額を決めやすくする
// 保存したら true を返す。初めて登録したときは iPhone の通知の許可をもらう。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/price_alert.dart';
import '../services/price_alert_service.dart';
import '../services/push_service.dart';
import '../services/stock_service.dart';
import '../utils/formatter.dart';
import '../utils/stock_code.dart';
import 'error_dialog.dart';

class PriceAlertSheet extends StatefulWidget {
  final String code;
  final String name;

  /// 直すときのアラート。新しく作るときは null
  final PriceAlert? existing;

  const PriceAlertSheet({
    super.key,
    required this.code,
    required this.name,
    this.existing,
  });

  /// シートを開く。保存したら true
  static Future<bool> show(
    BuildContext context, {
    required String code,
    required String name,
    PriceAlert? existing,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          PriceAlertSheet(code: code, name: name, existing: existing),
    );
    return saved ?? false;
  }

  @override
  State<PriceAlertSheet> createState() => _PriceAlertSheetState();
}

class _PriceAlertSheetState extends State<PriceAlertSheet> {
  late String _condition;
  late String _repeat;
  final _targetController = TextEditingController();
  double? _price;
  double? _changePct;
  bool _isSaving = false;

  bool get _isJp => StockCode.isJp(widget.code);
  bool get _isPercent => PriceAlertCondition.isPercent(_condition);

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _condition = existing?.condition ?? PriceAlertCondition.priceAbove;
    _repeat = existing?.repeat ?? PriceAlertRepeat.daily;
    if (existing != null) {
      final t = existing.target;
      _targetController.text = t == t.roundToDouble()
          ? t.toStringAsFixed(0)
          : t.toString();
    }
    _targetController.addListener(() => setState(() {}));
    _loadPrice();
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _loadPrice() async {
    final res = await StockService.getPrice(widget.code);
    if (!mounted) return;
    setState(() {
      _price = (res['price'] as num?)?.toDouble();
      _changePct = (res['change_pct'] as num?)?.toDouble();
    });
  }

  String _formatPrice(double v) => _isJp
      ? '${Formatter.number(v, decimals: v == v.roundToDouble() ? 0 : 1)}円'
      : '\$${Formatter.number(v, decimals: 2)}';

  /// 「今の株価から +3.2%」のような、目標までの距離
  String? get _distanceText {
    final target = double.tryParse(_targetController.text);
    final price = _price;
    if (target == null || price == null || price == 0 || _isPercent) {
      return null;
    }
    final pct = (target - price) / price * 100;
    return '今の株価から ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%';
  }

  Future<void> _save() async {
    final target = double.tryParse(_targetController.text);
    if (target == null || target <= 0) {
      await ErrorDialog.show(
        context,
        title: '入力を確認してください',
        message: _isPercent ? '% を数字で入れてください' : '金額を数字で入れてください',
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await PriceAlertService.create(
          code: widget.code,
          name: widget.name,
          condition: _condition,
          target: target,
          repeat: _repeat,
        );
      } else {
        await PriceAlertService.update(
          existing.alertId,
          condition: _condition,
          target: target,
          repeat: _repeat,
          // 直したら、OFF になっていたものも ON に戻す
          enabled: true,
        );
      }
      final allowed = await PushService.requestPermissionAndRegister();
      if (!mounted) return;
      if (!allowed && PushService.isSupported) {
        await ErrorDialog.show(
          context,
          title: '通知が許可されていません',
          message:
              'アラートは保存しましたが、通知が届きません。iPhone の「設定」→「通知」で、このアプリの通知を許可してください。',
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on PriceAlertException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      await ErrorDialog.show(context, message: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null ? '株価アラートを作る' : '株価アラートを直す',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.name}（${StockCode.display(widget.code)}）',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 8),
            _buildCurrentPrice(),
            const SizedBox(height: 12),
            const Text('条件', style: TextStyle(fontWeight: FontWeight.bold)),
            RadioGroup<String>(
              groupValue: _condition,
              onChanged: (v) => setState(() => _condition = v ?? _condition),
              child: Column(
                children: [
                  for (final c in PriceAlertCondition.all)
                    RadioListTile<String>(
                      value: c,
                      title: Text(PriceAlertCondition.label(c)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            TextField(
              controller: _targetController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: _isPercent ? '前日比（%）' : '株価',
                suffixText: _isPercent ? '%' : (_isJp ? '円' : 'ドル'),
                helperText: _distanceText,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _repeat == PriceAlertRepeat.once,
              onChanged: (v) => setState(
                () => _repeat = v
                    ? PriceAlertRepeat.once
                    : PriceAlertRepeat.daily,
              ),
              title: const Text('1回通知したら OFF にする'),
              subtitle: Text(
                _repeat == PriceAlertRepeat.once
                    ? '目標に届いたら1回だけ知らせます'
                    : '条件を満たしている間、1日1回まで知らせます',
                style: const TextStyle(fontSize: 12),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 4),
            const Text(
              '・市場が開いている時間に、5分おきに確認します\n'
              '・株価は最大20分ほど遅れることがあります',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存する'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPrice() {
    final price = _price;
    if (price == null) {
      return const Text(
        '今の株価：読み込み中…',
        style: TextStyle(fontSize: 13, color: Colors.black54),
      );
    }
    final change = _changePct;
    final changeText = change == null
        ? ''
        : '（前日比 ${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%）';
    return Text(
      '今の株価：${_formatPrice(price)}$changeText',
      style: const TextStyle(fontSize: 13),
    );
  }
}
