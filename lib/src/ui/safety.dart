import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import 'widgets.dart';

enum _SafetyAction { end, block, report }

/// End / block / report, available from every place another person appears.
class SafetyMenu extends StatelessWidget {
  const SafetyMenu({
    super.key,
    required this.backend,
    required this.targetId,
    required this.where,
    required this.afterExit,
    this.connectionId,
  });

  final TsuzuriBackend backend;
  final String targetId;

  /// letter | page | diary | profile
  final String where;
  final String? connectionId;

  /// Called after the person is no longer reachable (ended, blocked, reported).
  final VoidCallback afterExit;

  Future<void> _select(BuildContext context, _SafetyAction action) async {
    final name = backend.profile(targetId)?.penName ?? 'この人';
    // Captured up front: this menu may be gone by the time the sheet closes.
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case _SafetyAction.end:
        final ok = await confirm(
          context,
          title: '関係を終えますか',
          message: '理由を伝える必要はありません。$nameさんには「この関係は終わりました」とだけ表示され、'
              'ふたりの日記は読めなくなります。もう一度つながることはできません。',
          action: '関係を終える',
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        final done = await runGuarded(context, () async {
          await backend.endConnection(connectionId!);
          return true;
        });
        if (done == true) afterExit();
      case _SafetyAction.block:
        final ok = await confirm(
          context,
          title: 'ブロックしますか',
          message: '$nameさんには通知されません。お互いに紹介されなくなり、つながりや感想も閉じます。',
          action: 'ブロックする',
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        final done = await runGuarded(context, () async {
          await backend.block(targetId);
          return true;
        });
        if (done == true) afterExit();
      case _SafetyAction.report:
        final done = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          builder: (_) => ReportSheet(backend: backend, targetId: targetId, where: where),
        );
        if (done == true) {
          messenger.showSnackBar(const SnackBar(content: Text('通報を受け付けました。この人はブロックされました。')));
          afterExit();
        }
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<_SafetyAction>(
        tooltip: '安全のためのメニュー',
        icon: const Icon(Icons.more_horiz),
        onSelected: (a) => _select(context, a),
        itemBuilder: (_) => [
          if (connectionId != null) const PopupMenuItem(value: _SafetyAction.end, child: Text('関係を終える')),
          const PopupMenuItem(value: _SafetyAction.block, child: Text('ブロック')),
          const PopupMenuItem(value: _SafetyAction.report, child: Text('通報')),
        ],
      );
}

class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key, required this.backend, required this.targetId, required this.where});
  final TsuzuriBackend backend;
  final String targetId;
  final String where;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportCategory? category;
  final note = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => busy = true);
    final done = await runGuarded(context, () async {
      await widget.backend.report(
        targetId: widget.targetId,
        context: widget.where,
        category: category!,
        note: note.text,
      );
      return true;
    });
    if (!mounted) return;
    setState(() => busy = false);
    if (done == true) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('通報', style: text.headlineSmall),
        const SizedBox(height: 6),
        const Hint('運営が内容を確認します。通報すると、この人は自動的にブロックされます。相手に通報したことは伝わりません。'),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in ReportCategory.values)
            ChoiceChip(label: Text(c.label), selected: category == c, onSelected: (_) => setState(() => category = c)),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: note,
          maxLines: 3,
          maxLength: 1000,
          decoration: const InputDecoration(hintText: '状況の説明（任意）'),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: category == null || busy ? null : _send,
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('通報する')),
          ),
        ),
      ]),
    );
  }
}
