import { createHash } from 'node:crypto';
import { DomainError, requireValue, id, text, amount, add, date, oneOf, personalRecord, totals, billOccurrence, categories } from './domain.js';

export function createCommandHandlers({ db, getAuthUser, walletModel, nowSeconds = () => Math.floor(Date.now() / 1000) }) {
  const doc = path => db.doc(path);
  const privateDoc = (uid, kind, key) => doc(`users/${uid}/${kind}/${key}`);
  function canonical(value) {
    if (Array.isArray(value)) return value.map(canonical);
    if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
    return value;
  }
  function fail(condition, message, code = 'permission-denied') { requireValue(condition, message, code); }
  async function read(tx, ref) { const snap = await tx.get(ref); return snap.exists ? snap.data() : null; }
  async function active(tx, uid, role) {
    const access = await read(tx, doc(`access/${uid}`));
    fail(access?.status === 'ACTIVE' && (!role || access.role === role), 'This operation is not permitted.');
    return access;
  }
  async function member(tx, walletID, uid, manager = false) {
    const wallet = await read(tx, doc(`wallets/${walletID}`));
    const membership = await read(tx, doc(`wallets/${walletID}/members/${uid}`));
    fail(wallet?.status === 'ACTIVE' && membership && (!manager || membership.role === 'FAMILY_MANAGER'), 'Wallet permission denied.');
    return { wallet, membership };
  }
  async function rows(tx, query) {
    const snap = await tx.get(query.limit(5001));
    fail(snap.size <= 5000, 'This account requires a paginated aggregation job.', 'resource-exhausted');
    return snap.docs.map(d => d.data()).filter(d => !d._deleted);
  }
  function revision(existing, expected) {
    fail(Number.isSafeInteger(expected) && expected >= 0, 'Expected revision is required.', 'invalid-argument');
    fail((existing?.revision ?? 0) === expected && !existing?._deleted, 'This record changed. Reload and try again.', 'aborted');
    return expected + 1;
  }

  // Every command is authenticated, validated, and replay-protected in one Firestore
  // transaction. Admin SDK bypasses Rules, so authorization is repeated here.
  async function command(request) {
    try {
      fail(request.auth, 'Sign in to continue.', 'unauthenticated');
      const uid = id(request.auth.uid), input = request.data ?? {};
      fail(input.expectedUserID === uid, 'The signed-in account changed. Reopen this screen.', 'failed-precondition');
      const action = text(input.action, 'action', 80), operationID = id(input.operationID), p = input.payload ?? {};
      fail(p && typeof p === 'object' && !Array.isArray(p), 'Invalid payload.', 'invalid-argument');
      const serialized = JSON.stringify(canonical({ action, payload: p }));
      fail(serialized.length <= 24000, 'Request is too large.', 'invalid-argument');
      const hash = createHash('sha256').update(serialized).digest('hex');
      const authUser = action === 'profile.initialize' ? await getAuthUser(uid) : null;
      return await db.runTransaction(async tx => {
        const now = nowSeconds(), opRef = privateDoc(uid, 'operations', operationID);
        const access = await read(tx, doc(`access/${uid}`));
        if (action !== 'profile.initialize') fail(access?.status === 'ACTIVE', 'Account is not active.');
        else fail(!access || access.status === 'ACTIVE', 'Account is not active.');
        const previous = await read(tx, opRef);
        if (previous) {
          fail(previous.hash === hash, 'Operation identifier was reused with different data.', 'already-exists');
          return previous.result;
        }
        const writes = [], put = (ref, data) => writes.push([ref, data]);
        let result = { id: operationID };
        if (action === 'profile.initialize') {
          const ref = doc(`users/${uid}`), existing = await read(tx, ref);
          const defaultsRef = doc('system/categoryDefaults'), defaults = await read(tx, defaultsRef);
          if (!defaults) {
            const configured = await rows(tx, db.collection('categories'));
            if (configured.length === 0) {
              for (const name of categories) put(doc(`categories/${name.toLowerCase()}`), { id: name.toLowerCase(), name, active: true });
            }
            put(defaultsRef, { initializedAt: now });
          }
          if (!existing) {
            fail(!access, 'Account state needs administrator repair.', 'failed-precondition');
            put(doc(`access/${uid}`), { id: uid, role: 'PERSONAL_USER', status: 'ACTIVE' });
            put(ref, { id: uid, fullName: text(p.fullName ?? authUser.displayName ?? 'SpendWise member', 'name'), email: authUser.email ?? '', role: 'PERSONAL_USER', status: 'ACTIVE', currency: 'RWF', createdAt: now });
          }
          result = { id: uid };
        } else if (action === 'profile.save') {
          const ref = doc(`users/${uid}`), existing = await read(tx, ref);
          fail(existing, 'Profile not found.', 'not-found');
          put(ref, { ...existing, fullName: text(p.fullName, 'name'), phoneNumber: typeof p.phoneNumber === 'string' ? p.phoneNumber.slice(0, 40) : null });
        } else if (['record.save', 'record.delete'].includes(action)) {
          const kind = oneOf(p.kind, ['transactions', 'budgets', 'goals', 'bills'], 'collection');
          const key = id(p.record?.id ?? p.id), ref = privateDoc(uid, kind, key), existing = await read(tx, ref);
          const next = revision(existing, p.expectedRevision);
          if (action === 'record.delete') {
            fail(existing, 'Record not found.', 'not-found');
            fail(kind !== 'transactions' || !existing.sourceBillID, 'Bill payments cannot be removed from transaction history.', 'failed-precondition');
            put(ref, { ...existing, _deleted: true, revision: next });
          } else {
            fail(!existing?.sourceBillID, 'Bill-generated transactions are immutable.', 'failed-precondition');
            const record = personalRecord(kind, p.record, uid, existing, now);
            if (kind === 'budgets') {
              const budgets = await rows(tx, db.collection(`users/${uid}/budgets`));
              fail(!budgets.some(b => b.id !== key && b.month === record.month && b.year === record.year && b.category === record.category), 'A budget already exists for this category and month.', 'already-exists');
            }
            put(ref, { ...record, revision: next });
          }
          result = { id: key, revision: next };
        } else if (action === 'goal.contribute') {
          const key = id(p.goalID), ref = privateDoc(uid, 'goals', key), goal = await read(tx, ref);
          fail(goal && !goal._deleted && goal.status === 'ACTIVE', 'Goal is not active.', 'failed-precondition');
          const saved = add(goal.savedAmount, amount(p.amount));
          put(ref, { ...goal, savedAmount: saved, status: saved >= goal.targetAmount ? 'COMPLETED' : 'ACTIVE', revision: goal.revision + 1 });
          put(privateDoc(uid, 'savingsContributions', operationID), { id: operationID, userId: uid, goalId: key, amount: p.amount, contributedAt: now });
        } else if (action === 'bill.pay') {
          const key = id(p.billID), ref = privateDoc(uid, 'bills', key), bill = await read(tx, ref);
          fail(bill && !bill._deleted && bill.status === 'ACTIVE', 'Bill is not active.', 'failed-precondition');
          fail(date(p.expectedDueDate) === bill.nextDueDate, 'This occurrence has already changed.', 'aborted');
          const occurrenceRef = privateDoc(uid, 'paidBillOccurrences', createHash('sha256').update(`${key}:${bill.nextDueDate}`).digest('hex'));
          const paidOccurrence = await read(tx, occurrenceRef);
          const existingTransaction = await read(tx, privateDoc(uid, 'transactions', operationID));
          fail(!paidOccurrence, 'This bill occurrence was already paid.', 'already-exists');
          fail(!existingTransaction, 'Payment transaction identifier is already used.', 'already-exists');
          const count = bill.paidOccurrences + 1, next = billOccurrence(bill.anchorDate, bill.frequency, count);
          put(occurrenceRef, { billId: key, dueDate: bill.nextDueDate, operationID });
          put(ref, { ...bill, nextDueDate: next, paidOccurrences: count, revision: bill.revision + 1 });
          put(privateDoc(uid, 'billPayments', operationID), { id: operationID, userId: uid, billId: key, amount: bill.amount, dueDate: bill.nextDueDate, paidAt: now });
          put(privateDoc(uid, 'transactions', operationID), { id: operationID, userId: uid, title: bill.title, amount: bill.amount, type: 'EXPENSE', category: bill.category, date: now, createdAt: now, sourceBillID: key, revision: 1, _deleted: false });
        } else if (action === 'wallet.create') {
          const key = id(p.id), ref = doc(`wallets/${key}`), exists = await read(tx, ref);
          fail(!exists, 'Wallet identifier is already used.', 'already-exists');
          put(ref, { id: key, name: text(p.name, 'wallet name'), description: '', currency: 'RWF', createdBy: uid, status: 'ACTIVE', createdAt: now, memberIds: [uid], balance: 0 });
          put(doc(`wallets/${key}/members/${uid}`), { id: uid, walletId: key, userId: uid, role: 'FAMILY_MANAGER', joinedAt: now });
          result = { id: key };
        } else if (action === 'wallet.invite') {
          const walletID = id(p.walletID), inviteeID = id(p.inviteeID);
          await member(tx, walletID, uid, true); await active(tx, inviteeID);
          fail(uid !== inviteeID, 'You are already a member.', 'invalid-argument');
          const membership = await read(tx, doc(`wallets/${walletID}/members/${inviteeID}`));
          fail(!membership, 'This user is already a member.', 'already-exists');
          const pending = await rows(tx, db.collection('walletInvitations').where('walletId', '==', walletID));
          fail(!pending.some(i => i.inviteeId === inviteeID && i.status === 'PENDING' && i.expiresAt > now), 'An invitation is already pending.', 'already-exists');
          put(doc(`walletInvitations/${operationID}`), { id: operationID, walletId: walletID, invitedBy: uid, inviteeId: inviteeID, status: 'PENDING', createdAt: now, expiresAt: now + 7 * 86400 });
        } else if (action === 'wallet.respond') {
          const ref = doc(`walletInvitations/${id(p.invitationID)}`), invitation = await read(tx, ref);
          fail(invitation?.inviteeId === uid && invitation.status === 'PENDING' && invitation.expiresAt > now, 'Invitation is unavailable.', 'failed-precondition');
          const walletRef = doc(`wallets/${invitation.walletId}`), wallet = await read(tx, walletRef);
          await member(tx, invitation.walletId, invitation.invitedBy, true);
          const status = oneOf(p.status, ['ACCEPTED', 'DECLINED'], 'response');
          fail(wallet?.status === 'ACTIVE' && wallet.memberIds.length < 50, 'Wallet is unavailable or full.', 'failed-precondition');
          if (status === 'ACCEPTED') {
            put(walletRef, { ...wallet, memberIds: [...new Set([...wallet.memberIds, uid])] });
            put(doc(`wallets/${wallet.id}/members/${uid}`), { id: uid, walletId: wallet.id, userId: uid, role: 'FAMILY_MEMBER', joinedAt: now });
          }
          put(ref, { ...invitation, status });
        } else if (action === 'wallet.member') {
          const walletID = id(p.walletID), target = id(p.userID);
          const { wallet } = await member(tx, walletID, uid, true);
          fail(target !== uid && target !== wallet.createdBy, 'The owner and your own membership cannot be changed here.', 'failed-precondition');
          const ref = doc(`wallets/${walletID}/members/${target}`), membership = await read(tx, ref);
          fail(membership, 'Member not found.', 'not-found');
          if (p.remove === true) {
            writes.push([ref, null]); put(doc(`wallets/${walletID}`), { ...wallet, memberIds: wallet.memberIds.filter(v => v !== target) });
          } else put(ref, { ...membership, role: oneOf(p.role, ['FAMILY_MANAGER', 'FAMILY_MEMBER'], 'wallet role') });
        } else if (['wallet.contribute', 'wallet.expense', 'wallet.budget'].includes(action)) {
          fail(walletModel() === 'CONTRIBUTION_POOL', 'The shared-wallet financial model must be confirmed before ledger writes are enabled.', 'failed-precondition');
          const walletID = id(p.walletID), { wallet } = await member(tx, walletID, uid, action !== 'wallet.contribute');
          if (action === 'wallet.budget') {
            const record = personalRecord('budgets', p.record, uid, null, now);
            const key = `${record.year}-${record.month}-${createHash('sha256').update(record.category).digest('hex').slice(0, 16)}`;
            put(doc(`wallets/${walletID}/budgets/${key}`), { ...record, id: key, walletId: walletID });
          } else {
            const money = amount(p.amount), contribution = action === 'wallet.contribute';
            put(doc(`wallets/${walletID}`), { ...wallet, balance: add(wallet.balance, contribution ? money : -money) });
            put(doc(`wallets/${walletID}/${contribution ? 'contributions' : 'expenses'}/${operationID}`), contribution
              ? { id: operationID, walletId: walletID, memberId: uid, amount: money, recordedBy: uid, contributedAt: now }
              : { id: operationID, walletId: walletID, createdBy: uid, title: text(p.title, 'title'), category: text(p.category, 'category', 80), amount: money, expenseDate: now, createdAt: now });
          }
        } else if (action === 'advice.request') {
          const advisorID = id(p.advisorID); await active(tx, advisorID, 'FINANCIAL_ADVISOR');
          fail(advisorID !== uid, 'Choose another advisor.', 'invalid-argument');
          put(doc(`adviceRequests/${operationID}`), { id: operationID, clientId: uid, advisorId: advisorID, message: text(p.message, 'request', 2000), createdAt: now, status: 'PENDING' });
        } else if (action === 'advice.grant') {
          const advisorID = id(p.advisorID); await active(tx, advisorID, 'FINANCIAL_ADVISOR');
          fail(advisorID !== uid, 'Choose another advisor.', 'invalid-argument');
          fail(Array.isArray(p.scopes) && p.scopes.length > 0 && p.scopes.length <= 3, 'Choose summary scopes.', 'invalid-argument');
          const scopes = [...new Set(p.scopes.map(s => oneOf(s, ['BUDGET_SUMMARY', 'SPENDING_SUMMARY', 'SAVINGS_SUMMARY'], 'scope')))];
          const expiresAt = date(p.expiresAt); fail(expiresAt > now && expiresAt <= now + 90 * 86400, 'Consent must expire within 90 days.', 'invalid-argument');
          const summary = {};
          if (scopes.includes('SPENDING_SUMMARY')) Object.assign(summary, totals(await rows(tx, db.collection(`users/${uid}/transactions`))));
          if (scopes.includes('BUDGET_SUMMARY')) {
            const budgets = await rows(tx, db.collection(`users/${uid}/budgets`));
            summary.budgetCount = budgets.length; summary.budgetLimits = budgets.reduce((a, b) => add(a, b.limitAmount), 0);
          }
          if (scopes.includes('SAVINGS_SUMMARY')) {
            const goals = await rows(tx, db.collection(`users/${uid}/goals`));
            summary.savingsTotal = goals.reduce((a, g) => add(a, g.savedAmount), 0); summary.savingsTargets = goals.reduce((a, g) => add(a, g.targetAmount), 0);
          }
          const grant = { id: operationID, clientId: uid, advisorId: advisorID, scopes, status: 'ACTIVE', createdAt: now, expiresAt };
          put(doc(`adviceGrants/${operationID}`), grant);
          put(doc(`sharedSummaries/${operationID}`), { ...grant, summary });
        } else if (action === 'advice.revoke') {
          const ref = doc(`adviceGrants/${id(p.grantID)}`), grant = await read(tx, ref);
          fail(grant?.clientId === uid, 'Consent permission denied.'); put(ref, { ...grant, status: 'REVOKED' });
        } else if (action === 'advice.recommend') {
          fail(access.role === 'FINANCIAL_ADVISOR', 'Advisor role is required.');
          const grantID = id(p.grantID), grant = await read(tx, doc(`adviceGrants/${grantID}`));
          fail(grant?.advisorId === uid && grant.status === 'ACTIVE' && grant.expiresAt > now, 'Consent is unavailable.');
          await active(tx, grant.clientId);
          put(doc(`recommendations/${operationID}`), { id: operationID, grantId: grantID, clientId: grant.clientId, advisorId: uid, title: text(p.title, 'title'), message: text(p.message, 'recommendation', 4000), status: 'PENDING', createdAt: now });
        } else if (action === 'advice.review') {
          const ref = doc(`recommendations/${id(p.id)}`), recommendation = await read(tx, ref);
          fail(recommendation?.clientId === uid, 'Recommendation permission denied.');
          put(ref, { ...recommendation, status: oneOf(p.status, ['REVIEWED', 'ARCHIVED'], 'status') });
        } else if (action.startsWith('admin.')) {
          fail(access.role === 'ADMIN', 'Administrator role is required.');
          if (action === 'admin.account') {
            const target = id(p.userID); fail(target !== uid, 'Administrators cannot change their own access.', 'failed-precondition');
            const accessRef = doc(`access/${target}`), targetAccess = await read(tx, accessRef);
            const userRef = doc(`users/${target}`), profile = await read(tx, userRef);
            fail(targetAccess && profile, 'Account not found.', 'not-found');
            const role = oneOf(p.role, ['ADMIN', 'PERSONAL_USER', 'FINANCIAL_ADVISOR'], 'role');
            const status = oneOf(p.status, ['ACTIVE', 'SUSPENDED', 'DEACTIVATED'], 'status');
            put(accessRef, { ...targetAccess, role, status }); put(userRef, { ...profile, role, status });
            put(doc(`audit/${operationID}`), { id: operationID, actorId: uid, targetId: target, action, role, status, createdAt: now });
          } else if (action === 'admin.category') {
            const key = id(p.id), name = text(p.name, 'category', 80);
            const configured = await rows(tx, db.collection('categories'));
            fail(!configured.some(c => c.id !== key && c.name.toLowerCase() === name.toLowerCase()), 'This category name is already used.', 'already-exists');
            put(doc(`categories/${key}`), { id: key, name, active: p.active !== false });
            put(doc(`audit/${operationID}`), { id: operationID, actorId: uid, targetId: key, action, createdAt: now });
          } else throw new DomainError('Unknown administrator action.');
        } else throw new DomainError('Unknown action.');
        for (const [ref, value] of writes) { if (value === null) tx.delete(ref); else tx.set(ref, value); }
        tx.set(opRef, { hash, result, createdAt: now });
        return result;
      });
    } catch (error) {
      throw error;
    }
  }

  async function directory(request) {
    try {
      fail(request.auth, 'Sign in to continue.', 'unauthenticated');
      return await db.runTransaction(async tx => {
        await active(tx, request.auth.uid, 'ADMIN');
        // Return only account administration fields, never private subcollections.
        const users = await rows(tx, db.collection('users'));
        return { users: users.map(u => ({ id: u.id, fullName: u.fullName, email: u.email, role: u.role, status: u.status })) };
      });
    } catch (error) {
      throw error;
    }
  }
  return { command, directory };
}
