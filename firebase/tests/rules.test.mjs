import { before, beforeEach, after, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, query, where, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
let env;
before(async () => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080').split(':');
  env = await initializeTestEnvironment({ projectId: 'demo-spendwise', firestore: { host, port: Number(port), rules: await readFile('firebase/firestore.rules', 'utf8') } });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    const data = {
      'access/alice': { role: 'PERSONAL_USER', status: 'ACTIVE' },
      'access/bob': { role: 'PERSONAL_USER', status: 'ACTIVE' },
      'access/admin': { role: 'ADMIN', status: 'ACTIVE' },
      'access/advisor': { role: 'FINANCIAL_ADVISOR', status: 'ACTIVE' },
      'users/alice': { id: 'alice', fullName: 'Alice' },
      'users/alice/transactions/t1': { id: 't1', userId: 'alice', amount: 100, _deleted: false },
      'wallets/w1': { id: 'w1', memberIds: ['alice'], status: 'ACTIVE' },
      'wallets/w1/members/alice': { userId: 'alice', role: 'FAMILY_MANAGER' },
      'wallets/w1/contributions/c1': { amount: 100 },
      'adviceGrants/g1': { clientId: 'alice', advisorId: 'advisor', status: 'ACTIVE', expiresAt: Date.now() / 1000 + 86400 },
      'sharedSummaries/g1': { id: 'g1', clientId: 'alice', advisorId: 'advisor', summary: { balance: 100 } },
      'audit/a1': { actorId: 'admin' },
      'categories/food': { name: 'Food', active: true }
    };
    for (const [path, value] of Object.entries(data)) await setDoc(doc(db, path), value);
  });
});
const dbFor = uid => env.authenticatedContext(uid).firestore();
test('only owner reads private transactions; admin and advisor have no bypass', async () => {
  await assertSucceeds(getDoc(doc(dbFor('alice'), 'users/alice/transactions/t1')));
  for (const uid of ['bob', 'admin', 'advisor']) await assertFails(getDoc(doc(dbFor(uid), 'users/alice/transactions/t1')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'users/alice/transactions/t1')));
});
test('all direct financial writes and privilege escalation are denied', async () => {
  for (const uid of ['alice', 'admin']) {
    await assertFails(updateDoc(doc(dbFor(uid), 'access/alice'), { role: 'ADMIN' }));
    await assertFails(updateDoc(doc(dbFor(uid), 'users/alice'), { role: 'ADMIN' }));
    await assertFails(setDoc(doc(dbFor(uid), 'users/alice/transactions/new'), { amount: -100 }));
    await assertFails(deleteDoc(doc(dbFor(uid), 'users/alice/transactions/t1')));
    await assertFails(setDoc(doc(dbFor(uid), 'wallets/w1/members/bob'), { role: 'FAMILY_MANAGER' }));
  }
});
test('wallet reads require current membership', async () => {
  await assertSucceeds(getDoc(doc(dbFor('alice'), 'wallets/w1/contributions/c1')));
  await assertSucceeds(getDocs(query(collection(dbFor('alice'), 'wallets'), where('memberIds', 'array-contains', 'alice'))));
  await assertFails(getDoc(doc(dbFor('bob'), 'wallets/w1/contributions/c1')));
  await env.withSecurityRulesDisabled(async c => { await deleteDoc(doc(c.firestore(), 'wallets/w1/members/alice')); });
  await assertFails(getDoc(doc(dbFor('alice'), 'wallets/w1/contributions/c1')));
});
test('advisor can read only an approved summary and loses access on revocation', async () => {
  await assertSucceeds(getDoc(doc(dbFor('advisor'), 'sharedSummaries/g1')));
  await assertFails(getDoc(doc(dbFor('bob'), 'sharedSummaries/g1')));
  await env.withSecurityRulesDisabled(async c => { await updateDoc(doc(c.firestore(), 'adviceGrants/g1'), { status: 'REVOKED' }); });
  await assertFails(getDoc(doc(dbFor('advisor'), 'sharedSummaries/g1')));
  await assertSucceeds(getDoc(doc(dbFor('alice'), 'sharedSummaries/g1')));
});
test('expiry, advisor role removal and account suspension revoke access', async () => {
  await env.withSecurityRulesDisabled(async c => { await updateDoc(doc(c.firestore(), 'adviceGrants/g1'), { expiresAt: 1 }); });
  await assertFails(getDoc(doc(dbFor('advisor'), 'sharedSummaries/g1')));
  await env.withSecurityRulesDisabled(async c => {
    await updateDoc(doc(c.firestore(), 'adviceGrants/g1'), { expiresAt: Date.now() / 1000 + 86400 });
    await updateDoc(doc(c.firestore(), 'access/advisor'), { role: 'PERSONAL_USER' });
    await updateDoc(doc(c.firestore(), 'access/alice'), { status: 'SUSPENDED' });
  });
  await assertFails(getDoc(doc(dbFor('advisor'), 'sharedSummaries/g1')));
  await assertFails(getDoc(doc(dbFor('alice'), 'users/alice/transactions/t1')));
});
test('only admin reads audit; nobody writes categories directly', async () => {
  await assertSucceeds(getDoc(doc(dbFor('admin'), 'audit/a1')));
  await assertFails(getDoc(doc(dbFor('alice'), 'audit/a1')));
  await assertFails(setDoc(doc(dbFor('admin'), 'categories/new'), { name: 'New' }));
  await assertSucceeds(getDoc(doc(dbFor('alice'), 'categories/food')));
});
