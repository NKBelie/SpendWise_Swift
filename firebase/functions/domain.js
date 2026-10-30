export class DomainError extends Error {
  constructor(message, code = 'invalid-argument') { super(message); this.code = code; }
}
export const MAX_MONEY = 9_000_000_000_000;
export function requireValue(condition, message, code) {
  if (!condition) throw new DomainError(message, code);
}
export function text(value, field, max = 160) {
  requireValue(typeof value === 'string' && value.trim().length > 0 && value.length <= max, `Invalid ${field}.`);
  return value.trim();
}
export function id(value) {
  const result = text(value, 'identifier', 128);
  requireValue(/^[A-Za-z0-9_-]+$/.test(result), 'Invalid identifier.');
  return result;
}
export function amount(value, zero = false) {
  requireValue(Number.isSafeInteger(value) && value >= (zero ? 0 : 1) && value <= MAX_MONEY, 'Enter a valid integer RWF amount.');
  return value;
}
export function add(a, b) {
  const total = a + b;
  requireValue(Number.isSafeInteger(total) && Math.abs(total) <= MAX_MONEY, 'Financial total exceeds supported range.', 'out-of-range');
  return total;
}
export function date(value) {
  requireValue(typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 253402207200, 'Invalid date.');
  return value;
}
export function oneOf(value, choices, field) {
  requireValue(choices.includes(value), `Invalid ${field}.`); return value;
}
export const categories = ['Salary', 'Business', 'Food', 'Transport', 'Home', 'Health', 'Education', 'Entertainment', 'Other'];
export function personalRecord(kind, p, uid, existing, now) {
  const common = { id: id(p.id), userId: uid, createdAt: existing?.createdAt ?? now, _deleted: false };
  if (kind === 'transactions') return { ...common, title: text(p.title, 'title'), amount: amount(p.amount), type: oneOf(p.type, ['INCOME', 'EXPENSE'], 'type'), category: text(p.category, 'category', 80), note: typeof p.note === 'string' ? p.note.slice(0, 2000) : null, date: date(p.date) };
  if (kind === 'budgets') {
    requireValue(Number.isInteger(p.month) && p.month >= 1 && p.month <= 12 && Number.isInteger(p.year) && p.year >= 1970 && p.year <= 9999, 'Invalid budget period.');
    return { ...common, category: text(p.category, 'category', 80), limitAmount: amount(p.limitAmount), month: p.month, year: p.year };
  }
  if (kind === 'goals') {
    const target = amount(p.targetAmount), saved = existing?.savedAmount ?? 0;
    const status = oneOf(p.status ?? 'ACTIVE', ['ACTIVE', 'COMPLETED', 'CANCELLED', 'ARCHIVED'], 'goal status');
    requireValue(status !== 'COMPLETED' || saved >= target, 'The target has not been reached.');
    const deadline = p.deadline == null ? null : date(p.deadline);
    requireValue(deadline === null || deadline >= common.createdAt, 'Deadline precedes goal creation.');
    return { ...common, title: text(p.title, 'title'), targetAmount: target, savedAmount: saved, status: saved >= target && status === 'ACTIVE' ? 'COMPLETED' : status, deadline };
  }
  if (kind === 'bills') {
    const due = date(p.nextDueDate), frequency = oneOf(p.frequency, ['WEEKLY', 'MONTHLY', 'YEARLY'], 'frequency');
    const unchanged = existing && due === existing.nextDueDate && frequency === existing.frequency;
    return { ...common, title: text(p.title, 'title'), category: text(p.category, 'category', 80), amount: amount(p.amount), frequency, nextDueDate: due, status: oneOf(p.status ?? 'ACTIVE', ['ACTIVE', 'PAUSED', 'CANCELLED'], 'status'), anchorDate: unchanged ? existing.anchorDate : due, paidOccurrences: unchanged ? existing.paidOccurrences : 0 };
  }
  throw new DomainError('Unknown collection.');
}
// Durable recurrence uses a Kigali calendar-day anchor (UTC+02:00).
export function billOccurrence(anchor, frequency, offset) {
  date(anchor);
  requireValue(Number.isSafeInteger(offset) && offset >= 0 && offset <= 100000, 'Invalid occurrence.');
  const local = new Date((anchor + 7200) * 1000);
  const year = local.getUTCFullYear(), month = local.getUTCMonth(), day = local.getUTCDate();
  let target;
  if (frequency === 'WEEKLY') target = Date.UTC(year, month, day + offset * 7);
  else {
    const targetMonth = frequency === 'MONTHLY' ? month + offset : month;
    const targetYear = frequency === 'YEARLY' ? year + offset : year;
    oneOf(frequency, ['MONTHLY', 'YEARLY'], 'frequency');
    const last = new Date(Date.UTC(targetYear, targetMonth + 1, 0)).getUTCDate();
    target = Date.UTC(targetYear, targetMonth, Math.min(day, last));
  }
  return date(target / 1000 - 7200);
}
export function totals(transactions) {
  let income = 0, expenses = 0;
  for (const t of transactions) {
    if (t._deleted) continue;
    if (t.type === 'INCOME') income = add(income, amount(t.amount));
    else if (t.type === 'EXPENSE') expenses = add(expenses, amount(t.amount));
    else throw new DomainError('Invalid stored transaction type.', 'data-loss');
  }
  return { income, expenses, balance: add(income, -expenses) };
}
