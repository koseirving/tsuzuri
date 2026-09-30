/** Calm-by-design rules. Mirrors lib/src/domain/rules.dart in the app. */
import type { Gender, PhotoInfo, ConnectionDoc, Seekable } from './model.ts';

export const LIMITS = {
  introsPerDay: 3,
  pendingLetters: 3,
  activeConnections: 3,
  letterMin: 10,
  letterMax: 400,
  diaryMax: 2000,
  pageMax: 2000,
  repliesPerPage: 20,
  penNameMax: 16,
  bioMax: 120,
  reportNoteMax: 1000,
  letterLifetimeMs: 14 * 24 * 3600 * 1000,
  photoProposalLifetimeMs: 30 * 24 * 3600 * 1000,
  introCooldownDays: 30,
  /** An introduced writer's diaries stay readable for two days. */
  introAccessMs: 2 * 24 * 3600 * 1000,
  activeWriterWindowMs: 30 * 24 * 3600 * 1000,
} as const;

export interface Person {
  uid: string;
  gender: Gender;
  seeking: readonly Seekable[];
}

const ALL: readonly Seekable[] = ['woman', 'man', 'nonbinary'];

/** "回答しない" is only met by people open to everyone. */
export function wantsToMeet(a: Person, b: Person): boolean {
  if (b.gender === 'unspecified') return ALL.every((g) => a.seeking.includes(g));
  return a.seeking.includes(b.gender);
}

export const mutuallyCompatible = (a: Person, b: Person): boolean =>
  a.uid !== b.uid && wantsToMeet(a, b) && wantsToMeet(b, a);

/** The introduction day rolls over at 05:00 JST (UTC+9, no DST). */
export function introDayKey(now: Date): string {
  const t = new Date(now.getTime() + (9 - 5) * 3600 * 1000);
  return t.toISOString().slice(0, 10);
}

export const dayDistance = (from: string, to: string): number =>
  Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86400000);

export function stableHash(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

function seededShuffle<T>(items: T[], seed: number): T[] {
  const a = [...items];
  let x = seed || 1;
  for (let i = a.length - 1; i > 0; i--) {
    x = (Math.imul(x, 1103515245) + 12345) >>> 0;
    const j = x % (i + 1);
    [a[i], a[j]] = [a[j]!, a[i]!];
  }
  return a;
}

export interface Candidate extends Person {
  paused: boolean;
  hasRecentIntroDiary: boolean;
  atConnectionLimit: boolean;
}

/** No personality scoring: eligibility filters, then a deterministic shuffle per user and day. */
export function pickIntroductions(args: {
  me: Person;
  candidates: readonly Candidate[];
  dayKey: string;
  excluded: ReadonlySet<string>;
  lastIntroduced: Readonly<Record<string, string>>;
}): string[] {
  const { me, candidates, dayKey, excluded, lastIntroduced } = args;
  const eligible = candidates
    .filter((p) => {
      if (p.paused || excluded.has(p.uid)) return false;
      if (!mutuallyCompatible(me, p)) return false;
      if (!p.hasRecentIntroDiary || p.atConnectionLimit) return false;
      const last = lastIntroduced[p.uid];
      if (last !== undefined && last !== dayKey && dayDistance(last, dayKey) < LIMITS.introCooldownDays) return false;
      return true;
    })
    .map((p) => p.uid)
    .sort();
  return seededShuffle(eligible, stableHash(`${dayKey}/${me.uid}`)).slice(0, LIMITS.introsPerDay);
}

function halfWidth(s: string): string {
  let out = '';
  for (const ch of s) {
    const r = ch.codePointAt(0)!;
    if (r >= 0xff01 && r <= 0xff5e) out += String.fromCodePoint(r - 0xfee0);
    else if (r === 0x3000) out += ' ';
    else if (r === 0x2010 || r === 0x2212) out += '-';
    else out += ch;
  }
  return out;
}

const EMAIL = /[\w.+-]+@[\w-]+\.[\w.]+/;
const URL_RE = /(https?:\/\/|www\.|\b[\w-]+\.(com|jp|net|org|me|io|co)\b)/i;
const HANDLE = /@[a-z0-9_.]{3,}/i;
const SNS = /(instagram|インスタ|twitter|ツイッター|discord|ディスコード|kakao|カカオ|telegram|テレグラム|tiktok|ティックトック)/i;
const LINE = /(line|ライン|らいん)\s*(id|アイディ|交換|教え|追加|で話)/i;
const DIGIT_RUN = /\d[\d\s\-ー]{8,}\d/g;

/** Contact details must not be exchanged before connecting. */
export function containsContactInfo(text: string): boolean {
  const t = halfWidth(text);
  if (EMAIL.test(t) || URL_RE.test(t) || HANDLE.test(t) || SNS.test(t) || LINE.test(t)) return true;
  for (const m of t.matchAll(DIGIT_RUN)) {
    if (m[0].replace(/\D/g, '').length >= 10) return true;
  }
  return false;
}

/** Splits a diary into quotable sentences; 「」 and 『』 are not split inside. */
export function splitSentences(body: string): string[] {
  const out: string[] = [];
  let buf = '';
  let depth = 0;
  for (const ch of body) {
    if (ch === '「' || ch === '『') depth++;
    if ((ch === '」' || ch === '』') && depth > 0) depth--;
    if (ch === '\n') depth = 0;
    if (ch !== '\n') buf += ch;
    if ('。！？!?\n'.includes(ch) && depth === 0) {
      if (buf.trim()) out.push(buf.trim());
      buf = '';
    }
  }
  if (buf.trim()) out.push(buf.trim());
  return out;
}

export const charCount = (s: string): number => [...s.trim()].length;

/** Returns a user-facing reason, or null when the letter may be sent. */
export function letterProblem(quote: string, body: string, diaryBody: string): string | null {
  if (!quote || !diaryBody.includes(quote)) return '日記の中から一文を選んでください。';
  const n = charCount(body);
  if (n < LIMITS.letterMin) return `感想は${LIMITS.letterMin}文字以上で書いてください。`;
  if (n > LIMITS.letterMax) return `感想は${LIMITS.letterMax}文字までです。`;
  if (containsContactInfo(body)) {
    return 'つながる前の連絡先の交換は控えてください。電話番号・メールアドレス・URL・SNSのIDを消してから送れます。';
  }
  return null;
}

export const PhotoRules = {
  canPropose: (c: ConnectionDoc): boolean => c.status === 'active' && c.photo.state === 'hidden',
  canCancel: (c: ConnectionDoc, uid: string): boolean =>
    c.status === 'active' && c.photo.state === 'proposed' && c.photo.proposedBy === uid,
  canConsent: (c: ConnectionDoc, uid: string): boolean =>
    c.status === 'active' &&
    c.photo.state === 'proposed' &&
    c.photo.proposedBy !== null &&
    c.photo.proposedBy !== uid &&
    c.members.includes(uid),
  visible: (c: ConnectionDoc): boolean => c.status === 'active' && c.photo.state === 'revealed',
};

export const hiddenPhoto = (): PhotoInfo => ({ state: 'hidden', proposedBy: null, proposedAt: null, revealedAt: null });
