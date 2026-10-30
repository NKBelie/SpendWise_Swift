import test from 'node:test';
import assert from 'node:assert/strict';
import { amount, add, totals, personalRecord, billOccurrence, MAX_MONEY, id } from '../domain.js';
test('money rejects decimals, unsafe values, zero and negatives', () => {
  for (const value of [0, -1, 1.5, NaN, Infinity, MAX_MONEY + 1, '100']) assert.throws(() => amount(value));
  assert.equal(amount(MAX_MONEY), MAX_MONEY);
  assert.throws(() => add(MAX_MONEY, 1));
});
test('totals ignore tombstones and preserve negative balances', () => {
  assert.deepEqual(totals([{ type: 'INCOME', amount: 100 }, { type: 'EXPENSE', amount: 150 }, { _deleted: true, amount: 900 }]), { income: 100, expenses: 150, balance: -50 });
  assert.deepEqual(totals([]), { income: 0, expenses: 0, balance: 0 });
});
test('profile ownership and goal balances cannot be supplied by caller', () => {
  const goal = personalRecord('goals', { id: 'goal', title: 'Home', targetAmount: 100, savedAmount: 999, userId: 'attacker' }, 'owner', null, 1000);
  assert.equal(goal.userId, 'owner'); assert.equal(goal.savedAmount, 0);
  assert.throws(() => personalRecord('goals', { id: 'goal', title: 'Home', targetAmount: 100, status: 'COMPLETED' }, 'owner', null, 1000));
});
test('identifiers cannot escape Firestore paths', () => {
  for (const value of ['a/b', '..', '', 'white space']) assert.throws(() => id(value));
});
test('monthly scheduling retains January 31 anchor and Kigali midnight', () => {
  const anchor = Date.UTC(2026, 0, 30, 22) / 1000;
  assert.equal(billOccurrence(anchor, 'MONTHLY', 1), Date.UTC(2026, 1, 27, 22) / 1000);
  assert.equal(billOccurrence(anchor, 'MONTHLY', 2), Date.UTC(2026, 2, 30, 22) / 1000);
});
test('yearly leap anchor returns to February 29', () => {
  const anchor = Date.UTC(2024, 1, 28, 22) / 1000;
  assert.equal(billOccurrence(anchor, 'YEARLY', 1), Date.UTC(2025, 1, 27, 22) / 1000);
  assert.equal(billOccurrence(anchor, 'YEARLY', 4), Date.UTC(2028, 1, 28, 22) / 1000);
});
