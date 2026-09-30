/**
 * Server-side use cases. Everything that protects the calm-by-design rules
 * (limits, mutual matching, photo consent, blocking) is enforced here, never
 * only in the app. Each use case reads everything first, then writes.
 */
import type { Db, Tx } from './db.ts';
import {
  AGE_BANDS, GENDERS, PREFECTURES, REPORT_CATEGORIES, REPORT_CONTEXTS, SCOPES, SEEKABLE,
  letterId, pairId, partnerOf,
} from './model.ts';
import type {
  ConnectionDoc, DiaryScope, Gender, LetterDoc, PageDoc, ReportCategory, ReportContext, Seekable, UserDoc,
} from './model.ts';
import {
  LIMITS, PhotoRules, charCount, containsContactInfo, hiddenPhoto, introDayKey, letterProblem,
  mutuallyCompatible, pickIntroductions,
} from './rules.ts';

export type ErrorCode =
  | 'unauthenticated'
  | 'invalid-argument'
  | 'not-found'
  | 'permission-denied'
  | 'failed-precondition'
  | 'resource-exhausted';

/** A failure whose message can be shown to the user as is. */
export class ServiceError extends Error {
  readonly code: ErrorCode;
  constructor(code: ErrorCode, message: string) {
    super(message);
    this.code = code;
    this.name = 'ServiceError';
  }
}

export interface Context {
  db: Db;
  now: () => Date;
  newId: () => string;
  /** Public builds require verified age before any contact with others. */
  requireAgeVerification: boolean;
}

function fail(code: ErrorCode, message: string): never {
  throw new ServiceError(code, message);
}

// ------------------------------------------------------------------ input

type Input = Record<string, unknown>;

function str(input: Input, key: string, opts: { max: number; min?: number; optional?: boolean }): string {
  const v = input[key];
  if (v === undefined || v === null) {
    if (opts.optional) return '';
    return fail('invalid-argument', `${key} がありません。`);
  }
  if (typeof v !== 'string') return fail('invalid-argument', `${key} が不正です。`);
  const t = v.trim();
  const n = charCount(t);
  if (n > opts.max) return fail('invalid-argument', `${opts.max}文字までです。`);
  if (n < (opts.min ?? 0)) return fail('invalid-argument', `${opts.min}文字以上で書いてください。`);
  return t;
}

/** A Firestore document id: no '/', not '.' or '..', not reserved '__x__' (they would change the path). */
function docId(input: Input, key: string, max: number): string {
  const v = str(input, key, { max, min: 1 });
  if (v.includes('/') || v === '.' || v === '..' || /^__.*__$/.test(v)) return fail('invalid-argument', `${key} が不正です。`);
  return v;
}

function oneOf<T extends string>(input: Input, key: string, values: readonly T[]): T {
  const v = input[key];
  if (typeof v !== 'string' || !(values as readonly string[]).includes(v)) {
    return fail('invalid-argument', `${key} が不正です。`);
  }
  return v as T;
}

function bool(input: Input, key: string): boolean {
  const v = input[key];
  if (typeof v !== 'boolean') return fail('invalid-argument', `${key} が不正です。`);
  return v;
}

function uidOf(uid: string | null | undefined): string {
  if (!uid) return fail('unauthenticated', 'ログインしてください。');
  return uid;
}

async function member(ctx: Context, tx: Tx, uid: string): Promise<UserDoc> {
  const u = await tx.user(uid);
  if (!u) return fail('failed-precondition', 'はじめにプロフィールを作成してください。');
  if (ctx.requireAgeVerification && !u.ageVerified) {
    return fail('failed-precondition', '年齢確認が済んでから使えます。');
  }
  return u;
}

async function blockedEitherWay(tx: Tx, a: string, b: string): Promise<boolean> {
  const [x, y] = await Promise.all([tx.blocked(a, b), tx.blocked(b, a)]);
  return x || y;
}

const isLive = (ctx: Context, l: LetterDoc): boolean =>
  l.status === 'pending' && ctx.now().getTime() - l.createdAt.getTime() < LIMITS.letterLifetimeMs;

// ---------------------------------------------------------------- profile

export async function saveProfile(ctx: Context, authUid: string | null, input: Input): Promise<void> {
  const uid = uidOf(authUid);
  const penName = str(input, 'penName', { max: LIMITS.penNameMax, min: 1 });
  const bio = str(input, 'bio', { max: LIMITS.bioMax, optional: true });
  const ageBand = oneOf(input, 'ageBand', AGE_BANDS);
  const prefecture = oneOf(input, 'prefecture', PREFECTURES);
  const gender = oneOf<Gender>(input, 'gender', GENDERS);
  const seekingRaw = input['seeking'];
  if (!Array.isArray(seekingRaw) || seekingRaw.length === 0) {
    fail('invalid-argument', '出会いたい相手を1つ以上選んでください。');
  }
  const seeking = [...new Set(seekingRaw as unknown[])].map((s) => {
    if (typeof s !== 'string' || !(SEEKABLE as readonly string[]).includes(s)) fail('invalid-argument', 'seeking が不正です。');
    return s as Seekable;
  });
  if (containsContactInfo(penName) || containsContactInfo(bio)) {
    fail('invalid-argument', 'プロフィールに連絡先やSNSのIDは書けません。');
  }
  await ctx.db.run(async (tx) => {
    const [existing, profile] = await Promise.all([tx.user(uid), tx.profile(uid)]);
    tx.setUser({
      uid,
      gender,
      seeking,
      paused: existing?.paused ?? false,
      ageVerified: existing?.ageVerified ?? false,
      createdAt: existing?.createdAt ?? ctx.now(),
      lastIntroDiaryAt: existing?.lastIntroDiaryAt ?? null,
    });
    tx.setProfile({ uid, penName, ageBand, prefecture, bio, hasPhoto: profile?.hasPhoto ?? false });
  });
}

export async function setPaused(ctx: Context, authUid: string | null, input: Input): Promise<void> {
  const uid = uidOf(authUid);
  const paused = bool(input, 'paused');
  await ctx.db.run(async (tx) => {
    const u = await tx.user(uid);
    if (!u) return fail('failed-precondition', 'はじめにプロフィールを作成してください。');
    tx.setUser({ ...u, paused });
  });
}

/** Called by the Storage trigger after a photo upload passes validation. */
export async function markPhoto(ctx: Context, uid: string, hasPhoto: boolean): Promise<void> {
  await ctx.db.run(async (tx) => {
    const p = await tx.profile(uid);
    if (p) tx.setProfile({ ...p, hasPhoto });
  });
}

// ----------------------------------------------------------------- diaries

export async function writeDiary(ctx: Context, authUid: string | null, input: Input): Promise<{ id: string }> {
  const uid = uidOf(authUid);
  const body = str(input, 'body', { max: LIMITS.diaryMax, min: 1 });
  const scope = oneOf<DiaryScope>(input, 'scope', SCOPES);
  const prompt = str(input, 'prompt', { max: 40, optional: true }) || null;
  if (scope !== 'private' && containsContactInfo(body)) {
    fail('invalid-argument', 'ほかの人が読む日記には、連絡先やSNSのIDは書けません。');
  }
  const id = ctx.newId();
  await ctx.db.run(async (tx) => {
    const u = await tx.user(uid);
    if (!u) return fail('failed-precondition', 'はじめにプロフィールを作成してください。');
    const now = ctx.now();
    tx.setDiary({ id, authorId: uid, body, scope, prompt, createdAt: now });
    if (scope === 'intro') tx.setUser({ ...u, lastIntroDiaryAt: now });
  });
  return { id };
}

export interface PublicDiary {
  id: string;
  body: string;
  scope: DiaryScope;
  prompt: string | null;
  createdAtMs: number;
}

/**
 * Another person's profile and readable diaries. Served by a function rather
 * than a client query so the introduction/connection/block checks cannot be
 * bypassed by listing the diaries collection.
 */
export async function readDiaries(
  ctx: Context, authUid: string | null, input: Input,
): Promise<{ profile: { penName: string; ageBand: string; prefecture: string; bio: string }; diaries: PublicDiary[] }> {
  const uid = uidOf(authUid);
  const authorId = docId(input, 'authorId', 128);
  return ctx.db.run(async (tx) => {
    await member(ctx, tx, uid);
    const [profile, diaries, blocked, conn, access] = await Promise.all([
      tx.profile(authorId),
      tx.diariesOf(authorId),
      authorId === uid ? Promise.resolve(false) : blockedEitherWay(tx, uid, authorId),
      tx.connection(pairId(uid, authorId)),
      tx.access(uid, authorId),
    ]);
    if (!profile || blocked) return fail('not-found', 'この人の日記は読めません。');
    const own = authorId === uid;
    const connected = conn?.status === 'active';
    const granted = access !== null && access > ctx.now();
    if (!own && !connected && !granted) return fail('permission-denied', 'この人の日記は読めません。');
    const visible = diaries.filter((d) =>
      own || d.scope === 'intro' || (connected && d.scope === 'connections'));
    return {
      profile: { penName: profile.penName, ageBand: profile.ageBand, prefecture: profile.prefecture, bio: profile.bio },
      diaries: visible.map((d) => ({
        id: d.id, body: d.body, scope: d.scope, prompt: d.prompt, createdAtMs: d.createdAt.getTime(),
      })),
    };
  });
}

// ----------------------------------------------------------------- letters

export async function sendLetter(ctx: Context, authUid: string | null, input: Input): Promise<{ id: string }> {
  const uid = uidOf(authUid);
  const diaryId = docId(input, 'diaryId', 128);
  const quote = str(input, 'quote', { max: LIMITS.diaryMax, min: 1 });
  const body = typeof input['body'] === 'string' ? (input['body'] as string) : '';
  return ctx.db.run(async (tx) => {
    const me = await member(ctx, tx, uid);
    const diary = await tx.diary(diaryId);
    if (!diary || diary.authorId === uid || diary.scope !== 'intro') return fail('not-found', 'この日記は見つかりませんでした。');
    const toId = diary.authorId;
    const [them, blocked, mine, theirs, conn, pending, active, access] = await Promise.all([
      tx.user(toId),
      blockedEitherWay(tx, uid, toId),
      tx.letter(letterId(uid, toId)),
      tx.letter(letterId(toId, uid)),
      tx.connection(pairId(uid, toId)),
      tx.pendingLettersFrom(uid),
      tx.activeConnectionsOf(uid),
      tx.access(uid, toId),
    ]);
    // Letters go only to people this user was introduced to.
    if (!access || access <= ctx.now()) return fail('not-found', 'この人には感想を送れません。');
    const unverified = ctx.requireAgeVerification && !them?.ageVerified;
    if (!them || unverified || blocked || them.paused || !mutuallyCompatible(me, them)) {
      return fail('not-found', 'この人には感想を送れません。');
    }
    if (mine || theirs || conn) return fail('failed-precondition', 'この人とは、すでにやりとりがあります。');
    if (pending.filter((l) => isLive(ctx, l)).length >= LIMITS.pendingLetters) {
      return fail('resource-exhausted', `返事を待っている感想が${LIMITS.pendingLetters}通あります。ひとつ落ち着いてから、また送れます。`);
    }
    if (active.length >= LIMITS.activeConnections) {
      return fail('resource-exhausted', `いまは${LIMITS.activeConnections}人とつながっています。今のつながりを大切にする期間です。`);
    }
    const problem = letterProblem(quote, body, diary.body);
    if (problem) return fail('invalid-argument', problem);
    const id = letterId(uid, toId);
    const now = ctx.now();
    tx.setLetter({
      id, fromId: uid, toId, participants: [uid, toId], diaryId, quote, body: body.trim(),
      status: 'pending', createdAt: now, closedAt: null,
    });
    // Both may read each other while the letter waits for an answer.
    const until = new Date(now.getTime() + LIMITS.letterLifetimeMs);
    tx.setAccess(toId, uid, until);
    tx.setAccess(uid, toId, until);
    return { id };
  });
}

/** "話したい" creates the connection; "見送る" closes the letter silently. */
export async function respondToLetter(
  ctx: Context, authUid: string | null, input: Input,
): Promise<{ connectionId: string | null }> {
  const uid = uidOf(authUid);
  const id = docId(input, 'letterId', 300);
  const accept = bool(input, 'accept');
  return ctx.db.run(async (tx) => {
    await member(ctx, tx, uid);
    const letter = await tx.letter(id);
    if (!letter || letter.toId !== uid || !isLive(ctx, letter)) {
      return fail('failed-precondition', 'この感想には、もう返事ができません。');
    }
    const fromId = letter.fromId;
    const [blocked, mine, theirs, existing] = await Promise.all([
      blockedEitherWay(tx, uid, fromId),
      tx.activeConnectionsOf(uid),
      tx.activeConnectionsOf(fromId),
      tx.connection(pairId(uid, fromId)),
    ]);
    if (!accept) {
      tx.setLetter({ ...letter, status: 'closed', closedAt: ctx.now() });
      return { connectionId: null };
    }
    if (blocked || existing) return fail('failed-precondition', 'この感想には、もう返事ができません。');
    if (mine.length >= LIMITS.activeConnections) {
      return fail('resource-exhausted', `つながりは同時に${LIMITS.activeConnections}人までです。どなたかとの関係を見直してから、また返事ができます。`);
    }
    if (theirs.length >= LIMITS.activeConnections) {
      return fail('resource-exhausted', 'いまはつながれません。少し時間をおいてから、また返事をしてください。');
    }
    const now = ctx.now();
    const connection: ConnectionDoc = {
      id: pairId(uid, fromId),
      members: [uid, fromId].sort() as [string, string],
      status: 'active',
      photo: hiddenPhoto(),
      createdAt: now,
      endedAt: null,
    };
    tx.setLetter({ ...letter, status: 'accepted', closedAt: now });
    tx.setConnection(connection);
    return { connectionId: connection.id };
  });
}

// ------------------------------------------------------------ connections

async function activeConnectionFor(tx: Tx, uid: string, connectionId: string): Promise<ConnectionDoc> {
  const c = await tx.connection(connectionId);
  if (!c || !c.members.includes(uid)) return fail('not-found', 'このつながりは見つかりませんでした。');
  if (c.status !== 'active') return fail('failed-precondition', 'この関係は終わっています。');
  return c;
}

export async function writePage(ctx: Context, authUid: string | null, input: Input): Promise<{ id: string }> {
  const uid = uidOf(authUid);
  const connectionId = docId(input, 'connectionId', 300);
  const body = str(input, 'body', { max: LIMITS.pageMax, min: 1 });
  const id = ctx.newId();
  await ctx.db.run(async (tx) => {
    await member(ctx, tx, uid);
    await activeConnectionFor(tx, uid, connectionId);
    tx.setPage({ id, connectionId, authorId: uid, body, createdAt: ctx.now(), replies: [] });
  });
  return { id };
}

export async function replyToPage(ctx: Context, authUid: string | null, input: Input): Promise<void> {
  const uid = uidOf(authUid);
  const connectionId = docId(input, 'connectionId', 300);
  const pageId = docId(input, 'pageId', 128);
  const body = str(input, 'body', { max: LIMITS.pageMax, min: 1 });
  await ctx.db.run(async (tx) => {
    await member(ctx, tx, uid);
    await activeConnectionFor(tx, uid, connectionId);
    const page: PageDoc | null = await tx.page(connectionId, pageId);
    if (!page) return fail('not-found', 'このページは見つかりませんでした。');
    if (page.replies.length >= LIMITS.repliesPerPage) {
      return fail('resource-exhausted', 'このページには、もう返事を添えられません。新しいページに書いてみてください。');
    }
    tx.setPage({ ...page, replies: [...page.replies, { authorId: uid, body, createdAt: ctx.now() }] });
  });
}

export async function endConnection(ctx: Context, authUid: string | null, input: Input): Promise<void> {
  const uid = uidOf(authUid);
  const connectionId = docId(input, 'connectionId', 300);
  await ctx.db.run(async (tx) => {
    const c = await tx.connection(connectionId);
    if (!c || !c.members.includes(uid)) return fail('not-found', 'このつながりは見つかりませんでした。');
    if (c.status === 'ended') return;
    tx.setConnection({ ...c, status: 'ended', endedAt: ctx.now() });
  });
}

// ------------------------------------------------------------------ photos

export async function proposePhotos(ctx: Context, authUid: string | null, input: Input): Promise<void> {
  const uid = uidOf(authUid);
  const connectionId = docId(input, 'connectionId', 300);
  await ctx.db.run(async (tx) => {
    await member(ctx, tx, uid);
    const c = await activeConnectionFor(tx, uid, connectionId);
    const profile = await tx.profile(uid);
    if (!profile?.hasPhoto) return fail('failed-precondition', '先に、あなたの写真を登録してください。');
    if (!PhotoRules.canPropose(c)) return fail('failed-precondition', 'いまは提案できません。');
    tx.setConnection({ ...c, photo: { state: 'proposed', proposedBy: uid, proposedAt: ctx.now(), revealedAt: null } });
  });
}

export async function cancelPhotoProposal(ctx: Context, authUid: string | null, input: Input): Promise<void> {
  const uid = uidOf(authUid);
  const connectionId = docId(input, 'connectionId', 300);
  await ctx.db.run(async (tx) => {
    const c = await activeConnectionFor(tx, uid, connectionId);
    if (!PhotoRules.canCancel(c, uid)) return fail('failed-precondition', 'この提案は取り消せません。');
    tx.setConnection({ ...c, photo: hiddenPhoto() });
  });
}

/** The other member's consent reveals both photos at the same moment. */
export async function consentPhotos(ctx: Context, authUid: string | null, input: Input): Promise<void> {
  const uid = uidOf(authUid);
  const connectionId = docId(input, 'connectionId', 300);
  await ctx.db.run(async (tx) => {
    await member(ctx, tx, uid);
    const c = await activeConnectionFor(tx, uid, connectionId);
    const [mine, theirs] = await Promise.all([tx.profile(uid), tx.profile(partnerOf(c, uid))]);
    if (!mine?.hasPhoto) return fail('failed-precondition', '先に、あなたの写真を登録してください。');
    if (!PhotoRules.canConsent(c, uid)) return fail('failed-precondition', 'いまは同意できません。');
    if (!theirs?.hasPhoto) return fail('failed-precondition', 'いまは公開できません。');
    tx.setConnection({ ...c, photo: { ...c.photo, state: 'revealed', revealedAt: ctx.now() } });
  });
}

/** Returns the Storage path of the partner's photo, only after the reveal. */
export async function revealedPhotoPath(ctx: Context, authUid: string | null, input: Input): Promise<{ path: string }> {
  const uid = uidOf(authUid);
  const connectionId = docId(input, 'connectionId', 300);
  return ctx.db.run(async (tx) => {
    const c = await activeConnectionFor(tx, uid, connectionId);
    const partner = partnerOf(c, uid);
    if (await blockedEitherWay(tx, uid, partner)) return fail('not-found', 'このつながりは見つかりませんでした。');
    if (!PhotoRules.visible(c)) return fail('permission-denied', '写真はまだ公開されていません。');
    return { path: photoPath(partner) };
  });
}

export const photoPath = (uid: string): string => `photos/${uid}/profile.jpg`;

// ------------------------------------------------------------------ safety

async function closeEverythingWith(ctx: Context, tx: Tx, uid: string, other: string): Promise<void> {
  const [conn, a, b] = await Promise.all([
    tx.connection(pairId(uid, other)),
    tx.letter(letterId(uid, other)),
    tx.letter(letterId(other, uid)),
  ]);
  const now = ctx.now();
  tx.setBlock(uid, other, now);
  if (conn && conn.status === 'active') tx.setConnection({ ...conn, status: 'ended', endedAt: now });
  for (const l of [a, b]) {
    if (l && l.status === 'pending') tx.setLetter({ ...l, status: 'closed', closedAt: now });
  }
}

export async function block(ctx: Context, authUid: string | null, input: Input): Promise<void> {
  const uid = uidOf(authUid);
  const targetId = docId(input, 'targetId', 128);
  if (targetId === uid) fail('invalid-argument', '自分はブロックできません。');
  await ctx.db.run((tx) => closeEverythingWith(ctx, tx, uid, targetId));
}

/** Reporting always blocks too, so the reporter is never exposed again. */
export async function report(ctx: Context, authUid: string | null, input: Input): Promise<{ id: string }> {
  const uid = uidOf(authUid);
  const targetId = docId(input, 'targetId', 128);
  if (targetId === uid) fail('invalid-argument', '自分は通報できません。');
  const category = oneOf<ReportCategory>(input, 'category', REPORT_CATEGORIES);
  const context = oneOf<ReportContext>(input, 'context', REPORT_CONTEXTS);
  const note = str(input, 'note', { max: LIMITS.reportNoteMax, optional: true });
  const id = ctx.newId();
  await ctx.db.run(async (tx) => {
    // Reads inside closeEverythingWith happen before any write below.
    const now = ctx.now();
    await closeEverythingWith(ctx, tx, uid, targetId);
    tx.addReport({ id, reporterId: uid, targetId, context, category, note, createdAt: now, status: 'open' });
  });
  return { id };
}

/** Ends every relationship, then removes the user's own documents. */
export async function deleteAccount(ctx: Context, authUid: string | null): Promise<void> {
  const uid = uidOf(authUid);
  await ctx.db.run(async (tx) => {
    const [conns, out, inc] = await Promise.all([
      tx.activeConnectionsOf(uid), tx.pendingLettersFrom(uid), tx.pendingLettersTo(uid),
    ]);
    const now = ctx.now();
    for (const c of conns) tx.setConnection({ ...c, status: 'ended', endedAt: now });
    for (const l of [...out, ...inc]) tx.setLetter({ ...l, status: 'closed', closedAt: now });
  });
  await ctx.db.deleteUserData(uid);
}

// --------------------------------------------------------------- scheduled

/** Daily at 05:00 JST. Returns how many users received introductions. */
export async function computeIntroductions(ctx: Context): Promise<number> {
  const now = ctx.now();
  const dayKey = introDayKey(now);
  const pool = await ctx.db.introPool(new Date(now.getTime() - LIMITS.activeWriterWindowMs));
  const candidates = pool
    .filter((e) => !ctx.requireAgeVerification || e.user.ageVerified)
    .map((e) => ({
      uid: e.user.uid,
      gender: e.user.gender,
      seeking: e.user.seeking,
      paused: e.user.paused,
      hasRecentIntroDiary: true,
      atConnectionLimit: e.activeConnections >= LIMITS.activeConnections,
    }));
  let count = 0;
  for (const entry of pool) {
    if (ctx.requireAgeVerification && !entry.user.ageVerified) continue;
    const ids = pickIntroductions({
      me: entry.user,
      candidates,
      dayKey,
      excluded: entry.related,
      lastIntroduced: entry.lastIntroduced,
    });
    const last = { ...entry.lastIntroduced };
    for (const id of ids) last[id] = dayKey;
    await ctx.db.saveIntroductions(entry.user.uid, dayKey, ids, last, new Date(now.getTime() + LIMITS.introAccessMs));
    if (ids.length > 0) count++;
  }
  return count;
}

/** Hourly: close unanswered letters and stale photo proposals quietly. */
export async function expireStale(ctx: Context): Promise<{ letters: number; proposals: number }> {
  const now = ctx.now();
  const letters = await ctx.db.pendingLettersBefore(new Date(now.getTime() - LIMITS.letterLifetimeMs));
  for (const l of letters) {
    await ctx.db.run(async (tx) => {
      const fresh = await tx.letter(l.id);
      if (fresh && fresh.status === 'pending') tx.setLetter({ ...fresh, status: 'closed', closedAt: now });
    });
  }
  const proposals = await ctx.db.photoProposalsBefore(new Date(now.getTime() - LIMITS.photoProposalLifetimeMs));
  for (const c of proposals) {
    await ctx.db.run(async (tx) => {
      const fresh = await tx.connection(c.id);
      if (fresh && fresh.photo.state === 'proposed') tx.setConnection({ ...fresh, photo: hiddenPhoto() });
    });
  }
  return { letters: letters.length, proposals: proposals.length };
}
