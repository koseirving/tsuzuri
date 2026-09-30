import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.backend});
  final TsuzuriBackend backend;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Set<Gender> seeking = {...widget.backend.me!.seeking};

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.backend,
        builder: (context, _) {
          final b = widget.backend;
          final me = b.me;
          if (me == null) return const Scaffold();
          final text = Theme.of(context).textTheme;
          final blocked = b.blockedUsers();
          final changed = seeking.length != me.seeking.length || !seeking.containsAll(me.seeking);
          return Scaffold(
            appBar: AppBar(title: const Text('設定')),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(me.penName, style: text.headlineSmall),
                Text(profileLine(me), style: text.bodySmall),
                if (me.bio.isNotEmpty) Text(me.bio, style: text.bodyMedium),
                const SectionLabel('出会いたい相手'),
                Text('あなたの性別：${me.gender.label}（ほかの人には表示されません）', style: text.bodySmall),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final g in [Gender.woman, Gender.man, Gender.nonbinary])
                    FilterChip(
                      label: Text(g.label),
                      selected: seeking.contains(g),
                      onSelected: (on) => setState(() => on ? seeking.add(g) : seeking.remove(g)),
                    ),
                ]),
                if (changed)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () async {
                        final ok = await runGuarded(context, () async {
                          await b.updateProfile(me.copyWith(seeking: {...seeking}));
                          return true;
                        });
                        if (ok == true && context.mounted) showNote(context, '保存しました。今日の紹介に反映されます。');
                      },
                      child: const Text('保存する'),
                    ),
                  ),
                const SectionLabel('お休み'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: me.paused,
                  title: const Text('お休みモード'),
                  subtitle: const Text('紹介を止めて、あなたの日記もだれにも紹介されなくなります。つながりはそのまま続きます。'),
                  onChanged: (v) => runGuarded(context, () => b.setPaused(v)),
                ),
                const SectionLabel('ブロックした人'),
                if (blocked.isEmpty)
                  Text('いません。', style: text.bodySmall)
                else
                  for (final id in blocked)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(b.profile(id)?.penName ?? '退会したユーザー'),
                      trailing: TextButton(
                        onPressed: () => runGuarded(context, () => b.unblock(id)),
                        child: const Text('解除'),
                      ),
                    ),
                const SectionLabel('データ'),
                const Hint('デモ版のデータは、この端末の中だけに保存されています。'),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: 'すべてのデータを削除しますか',
                      message: '日記、感想、ふたりの日記、設定がこの端末から消えます。元に戻せません。',
                      action: '削除する',
                      destructive: true,
                    );
                    if (!ok || !context.mounted) return;
                    final navigator = Navigator.of(context);
                    final done = await runGuarded(context, () async {
                      await b.deleteAllData();
                      return true;
                    });
                    if (done == true) navigator.popUntil((r) => r.isFirst);
                  },
                  child: const Text('すべてのデータを削除'),
                ),
              ],
            ),
          );
        },
      );
}
