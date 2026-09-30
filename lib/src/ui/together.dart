import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import '../domain/rules.dart';
import 'read.dart';
import 'safety.dart';
import 'theme.dart';
import 'widgets.dart';

/// ふたり: letters and connections. No read receipts, no deadlines.
class TogetherTab extends StatelessWidget {
  const TogetherTab({super.key, required this.backend, this.demoDelay});
  final TsuzuriBackend backend;
  final Duration? demoDelay;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final incoming = backend.incomingLetters();
    final connections = backend.activeConnections();
    final outgoing = backend.outgoingLetters();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('ふたり', style: text.headlineSmall),
        const SizedBox(height: 4),
        Text('既読の表示や、返信の期限はありません。', style: text.bodySmall),
        if (incoming.isNotEmpty) ...[
          const SectionLabel('届いた感想'),
          for (final l in incoming) ...[
            _LetterCard(backend: backend, letter: l),
            const SizedBox(height: 12),
          ],
        ],
        SectionLabel('つながり', trailing: '${connections.length} / ${Limits.activeConnections}'),
        if (connections.isEmpty)
          const Hint('まだだれともつながっていません。日記を読んで、心に残った一文に感想を送ってみましょう。')
        else
          for (final c in connections) ...[
            _ConnectionTile(backend: backend, connection: c),
            const SizedBox(height: 12),
          ],
        if (outgoing.isNotEmpty) ...[
          const SectionLabel('送った感想'),
          for (final l in outgoing) ...[
            _OutgoingTile(backend: backend, letter: l),
            const SizedBox(height: 10),
          ],
        ],
        const SizedBox(height: 20),
        if (demoDelay != null)
          DemoBanner(
            text: 'デモ版：架空の書き手は、約${demoDelay!.inSeconds}秒後に「話したい」と返し、'
                'ふたりの日記や写真の提案にも返事をします。',
          ),
      ],
    );
  }
}

class _LetterCard extends StatelessWidget {
  const _LetterCard({required this.backend, required this.letter});
  final TsuzuriBackend backend;
  final Letter letter;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final from = backend.profile(letter.fromId);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => LetterDetailPage(backend: backend, letterId: letter.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${from?.penName ?? ''}さんから', style: text.titleMedium),
            const SizedBox(height: 8),
            QuoteBlock(letter.quote),
            const SizedBox(height: 8),
            Text(letter.body, style: text.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({required this.backend, required this.connection});
  final TsuzuriBackend backend;
  final Connection connection;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final me = backend.me!;
    final partner = backend.profile(connection.partnerOf(me.id));
    if (partner == null) return const SizedBox.shrink();
    final pages = backend.pages(connection.id);
    final last = pages.isEmpty ? null : pages.last;
    final lastAuthor = last == null
        ? null
        : (last.replies.isEmpty ? last.authorId : last.replies.last.authorId);
    final lastText = last == null ? '' : (last.replies.isEmpty ? last.body : last.replies.last.body);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => ConnectionPage(backend: backend, connectionId: connection.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            PhotoTile(profile: partner, revealed: PhotoRules.photosVisible(connection), size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(partner.penName, style: text.titleMedium),
                  if (lastAuthor != null && lastAuthor != me.id) ...[
                    const SizedBox(width: 8),
                    const SizedBox.square(
                      dimension: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: TsuzuriColors.osmanthus, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ]),
                Text(lastText, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _OutgoingTile extends StatelessWidget {
  const _OutgoingTile({required this.backend, required this.letter});
  final TsuzuriBackend backend;
  final Letter letter;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final to = backend.profile(letter.toId);
    final waiting = letter.status == LetterStatus.pending;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(waiting ? Icons.mail_outline : Icons.drafts_outlined, size: 18, color: TsuzuriColors.sub),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${to?.penName ?? ''}さんへ・${dateLabel(letter.createdAt)}', style: text.bodyMedium),
          Text(waiting ? '返事を待っています。急がなくて大丈夫です。' : 'そっと閉じました。', style: text.bodySmall),
        ]),
      ),
    ]);
  }
}

/// A received letter: "話したい" or "見送る". The sender is never told which.
class LetterDetailPage extends StatelessWidget {
  const LetterDetailPage({super.key, required this.backend, required this.letterId});
  final TsuzuriBackend backend;
  final String letterId;

  Future<void> _accept(BuildContext context) async {
    final c = await runGuarded(context, () => backend.acceptLetter(letterId));
    if (c == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('つながりました'),
        content: const Text('つながることは、交際への同意ではありません。'
            'ふたりの日記で、ゆっくり知り合っていきましょう。'
            'いつでも理由なしで関係を終えられます。'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('わかりました'))],
      ),
    );
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => ConnectionPage(backend: backend, connectionId: c.id)),
    );
  }

  Future<void> _decline(BuildContext context) async {
    final ok = await confirm(
      context,
      title: '見送りますか',
      message: '相手には通知されません。理由を伝える必要もありません。',
      action: '見送る',
    );
    if (!ok || !context.mounted) return;
    await runGuarded(context, () => backend.declineLetter(letterId));
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final letter = backend.incomingLetters().where((l) => l.id == letterId).firstOrNull;
    if (letter == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('この感想には、もう返事ができません。')));
    }
    final from = backend.profile(letter.fromId)!;
    return Scaffold(
      appBar: AppBar(
        title: Text('${from.penName}さんから'),
        actions: [
          SafetyMenu(backend: backend, targetId: from.id, where: 'letter', afterExit: () => Navigator.pop(context)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(profileLine(from), style: text.bodySmall),
          const SizedBox(height: 20),
          Text('あなたの日記から', style: text.bodySmall),
          const SizedBox(height: 6),
          QuoteBlock(letter.quote),
          const SizedBox(height: 16),
          Text(letter.body, style: text.bodyLarge),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: Text('${from.penName}さんの日記を読む'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => WriterPage(backend: backend, authorId: from.id)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Hint('「話したい」と返すと、ふたりがつながり、ふたりの日記が始まります。写真はまだ公開されません。'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => _accept(context),
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('話したい')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _decline(context),
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('見送る')),
          ),
        ],
      ),
    );
  }
}

/// ふたりの日記.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, required this.backend, required this.connectionId});
  final TsuzuriBackend backend;
  final String connectionId;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final body = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  Future<void> _write() async {
    setState(() => busy = true);
    final ok = await runGuarded(context, () async {
      await widget.backend.writePage(widget.connectionId, body.text);
      return true;
    });
    if (!mounted) return;
    setState(() => busy = false);
    if (ok == true) {
      body.clear();
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _reply(SharedPage page) async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReplySheet(quote: page.body),
    );
    if (text == null || !mounted) return;
    await runGuarded(context, () => widget.backend.replyToPage(widget.connectionId, page.id, text));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.backend,
        builder: (context, _) {
          final text = Theme.of(context).textTheme;
          final b = widget.backend;
          final me = b.me!;
          final c = b.connection(widget.connectionId);
          if (c == null || c.status == ConnectionStatus.ended) {
            return Scaffold(
              appBar: AppBar(),
              body: const Padding(
                padding: EdgeInsets.all(24),
                child: Hint('この関係は終わりました。ふたりの日記は読めなくなっています。'),
              ),
            );
          }
          final partner = b.profile(c.partnerOf(me.id))!;
          final pages = b.pages(c.id);
          final visible = PhotoRules.photosVisible(c);
          return Scaffold(
            appBar: AppBar(
              title: Text('${partner.penName}さんとの日記'),
              actions: [
                SafetyMenu(
                  backend: b,
                  targetId: partner.id,
                  where: 'page',
                  connectionId: c.id,
                  afterExit: () => Navigator.pop(context),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                const Hint('つながることは、交際への同意ではありません。いつでも理由なしで離れられます。'),
                const SizedBox(height: 16),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => PhotoRevealPage(backend: b, connectionId: c.id)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        PhotoTile(profile: partner, revealed: visible, size: 44),
                        const SizedBox(width: 6),
                        PhotoTile(profile: me, revealed: visible, size: 44),
                        const SizedBox(width: 14),
                        Expanded(child: Text(_photoStatus(c, me.id), style: text.bodySmall)),
                        const Icon(Icons.chevron_right, color: TsuzuriColors.sub),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: Text('${partner.penName}さんの日記を読む'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => WriterPage(backend: b, authorId: partner.id)),
                    ),
                  ),
                ),
                for (final p in pages) _PageView(backend: b, page: p, onReply: () => _reply(p)),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('page-body'),
                  controller: body,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: Limits.pageMax,
                  decoration: const InputDecoration(hintText: 'ふたりの日記に書く'),
                  onChanged: (_) => setState(() {}),
                ),
                FilledButton(
                  onPressed: busy || body.text.trim().isEmpty ? null : _write,
                  child: const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('書き足す')),
                ),
              ],
            ),
          );
        },
      );
}

String _photoStatus(Connection c, String meId) => switch (c.photoState) {
      PhotoState.hidden => '写真はまだ見えません。見せ合うかどうかは、ふたりで決められます。',
      PhotoState.proposed when c.proposedBy == meId => '写真を見せ合う提案をしています。相手の返事を待っています。',
      PhotoState.proposed => '写真を見せ合う提案が届いています。',
      PhotoState.revealed => 'ふたりの写真を、同時に公開しました。',
    };

class _PageView extends StatelessWidget {
  const _PageView({required this.backend, required this.page, required this.onReply});
  final TsuzuriBackend backend;
  final SharedPage page;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final author = backend.profile(page.authorId);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${author?.penName ?? ''}・${dateLabel(page.createdAt)}', style: text.bodySmall),
        const SizedBox(height: 4),
        Text(page.body, style: text.bodyLarge),
        for (final r in page.replies)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 10),
            child: Container(
              padding: const EdgeInsets.only(left: 12),
              decoration: const BoxDecoration(border: Border(left: BorderSide(color: TsuzuriColors.line, width: 2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${backend.profile(r.authorId)?.penName ?? ''}の返事', style: text.bodySmall),
                Text(r.body, style: text.bodyMedium),
              ]),
            ),
          ),
        TextButton(onPressed: onReply, child: const Text('返事を添える')),
        const Divider(),
      ]),
    );
  }
}

class _ReplySheet extends StatefulWidget {
  const _ReplySheet({required this.quote});
  final String quote;

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final body = TextEditingController();

  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          QuoteBlock(widget.quote),
          const SizedBox(height: 12),
          TextField(
            key: const Key('reply-body'),
            controller: body,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            maxLength: Limits.pageMax,
            decoration: const InputDecoration(hintText: '返事を添える'),
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: body.text.trim().isEmpty ? null : () => Navigator.pop(context, body.text),
              child: const Text('添える'),
            ),
          ),
        ]),
      );
}

/// Explains, then proposes / consents. Both photos appear at the same moment.
class PhotoRevealPage extends StatelessWidget {
  const PhotoRevealPage({super.key, required this.backend, required this.connectionId});
  final TsuzuriBackend backend;
  final String connectionId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: backend,
        builder: (context, _) {
          final text = Theme.of(context).textTheme;
          final me = backend.me!;
          final c = backend.connection(connectionId);
          if (c == null || c.status != ConnectionStatus.active) {
            return Scaffold(appBar: AppBar(), body: const Center(child: Text('この関係は終わっています。')));
          }
          final partner = backend.profile(c.partnerOf(me.id))!;
          final visible = PhotoRules.photosVisible(c);
          return Scaffold(
            appBar: AppBar(title: const Text('写真を見せ合う')),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Column(children: [
                    PhotoTile(profile: partner, revealed: visible, size: 120),
                    const SizedBox(height: 6),
                    Text(partner.penName, style: text.bodySmall),
                  ]),
                  const SizedBox(width: 20),
                  Column(children: [
                    PhotoTile(profile: me, revealed: visible, size: 120),
                    const SizedBox(height: 6),
                    Text('あなた', style: text.bodySmall),
                  ]),
                ]),
                if (visible) ...[
                  const SizedBox(height: 8),
                  Text('デモ版では、写真の代わりに色の画像を表示しています。',
                      style: text.bodySmall, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                if (!visible) ...[
                  const _Point('ふたりが同意した時点で、お互いの写真が同時に公開されます。'),
                  const _Point('公開した後に関係を終えても、相手がすでに見たことは取り消せません。'),
                  const _Point('同意しないことは失礼ではありません。理由を伝える必要もありません。'),
                  const SizedBox(height: 20),
                ],
                ..._actions(context, c, me.id),
              ],
            ),
          );
        },
      );

  List<Widget> _actions(BuildContext context, Connection c, String meId) {
    const pad = EdgeInsets.symmetric(vertical: 12);
    if (PhotoRules.canPropose(c)) {
      return [
        FilledButton(
          onPressed: () => runGuarded(context, () => backend.proposePhotoReveal(connectionId)),
          child: const Padding(padding: pad, child: Text('写真を見せ合いませんか、と提案する')),
        ),
      ];
    }
    if (PhotoRules.canCancel(c, meId)) {
      return [
        const Hint('相手の返事を待っています。相手が同意する前なら、提案を取り消せます。'),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => runGuarded(context, () => backend.cancelPhotoProposal(connectionId)),
          child: const Padding(padding: pad, child: Text('提案を取り消す')),
        ),
      ];
    }
    if (PhotoRules.canConsent(c, meId)) {
      return [
        FilledButton(
          onPressed: () async {
            final ok = await confirm(
              context,
              title: '同意して公開しますか',
              message: 'ふたりの写真が、いま同時に公開されます。',
              action: '同意して公開',
            );
            if (ok && context.mounted) {
              await runGuarded(context, () => backend.consentPhotoReveal(connectionId));
            }
          },
          child: const Padding(padding: pad, child: Text('同意して公開する')),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Padding(padding: pad, child: Text('今はまだ')),
        ),
        const SizedBox(height: 8),
        const Hint('「今はまだ」を選んでも、相手には通知されません。'),
      ];
    }
    return const [];
  }
}

class _Point extends StatelessWidget {
  const _Point(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Hint(text, icon: Icons.check_circle_outline),
      );
}
