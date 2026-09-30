/** Firestore document shapes. Keep in sync with firestore.rules and docs/DESIGN.md. */

export type Gender = 'woman' | 'man' | 'nonbinary' | 'unspecified';
export type Seekable = 'woman' | 'man' | 'nonbinary';
export type DiaryScope = 'intro' | 'connections' | 'private';
/** Declined and expired look identical to the sender: both are 'closed'. */
export type LetterStatus = 'pending' | 'accepted' | 'closed';
export type ConnectionStatus = 'active' | 'ended';
export type PhotoState = 'hidden' | 'proposed' | 'revealed';
export type ReportCategory = 'impersonation' | 'solicitation' | 'sexual' | 'harassment' | 'minor' | 'other';
export type ReportContext = 'letter' | 'page' | 'diary' | 'profile';

export const GENDERS: readonly Gender[] = ['woman', 'man', 'nonbinary', 'unspecified'];
export const SEEKABLE: readonly Seekable[] = ['woman', 'man', 'nonbinary'];
export const SCOPES: readonly DiaryScope[] = ['intro', 'connections', 'private'];
export const REPORT_CATEGORIES: readonly ReportCategory[] = [
  'impersonation', 'solicitation', 'sexual', 'harassment', 'minor', 'other',
];
export const REPORT_CONTEXTS: readonly ReportContext[] = ['letter', 'page', 'diary', 'profile'];
export const PREFECTURES: readonly string[] = (
  '北海道 青森県 岩手県 宮城県 秋田県 山形県 福島県 茨城県 栃木県 群馬県 埼玉県 千葉県 東京都 神奈川県 ' +
  '新潟県 富山県 石川県 福井県 山梨県 長野県 岐阜県 静岡県 愛知県 三重県 滋賀県 京都府 大阪府 兵庫県 ' +
  '奈良県 和歌山県 鳥取県 島根県 岡山県 広島県 山口県 徳島県 香川県 愛媛県 高知県 福岡県 佐賀県 長崎県 ' +
  '熊本県 大分県 宮崎県 鹿児島県 沖縄県'
).split(' ');
export const AGE_BANDS: readonly string[] = ['20代前半', '20代後半', '30代前半', '30代後半', '40代', '50代', '60代以上'];

/** users/{uid} — private to the owner. */
export interface UserDoc {
  uid: string;
  gender: Gender;
  seeking: Seekable[];
  paused: boolean;
  ageVerified: boolean;
  createdAt: Date;
  /** Last time an intro-scope diary was written; drives introduction eligibility. */
  lastIntroDiaryAt: Date | null;
}

/** profiles/{uid} — readable by signed-in members unless blocked. No gender here. */
export interface ProfileDoc {
  uid: string;
  penName: string;
  ageBand: string;
  prefecture: string;
  bio: string;
  /** Storage object path. Never exposed as a URL until photos are revealed. */
  hasPhoto: boolean;
}

export interface DiaryDoc {
  id: string;
  authorId: string;
  body: string;
  scope: DiaryScope;
  prompt: string | null;
  createdAt: Date;
}

/** letters/{from}_{to} — one letter per direction, ever. */
export interface LetterDoc {
  id: string;
  fromId: string;
  toId: string;
  participants: [string, string];
  diaryId: string;
  quote: string;
  body: string;
  status: LetterStatus;
  createdAt: Date;
  closedAt: Date | null;
}

export interface PhotoInfo {
  state: PhotoState;
  proposedBy: string | null;
  proposedAt: Date | null;
  revealedAt: Date | null;
}

/** connections/{a}_{b} with sorted uids — one per pair, ever. */
export interface ConnectionDoc {
  id: string;
  members: [string, string];
  status: ConnectionStatus;
  photo: PhotoInfo;
  createdAt: Date;
  endedAt: Date | null;
}

export interface PageReply {
  authorId: string;
  body: string;
  createdAt: Date;
}

/** connections/{cid}/pages/{pid} */
export interface PageDoc {
  id: string;
  connectionId: string;
  authorId: string;
  body: string;
  createdAt: Date;
  replies: PageReply[];
}

/** reports/{id} — write-only for clients (through functions), read by operators. */
export interface ReportDoc {
  id: string;
  reporterId: string;
  targetId: string;
  context: ReportContext;
  category: ReportCategory;
  note: string;
  createdAt: Date;
  status: 'open';
}

export const pairId = (a: string, b: string): string => [a, b].sort().join('_');
export const letterId = (fromId: string, toId: string): string => `${fromId}_${toId}`;
export const partnerOf = (c: ConnectionDoc, uid: string): string => (c.members[0] === uid ? c.members[1] : c.members[0]);
