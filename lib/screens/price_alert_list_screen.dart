// ============================================================
// PriceAlertListScreen
// 株価アラートの一覧（設定 → 株価アラート）。
//
// ・ON/OFF の切り替え、タップで直す、ゴミ箱で削除
// ・右上の「テスト通知」で、通知が届くかをすぐ確かめられる
// アラートを新しく作るのは、銘柄の詳細画面の🔔から（銘柄が決まっている必要があるため）。
// ============================================================

import 'package:flutter/material.dart';

import '../models/price_alert.dart';
import '../services/price_alert_service.dart';
import '../services/push_service.dart';
import '../widgets/error_dialog.dart';
import '../widgets/price_alert_sheet.dart';

class PriceAlertListScreen extends StatefulWidget {
  const PriceAlertListScreen({super.key});

  @override
  State<PriceAlertListScreen> createState() => _PriceAlertListScreenState();
}

class _PriceAlertListScreenState extends State<PriceAlertListScreen> {
  List<PriceAlert> _alerts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final alerts = await PriceAlertService.list();
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _isLoading = false;
      });
    } on PriceAlertException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggle(PriceAlert alert, bool enabled) async {
    try {
      await PriceAlertService.update(alert.alertId, enabled: enabled);
      await _load();
    } on PriceAlertException catch (e) {
      if (mounted) await ErrorDialog.show(context, message: e.message);
    }
  }

  Future<void> _delete(PriceAlert alert) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('アラートを削除'),
        content: Text('${alert.name}（${alert.conditionText}）を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PriceAlertService.delete(alert.alertId);
      await _load();
    } on PriceAlertException catch (e) {
      if (mounted) await ErrorDialog.show(context, message: e.message);
    }
  }

  Future<void> _edit(PriceAlert alert) async {
    final saved = await PriceAlertSheet.show(
      context,
      code: alert.code,
      name: alert.name,
      existing: alert,
    );
    if (saved) await _load();
  }

  Future<void> _sendTest() async {
    final messenger = ScaffoldMessenger.of(context);
    final allowed = await PushService.requestPermissionAndRegister();
    if (!mounted) return;
    if (!allowed) {
      await ErrorDialog.show(
        context,
        title: '通知を使えません',
        message: PushService.isSupported
            ? 'iPhone の「設定」→「通知」で、このアプリの通知を許可してください。'
            : 'この端末ではプッシュ通知を使えません（iPhone のアプリだけ対応しています）。',
      );
      return;
    }
    try {
      await PriceAlertService.sendTest();
      messenger.showSnackBar(
        const SnackBar(content: Text('テスト通知を送りました。数秒で届きます')),
      );
    } on PriceAlertException catch (e) {
      if (mounted) await ErrorDialog.show(context, message: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('株価アラート'),
        actions: [
          TextButton.icon(
            onPressed: _sendTest,
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('テスト通知'),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('再読み込み')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            '登録数：${_alerts.length} / ${PriceAlertService.maxAlerts}件\n'
            '新しく作るときは、銘柄の詳細画面の右上の🔔を押してください。',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          if (_alerts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: Text('アラートはまだありません')),
            ),
          for (final alert in _alerts) _buildTile(alert),
        ],
      ),
    );
  }

  Widget _buildTile(PriceAlert alert) {
    final repeatText = alert.repeat == PriceAlertRepeat.once
        ? '1回だけ'
        : '1日1回まで';
    final notified = alert.lastNotifiedDate.isEmpty
        ? ''
        : '・最後の通知 ${alert.lastNotifiedDate}';
    return Card(
      child: ListTile(
        title: Text('${alert.name}（${alert.displayCode}）'),
        subtitle: Text(
          '${alert.conditionText}・$repeatText$notified',
          style: const TextStyle(fontSize: 12),
        ),
        onTap: () => _edit(alert),
        leading: Switch(
          value: alert.enabled,
          onChanged: (v) => _toggle(alert, v),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '削除',
          onPressed: () => _delete(alert),
        ),
      ),
    );
  }
}
