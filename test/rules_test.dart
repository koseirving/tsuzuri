import 'package:flutter_test/flutter_test.dart';
import 'package:tsuzuri/src/domain/models.dart';
import 'package:tsuzuri/src/domain/rules.dart';

Profile p(String id, Gender g, Set<Gender> seeking, {bool paused = false}) => Profile(
      id: id, penName: id, ageBand: '30代前半', prefecture: '東京都', bio: '',
      gender: g, seeking: seeking, paused: paused);

void main() {
  group('mutual compatibility', () {
    test('same-gender match needs both wishes', () {
      final a = p('a', Gender.woman, {Gender.woman});
      final b = p('b', Gender.woman, {Gender.woman, Gender.man});
      final c = p('c', Gender.woman, {Gender.man});
      expect(mutuallyCompatible(a, b), isTrue);
      expect(mutuallyCompatible(a, c), isFalse);
    });

    test('different-gender match', () {
      final a = p('a', Gender.man, {Gender.woman});
      final b = p('b', Gender.woman, {Gender.man});
      expect(mutuallyCompatible(a, b), isTrue);
      expect(mutuallyCompatible(b, a), isTrue);
    });

    test('unspecified gender only meets people open to everyone', () {
      final u = p('u', Gender.unspecified, {Gender.woman});
      final open = p('o', Gender.woman, {Gender.woman, Gender.man, Gender.nonbinary});
      final narrow = p('n', Gender.woman, {Gender.woman, Gender.man});
      expect(mutuallyCompatible(u, open), isTrue);
      expect(mutuallyCompatible(u, narrow), isFalse);
    });

    test('never matches self', () {
      final a = p('a', Gender.woman, {Gender.woman});
      expect(mutuallyCompatible(a, a), isFalse);
    });
  });

  group('contact info', () {
    for (final s in [
      '090-1234-5678です',
      '０９０１２３４５６７８',
      'mail: a.b@example.com',
      'https://example.com 見てね',
      'インスタやってます',
      'LINE ID 教えてください',
      '@hibi_to でフォローして',
      '090ー1234ー5678',
    ]) {
      test('detects: $s', () => expect(containsContactInfo(s), isTrue));
    }
    for (final s in [
      '帰り道、遠回りして金木犀を探した。',
      'ラインを引いた本を読み返しました',
      '2026-09-30の夕焼けがきれいでした',
      'ツイードのコートを出しました',
    ]) {
      test('allows: $s', () => expect(containsContactInfo(s), isFalse));
    }
  });

  test('letter validation', () {
    const diary = '帰り道、遠回りして金木犀を探した。香りだけが先に届いた。';
    expect(letterProblem(quote: '香りだけが先に届いた。', body: '私も秋は遠回りしたくなります。', diaryBody: diary), isNull);
    expect(letterProblem(quote: '存在しない文', body: '私も秋は遠回りしたくなります。', diaryBody: diary), isNotNull);
    expect(letterProblem(quote: '香りだけが先に届いた。', body: 'いいね', diaryBody: diary), isNotNull);
    expect(letterProblem(quote: '香りだけが先に届いた。', body: 'よかったら 090-1234-5678 に連絡ください', diaryBody: diary),
        contains('連絡先'));
  });

  test('sentence split keeps quotable sentences', () {
    expect(splitSentences('一つ目。二つ目！三つ目\n四つ目'), ['一つ目。', '二つ目！', '三つ目', '四つ目']);
  });

  test('intro day rolls over at 05:00 JST', () {
    expect(introDayKey(DateTime.utc(2026, 9, 30, 19, 59)), '2026-09-30'); // 04:59 JST Oct 1
    expect(introDayKey(DateTime.utc(2026, 9, 30, 20, 0)), '2026-10-01'); // 05:00 JST Oct 1
  });

  group('introductions', () {
    final me = p('me', Gender.woman, {Gender.woman, Gender.man});
    final others = [
      for (var i = 0; i < 8; i++) p('w$i', Gender.woman, {Gender.woman}),
      p('m0', Gender.man, {Gender.woman}),
      p('m1', Gender.man, {Gender.man}),
      p('sleep', Gender.woman, {Gender.woman}, paused: true),
    ];
    List<String> pick(String day, {Set<String> excluded = const {}, Map<String, String>? last}) => pickIntroductions(
          me: me,
          others: others,
          dayKey: day,
          excluded: excluded,
          lastIntroduced: last ?? {},
          hasRecentIntroDiary: (_) => true,
          atConnectionLimit: (_) => false,
        );

    test('at most three, compatible, not paused, deterministic', () {
      final a = pick('2026-10-01');
      expect(a.length, Limits.introsPerDay);
      expect(a, isNot(contains('m1')));
      expect(a, isNot(contains('sleep')));
      expect(pick('2026-10-01'), a);
    });

    test('respects exclusions and cooldown', () {
      final excluded = {for (var i = 0; i < 8; i++) 'w$i'};
      expect(pick('2026-10-01', excluded: excluded), ['m0']);
      expect(pick('2026-10-01', excluded: excluded, last: {'m0': '2026-09-20'}), isEmpty);
      expect(pick('2026-10-01', excluded: excluded, last: {'m0': '2026-08-01'}), ['m0']);
    });
  });

  group('photo state machine', () {
    final base = Connection(
        id: 'c', members: const ['a', 'b'], createdAt: DateTime.utc(2026), status: ConnectionStatus.active);
    test('propose, only the other side consents', () {
      expect(PhotoRules.canPropose(base), isTrue);
      final proposed = base.copyWith(photoState: PhotoState.proposed, proposedBy: 'a');
      expect(PhotoRules.canConsent(proposed, 'a'), isFalse);
      expect(PhotoRules.canConsent(proposed, 'b'), isTrue);
      expect(PhotoRules.canCancel(proposed, 'a'), isTrue);
      expect(PhotoRules.canCancel(proposed, 'b'), isFalse);
      expect(PhotoRules.photosVisible(proposed), isFalse);
    });
    test('ended connection hides revealed photos', () {
      final revealed = base.copyWith(photoState: PhotoState.revealed);
      expect(PhotoRules.photosVisible(revealed), isTrue);
      expect(PhotoRules.photosVisible(revealed.copyWith(status: ConnectionStatus.ended)), isFalse);
    });
  });
}
