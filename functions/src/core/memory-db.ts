/** In-memory Db for tests. Enforces "reads before writes" inside run(). */
import type { Db, IntroPoolEntry, Tx } from './db.ts';
import type {
  ConnectionDoc, DiaryDoc, LetterDoc, PageDoc, ProfileDoc, ReportDoc, UserDoc,
} from './model.ts';

const clone = <T>(v: T): T => structuredClone(v);

export class MemoryDb implements Db {
  users = new Map<string, UserDoc>();
  profiles = new Map<string, ProfileDoc>();
  diaries = new Map<string, DiaryDoc>();
  letters = new Map<string, LetterDoc>();
  connections = new Map<string, ConnectionDoc>();
  pages = new Map<string, PageDoc>();
  blocks = new Map<string, Date>();
  reports: ReportDoc[] = [];
  intros = new Map<string, string[]>();
  history = new Map<string, Record<string, string>>();
  /** `${viewer}_${author}` → until */
  access = new Map<string, Date>();

  async run<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    const writes: Array<() => void> = [];
    let wrote = false;
    const read = <R>(f: () => R): Promise<R> => {
      if (wrote) throw new Error('Transaction read after write');
      return Promise.resolve(clone(f()));
    };
    const write = (f: () => void): void => {
      wrote = true;
      writes.push(f);
    };
    const tx: Tx = {
      user: (uid) => read(() => this.users.get(uid) ?? null),
      profile: (uid) => read(() => this.profiles.get(uid) ?? null),
      diary: (id) => read(() => this.diaries.get(id) ?? null),
      letter: (id) => read(() => this.letters.get(id) ?? null),
      connection: (id) => read(() => this.connections.get(id) ?? null),
      page: (cid, pid) => read(() => this.pages.get(`${cid}/${pid}`) ?? null),
      blocked: (a, b) => read(() => this.blocks.has(`${a}/${b}`)),
      pendingLettersFrom: (uid) => read(() => [...this.letters.values()].filter((l) => l.fromId === uid && l.status === 'pending')),
      pendingLettersTo: (uid) => read(() => [...this.letters.values()].filter((l) => l.toId === uid && l.status === 'pending')),
      activeConnectionsOf: (uid) =>
        read(() => [...this.connections.values()].filter((c) => c.members.includes(uid) && c.status === 'active')),
      access: (v, a) => read(() => this.access.get(`${v}_${a}`) ?? null),
      diariesOf: (a) => read(() => [...this.diaries.values()]
        .filter((d) => d.authorId === a)
        .sort((x, y) => y.createdAt.getTime() - x.createdAt.getTime())
        .slice(0, 30)),
      setUser: (d) => write(() => this.users.set(d.uid, clone(d))),
      setProfile: (d) => write(() => this.profiles.set(d.uid, clone(d))),
      setDiary: (d) => write(() => this.diaries.set(d.id, clone(d))),
      setLetter: (d) => write(() => this.letters.set(d.id, clone(d))),
      setConnection: (d) => write(() => this.connections.set(d.id, clone(d))),
      setPage: (d) => write(() => this.pages.set(`${d.connectionId}/${d.id}`, clone(d))),
      setBlock: (a, b, at) => write(() => this.blocks.set(`${a}/${b}`, at)),
      setAccess: (v, a, until) => write(() => this.access.set(`${v}_${a}`, until)),
      addReport: (d) => write(() => this.reports.push(clone(d))),
    };
    const result = await fn(tx);
    for (const w of writes) w(); // commit only on success
    return result;
  }

  async introPool(since: Date): Promise<IntroPoolEntry[]> {
    return [...this.users.values()]
      .filter((u) => !u.paused && u.lastIntroDiaryAt !== null && u.lastIntroDiaryAt >= since)
      .map((u) => {
        const related = new Set<string>();
        for (const l of this.letters.values()) {
          if (l.fromId === u.uid) related.add(l.toId);
          if (l.toId === u.uid) related.add(l.fromId);
        }
        let active = 0;
        for (const c of this.connections.values()) {
          if (!c.members.includes(u.uid)) continue;
          related.add(c.members[0] === u.uid ? c.members[1] : c.members[0]);
          if (c.status === 'active') active++;
        }
        for (const key of this.blocks.keys()) {
          const [a, b] = key.split('/') as [string, string];
          if (a === u.uid) related.add(b);
          if (b === u.uid) related.add(a);
        }
        return { user: clone(u), related, activeConnections: active, lastIntroduced: { ...(this.history.get(u.uid) ?? {}) } };
      });
  }

  async saveIntroductions(uid: string, dayKey: string, ids: string[], last: Record<string, string>, until: Date): Promise<void> {
    this.intros.set(`${uid}/${dayKey}`, [...ids]);
    for (const id of ids) this.access.set(`${uid}_${id}`, until);
    this.history.set(uid, { ...last });
  }

  async pendingLettersBefore(before: Date): Promise<LetterDoc[]> {
    return [...this.letters.values()].filter((l) => l.status === 'pending' && l.createdAt < before).map(clone);
  }

  async photoProposalsBefore(before: Date): Promise<ConnectionDoc[]> {
    return [...this.connections.values()]
      .filter((c) => c.status === 'active' && c.photo.state === 'proposed' && c.photo.proposedAt !== null && c.photo.proposedAt < before)
      .map(clone);
  }

  async deleteUserData(uid: string): Promise<void> {
    this.users.delete(uid);
    this.profiles.delete(uid);
    for (const [id, d] of this.diaries) if (d.authorId === uid) this.diaries.delete(id);
    for (const key of [...this.intros.keys()]) if (key.startsWith(`${uid}/`)) this.intros.delete(key);
    this.history.delete(uid);
    for (const key of [...this.blocks.keys()]) if (key.startsWith(`${uid}/`)) this.blocks.delete(key);
    for (const key of [...this.access.keys()]) if (key.startsWith(`${uid}_`) || key.endsWith(`_${uid}`)) this.access.delete(key);
  }
}
