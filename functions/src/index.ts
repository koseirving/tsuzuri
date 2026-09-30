/**
 * Cloud Functions entry points. Thin wrappers: authentication comes from the
 * callable context, all rules live in core/services.ts.
 *
 * Nothing here is deployed by this repository. Creating the Firebase projects
 * (tsuzuri-dev / tsuzuri-prod) and deploying need a separately approved task.
 */
import { randomUUID } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { defineBoolean } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onObjectDeleted, onObjectFinalized } from 'firebase-functions/v2/storage';
import { logger } from 'firebase-functions';
import { FirestoreDb } from './firestore-db.ts';
import * as S from './core/services.ts';

initializeApp();

const REGION = 'asia-northeast1';
/** Keep true for anything beyond a closed internal test. */
const requireAgeVerification = defineBoolean('REQUIRE_AGE_VERIFICATION', { default: true });

let db: FirestoreDb | undefined;
function ctx(): S.Context {
  db ??= new FirestoreDb(getFirestore());
  return {
    db,
    now: () => new Date(),
    newId: () => randomUUID(),
    requireAgeVerification: requireAgeVerification.value(),
  };
}

type Handler<R> = (c: S.Context, uid: string | null, input: Record<string, unknown>) => Promise<R>;

/** Maps ServiceError to HttpsError; never leaks internal errors to clients. */
function callable<R>(handler: Handler<R>) {
  return onCall({ region: REGION, enforceAppCheck: true }, async (req: CallableRequest) => {
    const input = req.data && typeof req.data === 'object' ? (req.data as Record<string, unknown>) : {};
    try {
      return await handler(ctx(), req.auth?.uid ?? null, input);
    } catch (e) {
      if (e instanceof S.ServiceError) throw new HttpsError(e.code, e.message);
      logger.error('callable failed', { error: e instanceof Error ? e.name : 'unknown' });
      throw new HttpsError('internal', '保存できませんでした。もう一度お試しください。');
    }
  });
}

export const saveProfile = callable(S.saveProfile);
export const setPaused = callable(S.setPaused);
export const writeDiary = callable(S.writeDiary);
export const readDiaries = callable(S.readDiaries);
export const sendLetter = callable(S.sendLetter);
export const respondToLetter = callable(S.respondToLetter);
export const writePage = callable(S.writePage);
export const replyToPage = callable(S.replyToPage);
export const endConnection = callable(S.endConnection);
export const proposePhotos = callable(S.proposePhotos);
export const cancelPhotoProposal = callable(S.cancelPhotoProposal);
export const consentPhotos = callable(S.consentPhotos);
export const block = callable(S.block);
export const report = callable(S.report);

/** Short-lived signed URL for a revealed partner photo. */
export const revealedPhotoUrl = callable(async (c, uid, input) => {
  const { path } = await S.revealedPhotoPath(c, uid, input);
  const [url] = await getStorage().bucket().file(path).getSignedUrl({
    action: 'read',
    expires: Date.now() + 5 * 60 * 1000,
  });
  return { url };
});

export const deleteAccount = callable(async (c, uid) => {
  await S.deleteAccount(c, uid);
  if (uid) {
    await getStorage().bucket().deleteFiles({ prefix: `photos/${uid}/` });
    await getAuth().deleteUser(uid);
  }
  return { ok: true };
});

/** 05:00 JST every day. */
export const dailyIntroductions = onSchedule(
  { region: REGION, schedule: '0 5 * * *', timeZone: 'Asia/Tokyo', timeoutSeconds: 1800, memory: '512MiB' },
  async () => {
    const n = await S.computeIntroductions(ctx());
    logger.info('introductions computed', { users: n });
  },
);

export const expireStale = onSchedule(
  { region: REGION, schedule: 'every 60 minutes', timeZone: 'Asia/Tokyo' },
  async () => {
    const r = await S.expireStale(ctx());
    logger.info('stale items closed', r);
  },
);

const PHOTO = /^photos\/([^/]+)\/profile\.jpg$/;

export const photoUploaded = onObjectFinalized({ region: REGION }, async (event) => {
  const m = PHOTO.exec(event.data.name ?? '');
  if (!m) return;
  await S.markPhoto(ctx(), m[1]!, true);
});

export const photoDeleted = onObjectDeleted({ region: REGION }, async (event) => {
  const m = PHOTO.exec(event.data.name ?? '');
  if (!m) return;
  await S.markPhoto(ctx(), m[1]!, false);
});
