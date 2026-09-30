/**
 * Security rules tests. Run with the emulator:
 *   npx firebase-tools emulators:exec --only firestore --project demo-tsuzuri "npm --prefix functions run test:rules"
 */
import { after, before, beforeEach, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import type { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, setDoc, Timestamp, where } from 'firebase/firestore';

let env: RulesTestEnvironment;
const future = () => Timestamp.fromMillis(Date.now() + 86400000);
const past = () => Timestamp.fromMillis(Date.now() - 1000);

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-tsuzuri',
    firestore: { rules: readFileSync(new URL('../../../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, 'users/a'), { uid: 'a', gender: 'woman' });
    for (const uid of ['a', 'b', 'c', 'd']) await setDoc(doc(db, `profiles/${uid}`), { uid, penName: uid });
    await setDoc(doc(db, 'diaries/b-intro'), { authorId: 'b', scope: 'intro', body: 'x' });
    await setDoc(doc(db, 'diaries/b-conn'), { authorId: 'b', scope: 'connections', body: 'x' });
    await setDoc(doc(db, 'diaries/b-private'), { authorId: 'b', scope: 'private', body: 'x' });
    await setDoc(doc(db, 'diaries/c-intro'), { authorId: 'c', scope: 'intro', body: 'x' });
    await setDoc(doc(db, 'access/a_b'), { viewerId: 'a', authorId: 'b', until: future() });
    await setDoc(doc(db, 'access/a_c'), { viewerId: 'a', authorId: 'c', until: past() });
    await setDoc(doc(db, 'access/a_d'), { viewerId: 'a', authorId: 'd', until: future() });
    await setDoc(doc(db, 'blocks/d/targets/a'), { blockerId: 'd', targetId: 'a' });
    await setDoc(doc(db, 'letters/a_b'), { fromId: 'a', toId: 'b', participants: ['a', 'b'] });
    await setDoc(doc(db, 'connections/a_b'), { members: ['a', 'b'], status: 'active' });
    await setDoc(doc(db, 'connections/a_b/pages/p1'), { authorId: 'b', body: 'x' });
    await setDoc(doc(db, 'reports/r1'), { reporterId: 'a', targetId: 'c' });
  });
});

const as = (uid: string | null) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

test('signed-out users read nothing', async () => {
  await assertFails(getDoc(doc(as(null), 'profiles/b')));
  await assertFails(getDoc(doc(as(null), 'diaries/b-intro')));
});

test('users/{uid} is private to its owner', async () => {
  await assertSucceeds(getDoc(doc(as('a'), 'users/a')));
  await assertFails(getDoc(doc(as('b'), 'users/a')));
});

test('clients cannot write anything directly', async () => {
  await assertFails(setDoc(doc(as('a'), 'users/a'), { paused: true }));
  await assertFails(setDoc(doc(as('a'), 'profiles/a'), { penName: 'x' }));
  await assertFails(setDoc(doc(as('a'), 'diaries/new'), { authorId: 'a', scope: 'intro', body: 'x' }));
  await assertFails(setDoc(doc(as('a'), 'letters/a_c'), { fromId: 'a', toId: 'c', participants: ['a', 'c'] }));
  await assertFails(setDoc(doc(as('a'), 'connections/a_c'), { members: ['a', 'c'], status: 'active' }));
  await assertFails(setDoc(doc(as('a'), 'access/a_x'), { until: future() }));
});

test('profiles: only with access or a connection, never across a block', async () => {
  await assertSucceeds(getDoc(doc(as('a'), 'profiles/a')));
  await assertSucceeds(getDoc(doc(as('a'), 'profiles/b')));
  await assertFails(getDoc(doc(as('a'), 'profiles/c'))); // access expired
  await assertFails(getDoc(doc(as('a'), 'profiles/d'))); // d blocked a
});

test('diaries follow their scope', async () => {
  await assertSucceeds(getDoc(doc(as('a'), 'diaries/b-intro')));
  await assertSucceeds(getDoc(doc(as('a'), 'diaries/b-conn')));
  await assertFails(getDoc(doc(as('a'), 'diaries/b-private')));
  await assertFails(getDoc(doc(as('a'), 'diaries/c-intro')));
  await assertSucceeds(getDoc(doc(as('b'), 'diaries/b-private')));
});

test('diary queries: owners may list their own; nobody may list others unfiltered', async () => {
  await assertSucceeds(getDocs(query(collection(as('b'), 'diaries'), where('authorId', '==', 'b'))));
  await assertFails(getDocs(query(collection(as('c'), 'diaries'), where('authorId', '==', 'b'))));
  await assertFails(getDocs(collection(as('a'), 'diaries')));
});

test('letters, connections and pages are for participants only', async () => {
  await assertSucceeds(getDoc(doc(as('b'), 'letters/a_b')));
  await assertFails(getDoc(doc(as('c'), 'letters/a_b')));
  await assertSucceeds(getDoc(doc(as('a'), 'connections/a_b')));
  await assertFails(getDoc(doc(as('c'), 'connections/a_b')));
  await assertSucceeds(getDoc(doc(as('a'), 'connections/a_b/pages/p1')));
  await assertFails(getDoc(doc(as('c'), 'connections/a_b/pages/p1')));
});

test('pages close when the connection ends', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), 'connections/a_b'), { members: ['a', 'b'], status: 'ended' });
  });
  await assertFails(getDoc(doc(as('a'), 'connections/a_b/pages/p1')));
  await assertFails(getDoc(doc(as('a'), 'diaries/b-conn')));
});

test('reports and access grants are never readable by clients', async () => {
  await assertFails(getDoc(doc(as('a'), 'reports/r1')));
  await assertFails(getDoc(doc(as('a'), 'access/a_b')));
});
