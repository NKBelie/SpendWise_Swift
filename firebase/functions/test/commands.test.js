import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createCommandHandlers } from '../command-handler.js';

// A transactional test double validates command logic and all-reads-before-writes.
// It is not a substitute for Firestore emulator conflict/retry or Rules tests.
class Query {
  constructor(path, filters = [], cap = Infinity) { this.path = path; this.filters = filters; this.cap = cap; }
  where(field, operator, value) { assert.equal(operator, '=='); return new Query(this.path, [...this.filters, [field, value]], this.cap); }
  limit(cap) { return new Query(this.path, this.filters, cap); }
}
class MemoryDB {
  data = new Map(); tail = Promise.resolve();
  doc(path) { return { path }; }
  collection(path) { return new Query(path); }
  async runTransaction(work) {
    const execution = this.tail.then(async () => {
      let writing = false; const writes = new Map();
      const result = await work({
        get: async ref => {
          assert.equal(writing, false, 'Firestore transactions must read before writing');
          if (ref instanceof Query) {
            const docs = [...this.data].filter(([path, value]) => path.startsWith(ref.path + '/') && !path.slice(ref.path.length + 1).includes('/') && ref.filters.every(([field, expected]) => value[field] === expected)).slice(0, ref.cap).map(([, value]) => ({ data: () => structuredClone(value) }));
            return { docs, size: docs.length };
          }
          const value = this.data.get(ref.path);
          return { exists: value !== undefined, data: () => structuredClone(value) };
        },
        set: (ref, value) => { writing = true; writes.set(ref.path, structuredClone(value)); },
        delete: ref => { writing = true; writes.set(ref.path, null); }
      });
      for (const [path, value] of writes) { if (value === null) this.data.delete(path); else this.data.set(path, value); }
      return result;
    });
    this.tail = execution.catch(() => {}); return execution;
  }
}
async function fixture() {
  const db = new MemoryDB();
  const handlers = createCommandHandlers({ db, getAuthUser: async uid => ({ uid, email: `${uid}@example.test` }), walletModel: () => 'UNCONFIRMED', nowSeconds: () => 1_800_000_000 });
  const call = (uid, action, payload = {}, operationID = randomUUID()) => handlers.command({ auth: { uid }, data: { expectedUserID: uid, action, payload, operationID } });
  for (const uid of ['alice', 'bob', 'advisor', 'admin']) await call(uid, 'profile.initialize', { fullName: uid, role: 'ADMIN' });
  db.data.set('access/advisor', { role: 'FINANCIAL_ADVISOR', status: 'ACTIVE' });
  db.data.set('access/admin', { role: 'ADMIN', status: 'ACTIVE' });
  return { db, handlers, call };
}
const entry = (id = randomUUID()) => ({ id, title: 'Salary', amount: 100_000, type: 'INCOME', category: 'Salary', date: 1_800_000_000, userId: 'bob' });

test('commands reject unauthenticated and changed identities; profiles cannot self-elevate', async () => {
  const { handlers, db } = await fixture();
  assert.equal(db.data.get('access/alice').role, 'PERSONAL_USER');
  await assert.rejects(handlers.command({ data: {} }), { code: 'unauthenticated' });
  await assert.rejects(handlers.command({ auth: { uid: 'alice' }, data: { expectedUserID: 'bob' } }), { code: 'failed-precondition' });
});

test('record writes bind ownership, reject changed replays, stale writes and resurrection', async () => {
  const { call, db } = await fixture();
  const record = entry(), operationID = randomUUID(), payload = { kind: 'transactions', record, expectedRevision: 0 };
  const created = await call('alice', 'record.save', payload, operationID);
  assert.deepEqual(await call('alice', 'record.save', payload, operationID), created);
  assert.equal(db.data.get(`users/alice/transactions/${record.id}`).userId, 'alice');
  await assert.rejects(call('alice', 'record.save', { ...payload, record: { ...record, amount: 1 } }, operationID), { code: 'already-exists' });
  const edits = await Promise.allSettled([200, 300].map(amount => call('alice', 'record.save', { ...payload, expectedRevision: 1, record: { ...record, amount } })));
  assert.equal(edits.filter(e => e.status === 'fulfilled').length, 1);
  await call('alice', 'record.delete', { kind: 'transactions', id: record.id, expectedRevision: 2 });
  await assert.rejects(call('alice', 'record.save', payload), { code: 'aborted' });
});

test('budget category/month uniqueness is enforced on the server', async () => {
  const { call } = await fixture();
  const record = { id: randomUUID(), category: 'Food', limitAmount: 100, month: 1, year: 2027 };
  await call('alice', 'record.save', { kind: 'budgets', record, expectedRevision: 0 });
  await assert.rejects(call('alice', 'record.save', { kind: 'budgets', record: { ...record, id: randomUUID() }, expectedRevision: 0 }), { code: 'already-exists' });
});

test('savings contributions update atomically and replay only once', async () => {
  const { call, db } = await fixture();
  const goalID = randomUUID();
  await call('alice', 'record.save', { kind: 'goals', record: { id: goalID, title: 'Home', targetAmount: 1000, savedAmount: 9999 }, expectedRevision: 0 });
  assert.equal(db.data.get(`users/alice/goals/${goalID}`).savedAmount, 0);
  const operationID = randomUUID();
  await call('alice', 'goal.contribute', { goalID, amount: 250 }, operationID);
  await call('alice', 'goal.contribute', { goalID, amount: 250 }, operationID);
  assert.equal(db.data.get(`users/alice/goals/${goalID}`).savedAmount, 250);
  await call('alice', 'goal.contribute', { goalID, amount: 750 });
  assert.equal(db.data.get(`users/alice/goals/${goalID}`).status, 'COMPLETED');
  await assert.rejects(call('alice', 'goal.contribute', { goalID, amount: 1 }), { code: 'failed-precondition' });
});

test('bill payments retain anchors, reject duplicates and preserve generated expenses', async () => {
  const { call, db } = await fixture();
  const billID = randomUUID(), due = Date.UTC(2026, 0, 30, 22) / 1000;
  const record = { id: billID, title: 'Rent', category: 'Home', amount: 200, frequency: 'MONTHLY', nextDueDate: due };
  await call('alice', 'record.save', { kind: 'bills', record, expectedRevision: 0 });
  const operationID = randomUUID();
  await call('alice', 'bill.pay', { billID, expectedDueDate: due }, operationID);
  await call('alice', 'bill.pay', { billID, expectedDueDate: due }, operationID);
  assert.equal(db.data.get(`users/alice/bills/${billID}`).nextDueDate, Date.UTC(2026, 1, 27, 22) / 1000);
  await assert.rejects(call('alice', 'record.delete', { kind: 'transactions', id: operationID, expectedRevision: 1 }), { code: 'failed-precondition' });
  await call('alice', 'record.save', { kind: 'bills', record, expectedRevision: 2 });
  await assert.rejects(call('alice', 'bill.pay', { billID, expectedDueDate: due }), { code: 'already-exists' });
});

test('wallet invitations bind identity and financial model remains gated', async () => {
  const { call, db } = await fixture();
  const walletID = randomUUID(), invitationID = randomUUID();
  await call('alice', 'wallet.create', { id: walletID, name: 'Family' });
  await call('alice', 'wallet.invite', { walletID, inviteeID: 'bob' }, invitationID);
  await assert.rejects(call('advisor', 'wallet.respond', { invitationID, status: 'ACCEPTED' }), { code: 'failed-precondition' });
  await call('bob', 'wallet.respond', { invitationID, status: 'ACCEPTED' });
  assert.equal(db.data.get(`wallets/${walletID}/members/bob`).role, 'FAMILY_MEMBER');
  await assert.rejects(call('bob', 'wallet.member', { walletID, userID: 'alice', remove: true }), { code: 'permission-denied' });
  await assert.rejects(call('bob', 'wallet.contribute', { walletID, amount: 100 }), { code: 'failed-precondition' });
  await call('alice', 'wallet.member', { walletID, userID: 'bob', remove: true });
  assert.equal(db.data.has(`wallets/${walletID}/members/bob`), false);
});

test('advisors receive only selected aggregates and recommendations require live consent', async () => {
  const { call, db } = await fixture();
  await call('alice', 'record.save', { kind: 'transactions', record: entry(), expectedRevision: 0 });
  const grantID = randomUUID();
  await call('alice', 'advice.grant', { advisorID: 'advisor', scopes: ['SPENDING_SUMMARY'], expiresAt: 1_800_003_600 }, grantID);
  const snapshot = db.data.get(`sharedSummaries/${grantID}`);
  assert.deepEqual(Object.keys(snapshot.summary).sort(), ['balance', 'expenses', 'income']);
  assert.equal(snapshot.summary.income, 100000);
  await call('advisor', 'advice.recommend', { grantID, title: 'Plan', message: 'Review your goals.' });
  await call('alice', 'advice.revoke', { grantID });
  await assert.rejects(call('advisor', 'advice.recommend', { grantID, title: 'Plan', message: 'Not authorized.' }), { code: 'permission-denied' });
});

test('administration requires canonical role, excludes private finance and audits changes', async () => {
  const { call, db, handlers } = await fixture();
  await assert.rejects(call('alice', 'admin.category', { id: 'custom', name: 'Custom' }), { code: 'permission-denied' });
  await assert.rejects(call('admin', 'admin.account', { userID: 'admin', role: 'PERSONAL_USER', status: 'ACTIVE' }), { code: 'failed-precondition' });
  const operationID = randomUUID();
  await call('admin', 'admin.account', { userID: 'bob', role: 'FINANCIAL_ADVISOR', status: 'SUSPENDED' }, operationID);
  assert.equal(db.data.get('access/bob').status, 'SUSPENDED');
  assert.equal(db.data.get(`audit/${operationID}`).actorId, 'admin');
  await assert.rejects(call('bob', 'profile.save', { fullName: 'Bob' }), { code: 'permission-denied' });
  const directory = await handlers.directory({ auth: { uid: 'admin' } });
  assert.deepEqual(Object.keys(directory.users[0]).sort(), ['email', 'fullName', 'id', 'role', 'status']);
});
