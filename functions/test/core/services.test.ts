import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MemoryDb } from '../../src/core/memory-db.ts';
import * as S from '../../src/core/services.ts';
import type { Context } from '../../src/core/services.ts';
import { LIMITS } from '../../src/core/rules.ts';

function setup(opts: { requireAge?: boolean } = {}) {
  const db = new MemoryDb();
  let t = Date.UTC(2026, 9, 1, 3); // 12:00 JST
  let n = 0;
  const ctx: Context = {
    db,
    now: () => new Date(t),
    newId: () => `id${++n}`,
    requireAgeVerification: opts.requireAge ?? false,
  };
  const advance = (ms: number) => { t += ms; };
  return { db, ctx, advance };
}

type G = 'woman' | 'man' | 'nonbinary' | 'unspecified';
async function person(ctx: Context, uid: string, gender: G, seeking: string[], diary = '帰り道、遠回りして金木犀を探した。香りだけが先に届いた。') {
  await S.saveProfile(ctx, uid, { penName: uid, ageBand: '30代前半', prefecture: '東京都', bio: '', gender, seeking });
  const { id } = await S.writeDiary(ctx, uid, { body: diary, scope: 'intro' });
  return id;
}

/** Letters require an introduction; tests grant it directly. */
function send(ctx: Context, from: string, input: Record<string, unknown>) {
  const db = ctx.db as MemoryDb;
  const author = db.diaries.get(input['diaryId'] as string)?.authorId;
  if (author) db.access.set(`${from}_${author}`, new Date(ctx.now().getTime() + 86400000));
  return S.sendLetter(ctx, from, input);
}

async function rejects(p: Promise<unknown>, code: S.ErrorCode) {
  await assert.rejects(p, (e: unknown) => e instanceof S.ServiceError && e.code === code);
}

const LETTER = '私も秋は遠回りしたくなります。';
const QUOTE = '香りだけが先に届いた。';

test('unauthenticated calls are rejected', async () => {
  const { ctx } = setup();
  await rejects(S.writeDiary(ctx, null, { body: 'x', scope: 'private' }), 'unauthenticated');
});

test('profile validation blocks contact info and bad enums', async () => {
  const { ctx } = setup();
  await rejects(S.saveProfile(ctx, 'a', { penName: '@myhandle', ageBand: '30代前半', prefecture: '東京都', gender: 'woman', seeking: ['man'] }), 'invalid-argument');
  await rejects(S.saveProfile(ctx, 'a', { penName: 'a', ageBand: '12歳', prefecture: '東京都', gender: 'woman', seeking: ['man'] }), 'invalid-argument');
  await rejects(S.saveProfile(ctx, 'a', { penName: 'a', ageBand: '30代前半', prefecture: '東京都', gender: 'woman', seeking: [] }), 'invalid-argument');
  await rejects(S.saveProfile(ctx, 'a', { penName: 'a', ageBand: '30代前半', prefecture: '東京都', gender: 'woman', seeking: ['unspecified'] }), 'invalid-argument');
});

test('intro diaries may not carry contact info; private ones may', async () => {
  const { ctx } = setup();
  await person(ctx, 'a', 'woman', ['man']);
  await rejects(S.writeDiary(ctx, 'a', { body: 'インスタ見てね', scope: 'intro' }), 'invalid-argument');
  await S.writeDiary(ctx, 'a', { body: 'インスタ見てね', scope: 'private' });
});

test('letter → accept → connection → pages', async () => {
  const { ctx, db } = setup();
  const diary = await person(ctx, 'b', 'man', ['woman']);
  await person(ctx, 'a', 'woman', ['man']);
  const { id } = await send(ctx, 'a', { diaryId: diary, quote: QUOTE, body: LETTER });
  assert.equal(db.letters.get(id)?.status, 'pending');
  assert.ok(db.access.has('b_a'), 'recipient may read the sender while deciding');
  await rejects(send(ctx, 'a', { diaryId: diary, quote: QUOTE, body: LETTER }), 'failed-precondition');
  await rejects(S.respondToLetter(ctx, 'a', { letterId: id, accept: true }), 'failed-precondition'); // not the recipient
  const { connectionId } = await S.respondToLetter(ctx, 'b', { letterId: id, accept: true });
  assert.equal(connectionId, 'a_b');
  assert.equal(db.letters.get(id)?.status, 'accepted');
  const page = await S.writePage(ctx, 'a', { connectionId, body: '今日は雨でした。' });
  await S.replyToPage(ctx, 'b', { connectionId, pageId: page.id, body: '傘、持っていましたか。' });
  assert.equal(db.pages.get(`a_b/${page.id}`)?.replies.length, 1);
  await rejects(S.writePage(ctx, 'c', { connectionId, body: '横から' }), 'failed-precondition'); // no profile
});

test('letters only between mutually compatible people', async () => {
  const { ctx } = setup();
  const diary = await person(ctx, 'b', 'woman', ['woman']);
  await person(ctx, 'a', 'man', ['woman']);
  await rejects(send(ctx, 'a', { diaryId: diary, quote: QUOTE, body: LETTER }), 'not-found');
});

test('only intro diaries can be written to', async () => {
  const { ctx } = setup();
  await person(ctx, 'b', 'man', ['woman']);
  await person(ctx, 'a', 'woman', ['man']);
  const { id } = await S.writeDiary(ctx, 'b', { body: QUOTE, scope: 'private' });
  await rejects(send(ctx, 'a', { diaryId: id, quote: QUOTE, body: LETTER }), 'not-found');
});

test('three pending letters at most; expired ones stop counting', async () => {
  const { ctx, advance } = setup();
  await person(ctx, 'a', 'woman', ['woman']);
  const diaries: string[] = [];
  for (const u of ['b', 'c', 'd', 'e']) diaries.push(await person(ctx, u, 'woman', ['woman']));
  for (const d of diaries.slice(0, 3)) await send(ctx, 'a', { diaryId: d, quote: QUOTE, body: LETTER });
  await rejects(send(ctx, 'a', { diaryId: diaries[3]!, quote: QUOTE, body: LETTER }), 'resource-exhausted');
  advance(LIMITS.letterLifetimeMs + 1);
  await send(ctx, 'a', { diaryId: diaries[3]!, quote: QUOTE, body: LETTER });
});

test('declining closes silently; the sender sees the same "closed" as expiry', async () => {
  const { ctx, db, advance } = setup();
  const d1 = await person(ctx, 'b', 'man', ['woman']);
  const d2 = await person(ctx, 'c', 'man', ['woman']);
  await person(ctx, 'a', 'woman', ['man']);
  const declined = await send(ctx, 'a', { diaryId: d1, quote: QUOTE, body: LETTER });
  const expired = await send(ctx, 'a', { diaryId: d2, quote: QUOTE, body: LETTER });
  await S.respondToLetter(ctx, 'b', { letterId: declined.id, accept: false });
  advance(LIMITS.letterLifetimeMs + 1);
  const r = await S.expireStale(ctx);
  assert.equal(r.letters, 1);
  const a = db.letters.get(declined.id)!;
  const b = db.letters.get(expired.id)!;
  assert.equal(a.status, 'closed');
  assert.equal(b.status, 'closed');
  assert.deepEqual(Object.keys(a).sort(), Object.keys(b).sort());
  await rejects(S.respondToLetter(ctx, 'c', { letterId: expired.id, accept: true }), 'failed-precondition');
});

test('connection cap applies to both sides', async () => {
  const { ctx, db } = setup();
  const hubDiary = await person(ctx, 'hub', 'woman', ['woman']);
  for (const u of ['x1', 'x2', 'x3', 'x4']) await person(ctx, u, 'woman', ['woman']);
  for (const u of ['x1', 'x2', 'x3']) {
    const { id } = await send(ctx, u, { diaryId: hubDiary, quote: QUOTE, body: LETTER });
    await S.respondToLetter(ctx, 'hub', { letterId: id, accept: true });
  }
  const { id } = await send(ctx, 'x4', { diaryId: hubDiary, quote: QUOTE, body: LETTER });
  await rejects(S.respondToLetter(ctx, 'hub', { letterId: id, accept: true }), 'resource-exhausted');
  assert.equal([...db.connections.values()].filter((c) => c.status === 'active').length, 3);
});

test('photos: need own photo, only the other side consents, then both revealed', async () => {
  const { ctx } = setup();
  const d = await person(ctx, 'b', 'man', ['woman']);
  await person(ctx, 'a', 'woman', ['man']);
  const { id } = await send(ctx, 'a', { diaryId: d, quote: QUOTE, body: LETTER });
  const { connectionId } = await S.respondToLetter(ctx, 'b', { letterId: id, accept: true });
  await rejects(S.proposePhotos(ctx, 'a', { connectionId }), 'failed-precondition'); // no photo yet
  await S.markPhoto(ctx, 'a', true);
  await S.markPhoto(ctx, 'b', true);
  await S.proposePhotos(ctx, 'a', { connectionId });
  await rejects(S.consentPhotos(ctx, 'a', { connectionId }), 'failed-precondition');
  await rejects(S.revealedPhotoPath(ctx, 'a', { connectionId }), 'permission-denied');
  await S.consentPhotos(ctx, 'b', { connectionId });
  assert.deepEqual(await S.revealedPhotoPath(ctx, 'a', { connectionId }), { path: 'photos/b/profile.jpg' });
  assert.deepEqual(await S.revealedPhotoPath(ctx, 'b', { connectionId }), { path: 'photos/a/profile.jpg' });
  await rejects(S.revealedPhotoPath(ctx, 'c', { connectionId }), 'not-found');
  await S.endConnection(ctx, 'b', { connectionId });
  await rejects(S.revealedPhotoPath(ctx, 'a', { connectionId }), 'failed-precondition');
});

test('stale photo proposals quietly reset after 30 days', async () => {
  const { ctx, db, advance } = setup();
  const d = await person(ctx, 'b', 'man', ['woman']);
  await person(ctx, 'a', 'woman', ['man']);
  const { id } = await send(ctx, 'a', { diaryId: d, quote: QUOTE, body: LETTER });
  const { connectionId } = await S.respondToLetter(ctx, 'b', { letterId: id, accept: true });
  await S.markPhoto(ctx, 'a', true);
  await S.proposePhotos(ctx, 'a', { connectionId });
  advance(LIMITS.photoProposalLifetimeMs + 1);
  assert.equal((await S.expireStale(ctx)).proposals, 1);
  assert.equal(db.connections.get(connectionId!)?.photo.state, 'hidden');
});

test('report blocks, ends the connection and closes letters', async () => {
  const { ctx, db } = setup();
  const d = await person(ctx, 'b', 'man', ['woman']);
  await person(ctx, 'a', 'woman', ['man']);
  const { id } = await send(ctx, 'a', { diaryId: d, quote: QUOTE, body: LETTER });
  const { connectionId } = await S.respondToLetter(ctx, 'b', { letterId: id, accept: true });
  await S.report(ctx, 'a', { targetId: 'b', category: 'harassment', context: 'page', note: '怖い言い方をされた' });
  assert.equal(db.connections.get(connectionId!)?.status, 'ended');
  assert.ok(db.blocks.has('a/b'));
  assert.equal(db.reports.length, 1);
  await rejects(S.writePage(ctx, 'b', { connectionId, body: 'まだいる？' }), 'failed-precondition');
  await rejects(S.report(ctx, 'a', { targetId: 'b', category: 'nope', context: 'page' }), 'invalid-argument');
});

test('blocked people cannot write letters to each other', async () => {
  const { ctx } = setup();
  const d = await person(ctx, 'b', 'man', ['woman']);
  await person(ctx, 'a', 'woman', ['man']);
  await S.block(ctx, 'b', { targetId: 'a' });
  await rejects(send(ctx, 'a', { diaryId: d, quote: QUOTE, body: LETTER }), 'not-found');
});

test('age verification gate', async () => {
  const { ctx, db } = setup({ requireAge: true });
  const d = await person(ctx, 'b', 'man', ['woman']);
  await person(ctx, 'a', 'woman', ['man']);
  await rejects(send(ctx, 'a', { diaryId: d, quote: QUOTE, body: LETTER }), 'failed-precondition');
  db.users.get('a')!.ageVerified = true;
  await rejects(send(ctx, 'a', { diaryId: d, quote: QUOTE, body: LETTER }), 'not-found'); // b unverified
  db.users.get('b')!.ageVerified = true;
  await send(ctx, 'a', { diaryId: d, quote: QUOTE, body: LETTER });
});

test('daily introductions: mutual, excludes relations and paused, records history', async () => {
  const { ctx, db } = setup();
  await person(ctx, 'me', 'woman', ['woman', 'man']);
  for (const u of ['w1', 'w2', 'w3', 'w4']) await person(ctx, u, 'woman', ['woman']);
  await person(ctx, 'm1', 'man', ['man']);
  await person(ctx, 'sleepy', 'woman', ['woman']);
  await S.setPaused(ctx, 'sleepy', { paused: true });
  await S.block(ctx, 'w4', { targetId: 'me' });
  const n = await S.computeIntroductions(ctx);
  assert.ok(n > 0);
  const mine = db.intros.get('me/2026-10-01')!;
  assert.equal(mine.length, 3);
  for (const bad of ['m1', 'sleepy', 'w4', 'me']) assert.ok(!mine.includes(bad), bad);
  for (const id of mine) {
    assert.equal(db.history.get('me')![id], '2026-10-01');
    assert.ok(db.access.get(`me_${id}`)! > ctx.now(), 'introduced writer is readable');
  }
});

test('deleting an account ends relationships and removes own documents', async () => {
  const { ctx, db } = setup();
  const d = await person(ctx, 'b', 'man', ['woman']);
  await person(ctx, 'a', 'woman', ['man']);
  const { id } = await send(ctx, 'a', { diaryId: d, quote: QUOTE, body: LETTER });
  const { connectionId } = await S.respondToLetter(ctx, 'b', { letterId: id, accept: true });
  await S.deleteAccount(ctx, 'a');
  assert.equal(db.users.has('a'), false);
  assert.equal(db.profiles.has('a'), false);
  assert.equal([...db.diaries.values()].some((x) => x.authorId === 'a'), false);
  assert.equal(db.connections.get(connectionId!)?.status, 'ended');
});

test('memory db enforces reads before writes', async () => {
  const { db } = setup();
  await assert.rejects(db.run(async (tx) => {
    tx.setBlock('a', 'b', new Date());
    await tx.user('a');
  }), /read after write/);
});

test('ids that would change a Firestore path are rejected', async () => {
  const { ctx } = setup();
  await person(ctx, 'a', 'woman', ['man']);
  await rejects(S.block(ctx, 'a', { targetId: 'x/y/z' }), 'invalid-argument');
  await rejects(S.writePage(ctx, 'a', { connectionId: 'a_b/pages/p1', body: 'x' }), 'invalid-argument');
  await rejects(S.respondToLetter(ctx, 'a', { letterId: '__x__', accept: false }), 'invalid-argument');
  await rejects(send(ctx, 'a', { diaryId: '..', quote: QUOTE, body: LETTER }), 'invalid-argument');
});

test('letters and diary reads require an introduction, a letter or a connection', async () => {
  const { ctx, db } = setup();
  const d = await person(ctx, 'b', 'man', ['woman']);
  await person(ctx, 'a', 'woman', ['man']);
  await S.writeDiary(ctx, 'b', { body: 'ひみつ', scope: 'private' });
  await S.writeDiary(ctx, 'b', { body: 'つながった人へ', scope: 'connections' });
  await rejects(S.sendLetter(ctx, 'a', { diaryId: d, quote: QUOTE, body: LETTER }), 'not-found');
  await rejects(S.readDiaries(ctx, 'a', { authorId: 'b' }), 'permission-denied');

  db.access.set('a_b', new Date(ctx.now().getTime() + 1000));
  const intro = await S.readDiaries(ctx, 'a', { authorId: 'b' });
  assert.deepEqual(intro.diaries.map((x) => x.scope), ['intro']);

  const { id } = await S.sendLetter(ctx, 'a', { diaryId: d, quote: QUOTE, body: LETTER });
  assert.equal(db.access.get('a_b')!.getTime(), db.access.get('b_a')!.getTime()); // both granted for the same period
  await S.readDiaries(ctx, 'b', { authorId: 'a' }); // recipient may read the sender
  await S.respondToLetter(ctx, 'b', { letterId: id, accept: true });
  const connected = await S.readDiaries(ctx, 'a', { authorId: 'b' });
  assert.deepEqual(connected.diaries.map((x) => x.scope).sort(), ['connections', 'intro']);
  assert.equal((await S.readDiaries(ctx, 'b', { authorId: 'b' })).diaries.length, 3);

  await S.block(ctx, 'b', { targetId: 'a' });
  await rejects(S.readDiaries(ctx, 'a', { authorId: 'b' }), 'not-found');
});
