/**
 * Storage port. The Firestore adapter implements it with transactions; tests
 * use MemoryDb. Inside run(), every read must happen before the first write
 * (a Firestore transaction rule that MemoryDb enforces too).
 */
import type {
  ConnectionDoc, DiaryDoc, LetterDoc, PageDoc, ProfileDoc, ReportDoc, UserDoc,
} from './model.ts';

export interface Tx {
  user(uid: string): Promise<UserDoc | null>;
  profile(uid: string): Promise<ProfileDoc | null>;
  diary(id: string): Promise<DiaryDoc | null>;
  letter(id: string): Promise<LetterDoc | null>;
  connection(id: string): Promise<ConnectionDoc | null>;
  page(connectionId: string, pageId: string): Promise<PageDoc | null>;
  /** True when blocker has blocked target. */
  blocked(blockerId: string, targetId: string): Promise<boolean>;
  pendingLettersFrom(uid: string): Promise<LetterDoc[]>;
  pendingLettersTo(uid: string): Promise<LetterDoc[]>;
  activeConnectionsOf(uid: string): Promise<ConnectionDoc[]>;
  /** Expiry of viewer's read access to author (null when never granted). */
  access(viewerId: string, authorId: string): Promise<Date | null>;
  /** The author's latest diaries, newest first (at most 30). */
  diariesOf(authorId: string): Promise<DiaryDoc[]>;

  setUser(doc: UserDoc): void;
  setProfile(doc: ProfileDoc): void;
  setDiary(doc: DiaryDoc): void;
  setLetter(doc: LetterDoc): void;
  setConnection(doc: ConnectionDoc): void;
  setPage(doc: PageDoc): void;
  setBlock(blockerId: string, targetId: string, at: Date): void;
  /** Lets viewer read author's profile and intro diaries until `until` (enforced by firestore.rules). */
  setAccess(viewerId: string, authorId: string, until: Date): void;
  addReport(doc: ReportDoc): void;
}

export interface IntroPoolEntry {
  user: UserDoc;
  /** Everyone this user has a letter, connection or block with (either direction). */
  related: Set<string>;
  activeConnections: number;
  lastIntroduced: Record<string, string>;
}

export interface Db {
  run<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;

  /** Non-paused users whose last intro diary is at or after `since`. */
  introPool(since: Date): Promise<IntroPoolEntry[]>;
  /** Stores today's introductions and grants the user read access to each candidate until `accessUntil`. */
  saveIntroductions(
    uid: string, dayKey: string, candidateIds: string[], lastIntroduced: Record<string, string>, accessUntil: Date,
  ): Promise<void>;

  /** Pending letters created before `before`. */
  pendingLettersBefore(before: Date): Promise<LetterDoc[]>;
  /** Proposed photo reveals proposed before `before`. */
  photoProposalsBefore(before: Date): Promise<ConnectionDoc[]>;

  /** Removes the user's own documents (profile, diaries, intros, blocks they made). */
  deleteUserData(uid: string): Promise<void>;
}
