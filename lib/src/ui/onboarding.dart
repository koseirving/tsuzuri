import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../data/seed.dart';
import '../domain/models.dart';
import 'theme.dart';
import 'widgets.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.backend});
  final TsuzuriBackend backend;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int step = 0;
  bool adult = false;
  final penName = TextEditingController();
  final bio = TextEditingController();
  final diary = TextEditingController();
  String ageBand = ageBands[1];
  String prefecture = '東京都';
  Gender? gender;
  final Set<Gender> seeking = {};
  bool busy = false;

  @override
  void dispose() {
    penName.dispose();
    bio.dispose();
    diary.dispose();
    super.dispose();
  }

  bool get canContinue => switch (step) {
        0 => adult,
        1 => penName.text.trim().isNotEmpty,
        2 => gender != null && seeking.isNotEmpty,
        _ => diary.text.trim().isNotEmpty && !busy,
      };

  Future<void> _next() async {
    if (step < 3) {
      setState(() => step++);
      return;
    }
    setState(() => busy = true);
    await runGuarded(context, () => widget.backend.createProfile(
          Profile(
            id: 'me',
            penName: penName.text,
            ageBand: ageBand,
            prefecture: prefecture,
            bio: bio.text,
            gender: gender!,
            seeking: {...seeking},
          ),
          firstDiary: diary.text,
        ));
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: step == 0
            ? null
            : IconButton(
                tooltip: '戻る',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => step--),
              ),
        title: Text('はじめに  ${step + 1} / 4', style: text.bodySmall),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            ...switch (step) {
              0 => _intro(text),
              1 => _profile(text),
              2 => _preferences(text),
              _ => _firstDiary(text),
            },
            const SizedBox(height: 32),
            FilledButton(
              onPressed: canContinue ? _next : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(step == 3 ? 'はじめる' : '次へ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _intro(TextTheme text) => [
        const SizedBox(height: 24),
        Text('つづり', style: text.headlineSmall?.copyWith(fontSize: 30, letterSpacing: 6)),
        const SizedBox(height: 8),
        Text('好きになるのは、その人の毎日。', style: text.bodyLarge),
        const SizedBox(height: 28),
        Text(
          '日々の小さな出来事を書いた日記から、人柄を知る場所です。'
          '友達になり、ふたりが望めば、その先に恋愛もあります。',
          style: text.bodyLarge,
        ),
        const SizedBox(height: 24),
        const _Promise('返信を急かしません', '既読表示も、返信の期限もありません。'),
        const _Promise('人気を競いません', 'いいねの数やランキングはありません。'),
        const _Promise('一人ずつ向き合います', '紹介は1日3人、つながりは同時に3人までです。'),
        const _Promise('無理なく続けられます', '毎日書く義務も、休んだときの罰もありません。'),
        const _Promise('安心して離れられます', '理由なしで見送り・関係の終了・ブロックができます。'),
        const SizedBox(height: 20),
        const DemoBanner(),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: adult,
          onChanged: (v) => setState(() => adult = v ?? false),
          title: const Text('18歳以上です'),
          subtitle: const Text('公開版では、公的書類による年齢確認を行います。'),
        ),
      ];

  List<Widget> _profile(TextTheme text) => [
        Text('あなたのことを少しだけ', style: text.headlineSmall),
        const SizedBox(height: 8),
        const Hint('本名や顔写真は、ここでは使いません。連絡先やSNSのIDは書けません。'),
        const SizedBox(height: 24),
        TextField(
          controller: penName,
          maxLength: 16,
          decoration: const InputDecoration(labelText: 'ペンネーム'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: ageBand,
          decoration: const InputDecoration(labelText: '年代'),
          items: [for (final a in ageBands) DropdownMenuItem(value: a, child: Text(a))],
          onChanged: (v) => setState(() => ageBand = v ?? ageBand),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: prefecture,
          decoration: const InputDecoration(labelText: '住んでいる地域'),
          items: [for (final p in prefectures) DropdownMenuItem(value: p, child: Text(p))],
          onChanged: (v) => setState(() => prefecture = v ?? prefecture),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: bio,
          maxLength: 120,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ひとこと（任意）', hintText: '例：散歩と喫茶店が好きです'),
        ),
      ];

  List<Widget> _preferences(TextTheme text) => [
        Text('どんな人と出会いたいですか', style: text.headlineSmall),
        const SizedBox(height: 8),
        const Hint('ここで選んだことは、ほかの人には表示されません。お互いの希望が合う人だけが紹介されます。',
            icon: Icons.visibility_off_outlined),
        const SizedBox(height: 24),
        Text('あなたの性別', style: text.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in Gender.values)
            ChoiceChip(
              label: Text(g.label),
              selected: gender == g,
              onSelected: (_) => setState(() => gender = g),
            ),
        ]),
        const SizedBox(height: 24),
        Text('出会いたい相手（いくつでも）', style: text.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in [Gender.woman, Gender.man, Gender.nonbinary])
            FilterChip(
              label: Text(g.label),
              selected: seeking.contains(g),
              onSelected: (on) => setState(() => on ? seeking.add(g) : seeking.remove(g)),
            ),
        ]),
        if (gender == Gender.unspecified) ...[
          const SizedBox(height: 16),
          const Hint('「回答しない」を選んだ場合、出会いたい相手にすべての性別を選んでいる人とだけ紹介し合います。'),
        ],
      ];

  List<Widget> _firstDiary(TextTheme text) => [
        Text('最初の日記', style: text.headlineSmall),
        const SizedBox(height: 8),
        const Hint('一行で大丈夫です。この日記が、あなたを紹介する最初のページになります。'),
        const SizedBox(height: 20),
        Text('今日うれしかったこと', style: text.bodySmall?.copyWith(color: TsuzuriColors.osmanthus)),
        const SizedBox(height: 8),
        TextField(
          controller: diary,
          minLines: 5,
          maxLines: 10,
          maxLength: 2000,
          decoration: const InputDecoration(hintText: '例：帰り道、遠回りして金木犀を探した。'),
          onChanged: (_) => setState(() {}),
        ),
      ];
}

class _Promise extends StatelessWidget {
  const _Promise(this.title, this.body);
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 9, right: 12),
            child: SizedBox.square(
              dimension: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(color: TsuzuriColors.osmanthus, shape: BoxShape.circle),
              ),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(body, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
      );
}
