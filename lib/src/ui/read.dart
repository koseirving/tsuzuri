import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import '../domain/rules.dart';
import 'safety.dart';
import 'theme.dart';
import 'widgets.dart';

/// 読む: today's introductions. Deliberately finite.
class ReadTab extends StatelessWidget {
  const ReadTab({super.key, required this.backend});
  final TsuzuriBackend backend;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final me = backend.me!;
    final intros = backend.todaysIntroductions();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('今日の日記', style: text.headlineSmall),
        const SizedBox(height: 4),
        Text('明日の朝5時に、また届きます。', style: text.bodySmall),
        const SizedBox(height: 16),
        if (me.paused)
          const Hint('お休み中です。紹介は届きません。設定からいつでも再開できます。', icon: Icons.nightlight_outlined)
        else if (intros.isEmpty)
          const Hint('今日紹介できる人はいません。自分の日記を書いたり、ふたりの日記を読み返したりして過ごしましょう。')
        else
          for (final p in intros) ...[
            _IntroCard(backend: backend, profile: p),
            const SizedBox(height: 14),
          ],
        const SizedBox(height: 12),
        const DemoBanner(),
      ],
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.backend, required this.profile});
  final TsuzuriBackend backend;
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final diaries = backend.readableDiaries(profile.id);
    final latest = diaries.isEmpty ? null : diaries.first;
    final relation = backend.relationWith(profile.id).kind;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => WriterPage(backend: backend, authorId: profile.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(profile.penName, style: text.titleMedium),
              const SizedBox(width: 10),
              Text(profileLine(profile), style: text.bodySmall),
              const Spacer(),
              if (relation == RelationKind.letterSent) Text('感想を送りました', style: text.bodySmall),
            ]),
            if (latest != null) ...[
              const SizedBox(height: 10),
              if (latest.prompt != null)
                Text(latest.prompt!, style: text.bodySmall?.copyWith(color: TsuzuriColors.osmanthus)),
              Text(latest.body, style: text.bodyLarge, maxLines: 4, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Text('${dateLabel(latest.createdAt)}・ほかに${diaries.length - 1}日分の日記', style: text.bodySmall),
            ],
          ]),
        ),
      ),
    );
  }
}

/// One writer's diaries. Tap a sentence to quote it in a letter.
class WriterPage extends StatefulWidget {
  const WriterPage({super.key, required this.backend, required this.authorId});
  final TsuzuriBackend backend;
  final String authorId;

  @override
  State<WriterPage> createState() => _WriterPageState();
}

class _WriterPageState extends State<WriterPage> {
  String? diaryId;
  String? quote;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.backend,
        builder: (context, _) {
          final text = Theme.of(context).textTheme;
          final b = widget.backend;
          final profile = b.profile(widget.authorId);
          if (profile == null) return const Scaffold(body: Center(child: Text('見つかりませんでした。')));
          final diaries = b.readableDiaries(profile.id);
          final relation = b.relationWith(profile.id).kind;
          final canWrite = relation == RelationKind.none;
          return Scaffold(
            appBar: AppBar(
              title: Text(profile.penName),
              actions: [
                SafetyMenu(backend: b, targetId: profile.id, where: 'diary', afterExit: () => Navigator.pop(context)),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
              children: [
                Text(profileLine(profile), style: text.bodySmall),
                if (profile.bio.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(profile.bio, style: text.bodyMedium),
                ],
                const SizedBox(height: 16),
                _RelationHint(kind: relation),
                for (final d in diaries) ...[
                  const SizedBox(height: 24),
                  Row(children: [
                    Text(dateLabel(d.createdAt), style: text.bodySmall),
                    if (d.prompt != null) ...[
                      const SizedBox(width: 10),
                      Text(d.prompt!, style: text.bodySmall?.copyWith(color: TsuzuriColors.osmanthus)),
                    ],
                  ]),
                  const SizedBox(height: 6),
                  for (final s in splitSentences(d.body))
                    _Sentence(
                      text: s,
                      selected: diaryId == d.id && quote == s,
                      enabled: canWrite,
                      onTap: () => setState(() {
                        final same = diaryId == d.id && quote == s;
                        diaryId = same ? null : d.id;
                        quote = same ? null : s;
                      }),
                    ),
                ],
              ],
            ),
            bottomNavigationBar: canWrite
                ? SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (quote == null) Text('心に残った一文をタップしてください', style: text.bodySmall),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: quote == null
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => LetterComposePage(
                                          backend: b,
                                          diary: b.diary(diaryId!)!,
                                          quote: quote!,
                                        ),
                                      ),
                                    ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('この一文に感想を書く'),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  )
                : null,
          );
        },
      );
}

class _RelationHint extends StatelessWidget {
  const _RelationHint({required this.kind});
  final RelationKind kind;

  @override
  Widget build(BuildContext context) => switch (kind) {
        RelationKind.none => const Hint('写真はまだ見えません。文章から、この人の毎日を読んでみてください。'),
        RelationKind.letterSent => const Hint('感想を届けました。返事はゆっくり待ちましょう。', icon: Icons.mail_outline),
        RelationKind.letterReceived => const Hint('この人から感想が届いています。「ふたり」から返事ができます。', icon: Icons.mail_outline),
        RelationKind.connected => const Hint('つながっています。「ふたり」で、ふたりの日記を書けます。', icon: Icons.people_outline),
        RelationKind.closed => const Hint('この人とのやりとりは閉じています。'),
      };
}

class _Sentence extends StatelessWidget {
  const _Sentence({required this.text, required this.selected, required this.enabled, required this.onTap});
  final String text;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? TsuzuriColors.highlight : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      );
}

class LetterComposePage extends StatefulWidget {
  const LetterComposePage({super.key, required this.backend, required this.diary, required this.quote});
  final TsuzuriBackend backend;
  final DiaryEntry diary;
  final String quote;

  @override
  State<LetterComposePage> createState() => _LetterComposePageState();
}

class _LetterComposePageState extends State<LetterComposePage> {
  final body = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => busy = true);
    final sent = await runGuarded(
      context,
      () => widget.backend.sendLetter(diaryId: widget.diary.id, quote: widget.quote, body: body.text),
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (sent != null) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((r) => r.isFirst);
      messenger.showSnackBar(const SnackBar(content: Text('届けました。返事はゆっくり待ちましょう。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final author = widget.backend.profile(widget.diary.authorId);
    final length = body.text.trim().runes.length;
    return Scaffold(
      appBar: AppBar(title: Text('${author?.penName ?? ''}さんへの感想')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          QuoteBlock(widget.quote),
          const SizedBox(height: 20),
          TextField(
            controller: body,
            minLines: 5,
            maxLines: 10,
            maxLength: Limits.letterMax,
            autofocus: true,
            decoration: const InputDecoration(hintText: '例：私も秋は遠回りしたくなります。'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          const Hint('つながる前に、連絡先やSNSのIDは送れません。'),
          const SizedBox(height: 6),
          const Hint('返事がなくても、催促はできません。相手のペースを大切にしましょう。'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy || length < Limits.letterMin ? null : _send,
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('感想を届ける')),
          ),
          if (length > 0 && length < Limits.letterMin)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('あと${Limits.letterMin - length}文字', style: text.bodySmall, textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}
