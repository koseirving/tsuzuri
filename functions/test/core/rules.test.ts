import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  containsContactInfo, introDayKey, letterProblem, mutuallyCompatible, pickIntroductions, splitSentences,
} from '../../src/core/rules.ts';
import type { Candidate, Person } from '../../src/core/rules.ts';

const p = (uid: string, gender: Person['gender'], seeking: Person['seeking']): Person => ({ uid, gender, seeking });
const c = (uid: string, gender: Person['gender'], seeking: Person['seeking'], extra: Partial<Candidate> = {}): Candidate => ({
  uid, gender, seeking, paused: false, hasRecentIntroDiary: true, atConnectionLimit: false, ...extra,
});

test('mutual matching covers same-gender, different-gender and unspecified', () => {
  assert.equal(mutuallyCompatible(p('a', 'woman', ['woman']), p('b', 'woman', ['woman', 'man'])), true);
  assert.equal(mutuallyCompatible(p('a', 'woman', ['woman']), p('b', 'woman', ['man'])), false);
  assert.equal(mutuallyCompatible(p('a', 'man', ['woman']), p('b', 'woman', ['man'])), true);
  assert.equal(mutuallyCompatible(p('u', 'unspecified', ['woman']), p('o', 'woman', ['woman', 'man', 'nonbinary'])), true);
  assert.equal(mutuallyCompatible(p('u', 'unspecified', ['woman']), p('n', 'woman', ['woman', 'man'])), false);
  assert.equal(mutuallyCompatible(p('a', 'woman', ['woman']), p('a', 'woman', ['woman'])), false);
});

test('contact info detection', () => {
  for (const s of ['090-1234-5678です', '０９０１２３４５６７８', 'a.b@example.com', 'https://example.com', 'インスタやってます',
    'LINE ID 教えて', '@hibi_to でフォロー', '090ー1234ー5678']) {
    assert.equal(containsContactInfo(s), true, s);
  }
  for (const s of ['帰り道、遠回りして金木犀を探した。', 'ラインを引いた本', '2026-09-30の夕焼け', 'ツイードのコート']) {
    assert.equal(containsContactInfo(s), false, s);
  }
});

test('letters need a real quote and 10+ characters without contact info', () => {
  const diary = '帰り道、遠回りして金木犀を探した。香りだけが先に届いた。';
  assert.equal(letterProblem('香りだけが先に届いた。', '私も秋は遠回りしたくなります。', diary), null);
  assert.notEqual(letterProblem('ない文。', '私も秋は遠回りしたくなります。', diary), null);
  assert.notEqual(letterProblem('香りだけが先に届いた。', 'いいね', diary), null);
  assert.match(letterProblem('香りだけが先に届いた。', 'よかったら 090-1234-5678 まで', diary) ?? '', /連絡先/);
});

test('sentences keep quoted speech whole', () => {
  assert.deepEqual(splitSentences('一つ目。二つ目！三つ目\n四つ目'), ['一つ目。', '二つ目！', '三つ目', '四つ目']);
  assert.deepEqual(splitSentences('原稿に「よいてんき。」という一文。'), ['原稿に「よいてんき。」という一文。']);
});

test('day rolls over at 05:00 JST', () => {
  assert.equal(introDayKey(new Date(Date.UTC(2026, 8, 30, 19, 59))), '2026-09-30');
  assert.equal(introDayKey(new Date(Date.UTC(2026, 8, 30, 20, 0))), '2026-10-01');
});

test('introductions: three, compatible, deterministic, cooldown', () => {
  const me = p('me', 'woman', ['woman', 'man']);
  const candidates = [
    ...Array.from({ length: 8 }, (_, i) => c(`w${i}`, 'woman', ['woman'])),
    c('m0', 'man', ['woman']),
    c('m1', 'man', ['man']),
    c('sleep', 'woman', ['woman'], { paused: true }),
    c('full', 'woman', ['woman'], { atConnectionLimit: true }),
    c('quiet', 'woman', ['woman'], { hasRecentIntroDiary: false }),
  ];
  const pick = (excluded: string[] = [], last: Record<string, string> = {}) =>
    pickIntroductions({ me, candidates, dayKey: '2026-10-01', excluded: new Set(excluded), lastIntroduced: last });
  const a = pick();
  assert.equal(a.length, 3);
  for (const bad of ['m1', 'sleep', 'full', 'quiet']) assert.ok(!a.includes(bad));
  assert.deepEqual(pick(), a);
  const ws = Array.from({ length: 8 }, (_, i) => `w${i}`);
  assert.deepEqual(pick(ws), ['m0']);
  assert.deepEqual(pick(ws, { m0: '2026-09-20' }), []);
  assert.deepEqual(pick(ws, { m0: '2026-08-01' }), ['m0']);
});
