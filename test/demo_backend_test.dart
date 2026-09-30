import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsuzuri/src/data/backend.dart';
import 'package:tsuzuri/src/data/demo_backend.dart';
import 'package:tsuzuri/src/domain/models.dart';
import 'package:tsuzuri/src/domain/rules.dart';

class Clock {
  DateTime now = DateTime.utc(2026, 10, 1, 3); // 12:00 JST
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

const me = Profile(
  id: 'me', penName: 'ひより', ageBand: '30代前半', prefecture: '東京都', bio: '',
  gender: Gender.woman, seeking: {Gender.woman, Gender.man},
);

Future<(DemoBackend, MemoryLocalStore, Clock)> started() async {
  final store = MemoryLocalStore();
  final clock = Clock();
  final b = DemoBackend(store, clock: clock.call, demoDelay: const Duration(seconds: 8));
  await b.load();
  await b.createProfile(me, firstDiary: '朝、ベランダでコーヒーを飲んだ。風が少し冷たかった。');
  return (b, store, clock);
}

Future<Letter> sendTo(DemoBackend b, String authorId) {
  final d = b.readableDiaries(authorId).first;
  return b.sendLetter(diaryId: d.id, quote: splitSentences(d.body).first, body: 'この一文が、とても好きでした。');
}

void main() {
  test('profile, first diary and a welcome letter persist across reload', () async {
    final (b, store, clock) = await started();
    expect(b.me!.penName, 'ひより');
    expect(b.myDiaries(), hasLength(1));
    expect(b.incomingLetters(), hasLength(1));

    final reloaded = DemoBackend(store, clock: clock.call);
    await reloaded.load();
    expect(reloaded.me!.penName, 'ひより');
    expect(reloaded.myDiaries().single.body, contains('ベランダ'));
    expect(reloaded.incomingLetters(), hasLength(1));
  });

  test('introductions: three per day, mutual only, stable within the day', () async {
    final (b, _, clock) = await started();
    final today = b.todaysIntroductions();
    expect(today.length, lessThanOrEqualTo(Limits.introsPerDay));
    expect(today, isNotEmpty);
    for (final p in today) {
      expect(mutuallyCompatible(b.me!, p), isTrue);
    }
    clock.advance(const Duration(hours: 2));
    expect(b.todaysIntroductions().map((p) => p.id), today.map((p) => p.id));
  });

  test('letter needs a real quote, blocks contact info, one per person', () async {
    final (b, _, _) = await started();
    final writer = b.todaysIntroductions().first;
    final d = b.readableDiaries(writer.id).first;
    await expectLater(
      b.sendLetter(diaryId: d.id, quote: '存在しない文。', body: 'この一文が、とても好きでした。'),
      throwsA(isA<TsuzuriException>()),
    );
    await expectLater(
      b.sendLetter(diaryId: d.id, quote: splitSentences(d.body).first, body: 'よかったら 090-1234-5678 まで連絡ください'),
      throwsA(isA<TsuzuriException>()),
    );
    await sendTo(b, writer.id);
    expect(b.relationWith(writer.id).kind, RelationKind.letterSent);
    await expectLater(sendTo(b, writer.id), throwsA(isA<TsuzuriException>()));
  });

  test('at most three letters wait at once', () async {
    final (b, _, _) = await started();
    // The welcome letter came from koharu, so she is not a fresh recipient.
    final ids = ['demo-akari', 'demo-minato', 'demo-shiori', 'demo-saku'];
    for (final id in ids.take(3)) {
      await sendTo(b, id);
    }
    await expectLater(sendTo(b, ids[3]), throwsA(isA<TsuzuriException>()));
  });

  test('demo writer accepts after the delay, then the shared diary works', () async {
    final (b, _, clock) = await started();
    await sendTo(b, 'demo-akari');
    expect(await b.tickDemo(), isFalse);
    clock.advance(const Duration(seconds: 9));
    expect(await b.tickDemo(), isTrue);
    final c = b.activeConnections().single;
    expect(c.partnerOf(meId), 'demo-akari');
    expect(b.pages(c.id), hasLength(1)); // greeting from the writer

    await b.writePage(c.id, '今日は雨でした。');
    clock.advance(const Duration(seconds: 9));
    await b.tickDemo();
    expect(b.pages(c.id).last.replies.single.authorId, 'demo-akari');
  });

  test('accepting and declining received letters', () async {
    final (b, _, _) = await started();
    final letter = b.incomingLetters().single;
    final c = await b.acceptLetter(letter.id);
    expect(b.activeConnections().single.id, c.id);
    expect(b.incomingLetters(), isEmpty);
    await expectLater(b.acceptLetter(letter.id), throwsA(isA<TsuzuriException>()));
  });

  test('photos are revealed only after the other side consents', () async {
    final (b, _, clock) = await started();
    final c = await b.acceptLetter(b.incomingLetters().single.id);
    await b.proposePhotoReveal(c.id);
    expect(b.connection(c.id)!.photoState, PhotoState.proposed);
    await expectLater(b.consentPhotoReveal(c.id), throwsA(isA<TsuzuriException>()));
    await b.cancelPhotoProposal(c.id);
    expect(b.connection(c.id)!.photoState, PhotoState.hidden);

    await b.proposePhotoReveal(c.id);
    clock.advance(const Duration(seconds: 9));
    await b.tickDemo();
    expect(PhotoRules.photosVisible(b.connection(c.id)!), isTrue);
  });

  test('ending, blocking and reporting close everything', () async {
    final (b, _, _) = await started();
    final letter = b.incomingLetters().single;
    final c = await b.acceptLetter(letter.id);
    await b.endConnection(c.id);
    expect(b.activeConnections(), isEmpty);
    expect(b.pages(c.id), isEmpty);
    expect(b.relationWith(letter.fromId).kind, RelationKind.closed);

    await sendTo(b, 'demo-minato');
    await b.report(targetId: 'demo-minato', context: 'diary', category: ReportCategory.harassment);
    expect(b.blockedUsers(), contains('demo-minato'));
    expect(b.readableDiaries('demo-minato'), isEmpty);
    expect(b.outgoingLetters().first.status, LetterStatus.closed);
    expect(b.reports.single.category, ReportCategory.harassment);
  });

  test('unanswered letters close quietly after 14 days', () async {
    final (b, _, clock) = await started();
    final incoming = b.incomingLetters().single;
    clock.advance(const Duration(days: 15));
    await b.tickDemo();
    expect(b.incomingLetters(), isEmpty);
    expect(b.relationWith(incoming.fromId).kind, RelationKind.closed);
  });

  test('pause stops introductions; delete removes everything', () async {
    final (b, store, _) = await started();
    await b.setPaused(true);
    expect(b.todaysIntroductions(), isEmpty);
    await b.deleteAllData();
    expect(b.me, isNull);
    expect(await store.read('tsuzuri.v1.me'), isNull);
  });

  test('many long diaries are stored in chunks under the record limit', () async {
    final (b, store, clock) = await started();
    final long = 'あ' * 1990;
    for (var i = 0; i < 80; i++) {
      await b.writeDiary('$i$long', DiaryScope.private);
    }
    final head = await store.read('tsuzuri.v1.diaries');
    expect(head!['chunks'], greaterThan(1));
    final reloaded = DemoBackend(store, clock: clock.call);
    await reloaded.load();
    expect(reloaded.myDiaries(), hasLength(81));
    await reloaded.deleteAllData();
    expect(await store.read('tsuzuri.v1.diaries.0'), isNull);
  });
}
