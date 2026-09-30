import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../data/seed.dart';
import '../domain/models.dart';
import '../domain/rules.dart';
import 'theme.dart';
import 'widgets.dart';

/// 書く: no streaks, no counters, no obligation.
class WriteTab extends StatefulWidget {
  const WriteTab({super.key, required this.backend});
  final TsuzuriBackend backend;

  @override
  State<WriteTab> createState() => _WriteTabState();
}

class _WriteTabState extends State<WriteTab> {
  final body = TextEditingController();
  DiaryScope scope = DiaryScope.intro;
  bool usePrompt = true;
  bool busy = false;

  String get prompt => writingPrompts[stableHash(introDayKey(DateTime.now())) % writingPrompts.length];

  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  Future<void> _write() async {
    setState(() => busy = true);
    final entry = await runGuarded(
      context,
      () => widget.backend.writeDiary(body.text, scope, prompt: usePrompt ? prompt : null),
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (entry != null) {
      body.clear();
      FocusScope.of(context).unfocus();
      showNote(context, '書きました。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final mine = widget.backend.myDiaries();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('今日のこと', style: text.headlineSmall),
        const SizedBox(height: 4),
        Text('一行でも大丈夫。毎日書かなくても大丈夫。', style: text.bodySmall),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Text(
              usePrompt ? '問いかけ：$prompt' : '問いかけなし',
              style: text.bodySmall?.copyWith(color: usePrompt ? TsuzuriColors.osmanthus : TsuzuriColors.sub),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => usePrompt = !usePrompt),
            child: Text(usePrompt ? '使わない' : '使う'),
          ),
        ]),
        TextField(
          key: const Key('diary-body'),
          controller: body,
          minLines: 6,
          maxLines: 14,
          maxLength: Limits.diaryMax,
          decoration: const InputDecoration(hintText: '今日、少し心が動いたことを。'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text('だれに見せるか', style: text.bodySmall),
        const SizedBox(height: 6),
        SegmentedButton<DiaryScope>(
          showSelectedIcon: false,
          segments: [
            for (final s in DiaryScope.values) ButtonSegment(value: s, label: Text(s.label)),
          ],
          selected: {scope},
          onSelectionChanged: (s) => setState(() => scope = s.first),
        ),
        const SizedBox(height: 8),
        Hint(switch (scope) {
          DiaryScope.intro => 'あなたを紹介するときに、この日記が読まれます。',
          DiaryScope.connections => 'つながった人だけが読めます。',
          DiaryScope.private => 'あなただけの日記です。だれにも表示されません。',
        }),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy || body.text.trim().isEmpty ? null : _write,
          child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('書く')),
        ),
        if (mine.isNotEmpty) const SectionLabel('これまでの日記'),
        for (final d in mine) ...[
          Row(children: [
            Text(dateLabel(d.createdAt), style: text.bodySmall),
            const SizedBox(width: 10),
            Text(d.scope.label, style: text.bodySmall),
          ]),
          const SizedBox(height: 4),
          Text(d.body, style: text.bodyLarge),
          const Divider(height: 32),
        ],
      ],
    );
  }
}
