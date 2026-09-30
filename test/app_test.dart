import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsuzuri/src/data/demo_backend.dart';
import 'package:tsuzuri/src/ui/app.dart';

void main() {
  testWidgets('onboarding → read → quote a sentence → send a letter', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final backend = DemoBackend(MemoryLocalStore());
    await backend.load();
    await tester.pumpWidget(TsuzuriApp(backend: backend, runDemoWorld: false));
    await tester.pumpAndSettle();

    expect(find.text('好きになるのは、その人の毎日。'), findsOneWidget);
    await tester.ensureVisible(find.text('18歳以上です'));
    await tester.tap(find.text('18歳以上です'));
    await tester.pump();
    await tester.ensureVisible(find.text('次へ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'ペンネーム'), 'ひより');
    await tester.pump();
    await tester.ensureVisible(find.text('次へ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('女性').first);
    await tester.pump();
    await tester.tap(find.text('男性').last);
    await tester.pump();
    await tester.ensureVisible(find.text('次へ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '朝、ベランダでコーヒーを飲んだ。');
    await tester.pump();
    await tester.ensureVisible(find.text('はじめる'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();

    expect(find.text('今日の日記'), findsOneWidget);
    expect(backend.me!.penName, 'ひより');

    final first = backend.todaysIntroductions().first;
    await tester.tap(find.text(first.penName).first);
    await tester.pumpAndSettle();

    final diary = backend.readableDiaries(first.id).first;
    final sentence = diary.body.substring(0, diary.body.indexOf('。') + 1);
    await tester.tap(find.text(sentence));
    await tester.pump();
    await tester.tap(find.text('この一文に感想を書く'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'この一文が、とても好きでした。');
    await tester.pump();
    await tester.tap(find.text('感想を届ける'));
    await tester.pumpAndSettle();

    expect(find.text('届けました。返事はゆっくり待ちましょう。'), findsOneWidget);
    expect(backend.outgoingLetters().single.toId, first.id);
  });
}
