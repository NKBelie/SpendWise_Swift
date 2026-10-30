import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { initializeApp, deleteApp } from 'firebase/app';
import { getAuth, connectAuthEmulator, createUserWithEmailAndPassword } from 'firebase/auth';
import { getFunctions, connectFunctionsEmulator, httpsCallable } from 'firebase/functions';
import { getFirestore, connectFirestoreEmulator, doc, getDoc } from 'firebase/firestore';
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const adminApp = require('firebase-admin/app');
const adminDB = require('firebase-admin/firestore');
const trusted = adminApp.initializeApp({ projectId: 'demo-spendwise' }, 'integration-admin');
const db = adminDB.getFirestore(trusted);
const clients = [];
async function client() {
  const app = initializeApp({ projectId: 'demo-spendwise', apiKey: 'fake-api-key', authDomain: 'demo-spendwise.firebaseapp.com' }, randomUUID());
  clients.push(app);
  const auth = getAuth(app); connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const functions = getFunctions(app, 'europe-west1'); connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  const firestore = getFirestore(app); connectFirestoreEmulator(firestore, '127.0.0.1', 8080);
  const user = (await createUserWithEmailAndPassword(auth, `${randomUUID()}@example.test`, 'Password-for-tests-123')).user;
  const call = (action, payload = {}, operationID = randomUUID()) => httpsCallable(functions, 'spendWise')({ action, payload, operationID, expectedUserID: user.uid }).then(r => r.data);
  await call('profile.initialize', { fullName: 'Test account', role: 'ADMIN' });
  return { uid: user.uid, call, firestore, functions };
}
after(async () => { await Promise.all(clients.map(deleteApp)); await adminApp.deleteApp(trusted); });
test('authenticated commands enforce roles, revisions, retries and consent', async () => {
  const owner = await client(), other = await client(), advisor = await client();
  assert.equal((await db.doc(`access/${owner.uid}`).get()).data().role, 'PERSONAL_USER');
  await assert.rejects(owner.call('admin.category', { id: 'food', name: 'Food' }));
  const record = { id: randomUUID(), userId: other.uid, title: 'Salary', amount: 100000, type: 'INCOME', category: 'Salary', date: Date.now() / 1000 };
  const operation = randomUUID(), payload = { kind: 'transactions', record, expectedRevision: 0 };
  const created = await owner.call('record.save', payload, operation);
  assert.deepEqual(await owner.call('record.save', payload, operation), created);
  await assert.rejects(owner.call('record.save', { ...payload, record: { ...record, amount: 1 } }, operation));
  const stored = (await db.doc(`users/${owner.uid}/transactions/${record.id}`).get()).data();
  assert.equal(stored.userId, owner.uid);
  await assert.rejects(getDoc(doc(other.firestore, `users/${owner.uid}/transactions/${record.id}`)));
  const edits = await Promise.allSettled([200000, 300000].map(value => owner.call('record.save', { ...payload, record: { ...record, amount: value }, expectedRevision: 1 })));
  assert.equal(edits.filter(r => r.status === 'fulfilled').length, 1);
  await db.doc(`access/${advisor.uid}`).update({ role: 'FINANCIAL_ADVISOR' });
  const grantID = randomUUID();
  await owner.call('advice.grant', { advisorID: advisor.uid, scopes: ['SPENDING_SUMMARY'], expiresAt: Date.now() / 1000 + 3600 }, grantID);
  const shared = await getDoc(doc(advisor.firestore, `sharedSummaries/${grantID}`));
  assert.ok(shared.data().summary.income > 0);
  assert.equal(shared.data().summary.title, undefined);
  await assert.rejects(getDoc(doc(advisor.firestore, `users/${owner.uid}/transactions/${record.id}`)));
  await owner.call('advice.revoke', { grantID });
  await assert.rejects(getDoc(doc(advisor.firestore, `sharedSummaries/${grantID}`)));
});

test('savings retries are idempotent and bill payments cannot duplicate an occurrence', async () => {
  const owner = await client();
  const goalID = randomUUID();
  await owner.call('record.save', { kind: 'goals', record: { id: goalID, title: 'Emergency', targetAmount: 1000, status: 'ACTIVE' }, expectedRevision: 0 });
  const contributionID = randomUUID();
  await owner.call('goal.contribute', { goalID, amount: 250 }, contributionID);
  await owner.call('goal.contribute', { goalID, amount: 250 }, contributionID);
  assert.equal((await db.doc(`users/${owner.uid}/goals/${goalID}`).get()).data().savedAmount, 250);
  await owner.call('goal.contribute', { goalID, amount: 750 });
  assert.equal((await db.doc(`users/${owner.uid}/goals/${goalID}`).get()).data().status, 'COMPLETED');
  await assert.rejects(owner.call('goal.contribute', { goalID, amount: 1 }));

  const billID = randomUUID(), due = Date.UTC(2026, 0, 30, 22) / 1000;
  const bill = { id: billID, title: 'Rent', category: 'Home', amount: 2000, frequency: 'MONTHLY', nextDueDate: due, status: 'ACTIVE' };
  await owner.call('record.save', { kind: 'bills', record: bill, expectedRevision: 0 });
  const paymentID = randomUUID();
  await owner.call('bill.pay', { billID, expectedDueDate: due }, paymentID);
  await owner.call('bill.pay', { billID, expectedDueDate: due }, paymentID);
  const paid = (await db.doc(`users/${owner.uid}/bills/${billID}`).get()).data();
  assert.equal(paid.nextDueDate, Date.UTC(2026, 1, 27, 22) / 1000);
  assert.equal((await db.doc(`users/${owner.uid}/transactions/${paymentID}`).get()).data().amount, 2000);
  await assert.rejects(owner.call('bill.pay', { billID, expectedDueDate: due }));
  await owner.call('record.save', { kind: 'bills', record: bill, expectedRevision: paid.revision });
  await assert.rejects(owner.call('bill.pay', { billID, expectedDueDate: due }));
});

test('wallet invitations are account-bound and managers control removal', async () => {
  const manager = await client(), invited = await client(), stranger = await client();
  const walletID = randomUUID(), invitationID = randomUUID();
  await manager.call('wallet.create', { id: walletID, name: 'Family' });
  await manager.call('wallet.invite', { walletID, inviteeID: invited.uid }, invitationID);
  await assert.rejects(stranger.call('wallet.respond', { invitationID, status: 'ACCEPTED' }));
  await invited.call('wallet.respond', { invitationID, status: 'ACCEPTED' });
  assert.equal((await db.doc(`wallets/${walletID}/members/${invited.uid}`).get()).data().role, 'FAMILY_MEMBER');
  await assert.rejects(invited.call('wallet.member', { walletID, userID: manager.uid, remove: true }));
  await manager.call('wallet.member', { walletID, userID: invited.uid, remove: true });
  await assert.rejects(getDoc(doc(invited.firestore, `wallets/${walletID}`)));
});
