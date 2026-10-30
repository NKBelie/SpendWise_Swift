import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineString } from 'firebase-functions/params';
import { DomainError } from './domain.js';
import { createCommandHandlers } from './command-handler.js';

initializeApp();
const walletModel = defineString('WALLET_MODEL', { default: 'UNCONFIRMED' });
const emulator = process.env.FUNCTIONS_EMULATOR === 'true';
const options = { region: 'europe-west1', enforceAppCheck: !emulator, maxInstances: 10, timeoutSeconds: 60 };
const handlers = createCommandHandlers({
  db: getFirestore(), getAuthUser: uid => getAuth().getUser(uid), walletModel: () => walletModel.value()
});
async function guarded(handler, request) {
  try { return await handler(request); }
  catch (error) {
    if (error instanceof DomainError) throw new HttpsError(error.code, error.message);
    console.error('SpendWise command failed', { code: error.code, name: error.name });
    throw new HttpsError('internal', 'The operation could not be completed. Retry with the same operation identifier.');
  }
}
export const spendWise = onCall(options, request => guarded(handlers.command, request));
export const adminDirectory = onCall(options, request => guarded(handlers.directory, request));
