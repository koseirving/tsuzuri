/**
 * Firestore implementation of the Db port (firebase-admin). Paths and field
 * names must match firestore.rules and firestore.indexes.json.
 *
 * Not exercised in this repository's unit tests (they use MemoryDb); the
 * emulator-based rules tests and a staging project are where this is verified.
 */
import { Timestamp } from 'firebase-admin/firestore';
import type { DocumentData, DocumentReference, Firestore, Query, Transaction } from 'firebase-admin/firestore';
import type { Db, IntroPoolEntry, Tx } from './core/db.ts';
import type {
  ConnectionDoc, DiaryDoc, LetterDoc, PageDoc, ProfileDoc, ReportDoc, UserDoc,
} from './core/model.ts';

/** Firestore Timestamps → Date, recursively. */
function revive<T>(value: unknown): T {
  if (value instanceof Timestamp) return value.toDate() as T;
  if (Array.isArray(value)) return value.map((v) => revive(v)) as T;
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) out[k] = revive(v);
    return out as T;
  }
  return value as T;
}

export class FirestoreDb implements Db {
  private readonly fs: Firestore;
  constructor(fs: Firestore) {
    this.fs = fs;
  }

  private users() { return this.fs.collection('users'); }
  private profiles() { return this.fs.collection('profiles'); }
  private diaries() { return this.fs.collection('diaries'); }
  private letters() { return this.fs.collection('letters'); }
  private connections() { return this.fs.collection('connections'); }
  private pages(connectionId: string) { return this.connections().doc(connectionId).collection('pages'); }
  private blockDoc(blocker: string, target: string) { return this.fs.doc(`blocks/${blocker}/targets/${target}`); }
  private accessDoc(viewer: string, author: string) { return this.fs.doc(`access/${viewer}_${author}`); }

  async run<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    return this.fs.runTransaction(async (t: Transaction) => {
      const one = async <D>(ref: DocumentReference): Promise<D | null> => {
        const snap = await t.get(ref);
        return snap.exists ? revive<D>(snap.data()) : null;
      };
      const many = async <D>(q: Query): Promise<D[]> => (await t.get(q)).docs.map((d) => revive<D>(d.data()));
      const tx: Tx = {
        user: (uid) => one<UserDoc>(this.users().doc(uid)),
        profile: (uid) => one<ProfileDoc>(this.profiles().doc(uid)),
        diary: (id) => one<DiaryDoc>(this.diaries().doc(id)),
        letter: (id) => one<LetterDoc>(this.letters().doc(id)),
        connection: (id) => one<ConnectionDoc>(this.connections().doc(id)),
        page: (cid, pid) => one<PageDoc>(this.pages(cid).doc(pid)),
        blocked: async (a, b) => (await t.get(this.blockDoc(a, b))).exists,
        pendingLettersFrom: (uid) =>
          many<LetterDoc>(this.letters().where('fromId', '==', uid).where('status', '==', 'pending')),
        pendingLettersTo: (uid) =>
          many<LetterDoc>(this.letters().where('toId', '==', uid).where('status', '==', 'pending')),
        activeConnectionsOf: (uid) =>
          many<ConnectionDoc>(this.connections().where('members', 'array-contains', uid).where('status', '==', 'active')),

        access: async (v, a) => (await one<{ until: Date }>(this.accessDoc(v, a)))?.until ?? null,
        diariesOf: (a) => many<DiaryDoc>(this.diaries().where('authorId', '==', a).orderBy('createdAt', 'desc').limit(30)),

        setUser: (d) => void t.set(this.users().doc(d.uid), d as unknown as DocumentData),
        setProfile: (d) => void t.set(this.profiles().doc(d.uid), d as unknown as DocumentData),
        setDiary: (d) => void t.set(this.diaries().doc(d.id), d as unknown as DocumentData),
        setLetter: (d) => void t.set(this.letters().doc(d.id), d as unknown as DocumentData),
        setConnection: (d) => void t.set(this.connections().doc(d.id), d as unknown as DocumentData),
        setPage: (d) => void t.set(this.pages(d.connectionId).doc(d.id), d as unknown as DocumentData),
        setBlock: (a, b, at) => void t.set(this.blockDoc(a, b), { blockerId: a, targetId: b, createdAt: at }),
        setAccess: (v, a, until) => void t.set(this.accessDoc(v, a), { viewerId: v, authorId: a, until }),
        addReport: (d: ReportDoc) => void t.set(this.fs.collection('reports').doc(d.id), d as unknown as DocumentData),
      };
      return fn(tx);
    });
  }

  async introPool(since: Date): Promise<IntroPoolEntry[]> {
    const snap = await this.users().where('paused', '==', false).where('lastIntroDiaryAt', '>=', since).get();
    const entries: IntroPoolEntry[] = [];
    for (const doc of snap.docs) {
      const user = revive<UserDoc>(doc.data());
      const uid = user.uid;
      const [letters, conns, blocksMade, blocksAgainst, history] = await Promise.all([
        this.letters().where('participants', 'array-contains', uid).select('participants').get(),
        this.connections().where('members', 'array-contains', uid).select('members', 'status').get(),
        this.fs.collection(`blocks/${uid}/targets`).select('targetId').get(),
        this.fs.collectionGroup('targets').where('targetId', '==', uid).select('blockerId').get(),
        this.fs.doc(`introHistory/${uid}`).get(),
      ]);
      const related = new Set<string>();
      for (const l of letters.docs) for (const p of l.get('participants') as string[]) if (p !== uid) related.add(p);
      let active = 0;
      for (const c of conns.docs) {
        for (const m of c.get('members') as string[]) if (m !== uid) related.add(m);
        if (c.get('status') === 'active') active++;
      }
      for (const b of blocksMade.docs) related.add(b.get('targetId') as string);
      for (const b of blocksAgainst.docs) related.add(b.get('blockerId') as string);
      entries.push({
        user,
        related,
        activeConnections: active,
        lastIntroduced: (history.get('last') as Record<string, string> | undefined) ?? {},
      });
    }
    return entries;
  }

  async saveIntroductions(
    uid: string, dayKey: string, ids: string[], last: Record<string, string>, accessUntil: Date,
  ): Promise<void> {
    const batch = this.fs.batch();
    batch.set(this.fs.doc(`intros/${uid}/days/${dayKey}`), { candidateIds: ids, createdAt: new Date() });
    batch.set(this.fs.doc(`introHistory/${uid}`), { last });
    for (const id of ids) batch.set(this.accessDoc(uid, id), { viewerId: uid, authorId: id, until: accessUntil });
    await batch.commit();
  }

  async pendingLettersBefore(before: Date): Promise<LetterDoc[]> {
    const snap = await this.letters().where('status', '==', 'pending').where('createdAt', '<', before).limit(500).get();
    return snap.docs.map((d) => revive<LetterDoc>(d.data()));
  }

  async photoProposalsBefore(before: Date): Promise<ConnectionDoc[]> {
    const snap = await this.connections()
      .where('photo.state', '==', 'proposed')
      .where('photo.proposedAt', '<', before)
      .limit(500)
      .get();
    return snap.docs.map((d) => revive<ConnectionDoc>(d.data())).filter((c) => c.status === 'active');
  }

  async deleteUserData(uid: string): Promise<void> {
    const [diaries, access, accessOthers] = await Promise.all([
      this.diaries().where('authorId', '==', uid).select().get(),
      this.fs.collection('access').where('viewerId', '==', uid).select('viewerId').get(),
      this.fs.collection('access').where('authorId', '==', uid).select('authorId').get(),
    ]);
    const refs: DocumentReference[] = [
      this.users().doc(uid), this.profiles().doc(uid), this.fs.doc(`introHistory/${uid}`),
      ...[...diaries.docs, ...access.docs, ...accessOthers.docs].map((d) => d.ref),
    ];
    // Without onWriteError, a failed BulkWriter op rejects its own promise; observe every
    // one immediately so a failure surfaces here instead of as an unhandled rejection.
    const writer = this.fs.bulkWriter();
    const results = Promise.allSettled(refs.map((r) => writer.delete(r)));
    await writer.close();
    const failed = (await results).find((r): r is PromiseRejectedResult => r.status === 'rejected');
    if (failed) throw failed.reason;
    await this.fs.recursiveDelete(this.fs.collection(`intros/${uid}/days`));
    await this.fs.recursiveDelete(this.fs.collection(`blocks/${uid}/targets`));
  }
}
