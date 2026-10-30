# Security model

## Authority boundaries

Firebase Authentication establishes identity. The server-only `access/{uid}`
document establishes global role and account status. Clients cannot create or
change it. Profile role/status mirrors are for presentation; all privileged
decisions re-read the canonical access record. Roles are not inferred from hidden
buttons or client-editable fields. The initial admin requires a trusted Admin SDK
bootstrap. Normal account initialization always creates `PERSONAL_USER`.

Wallet roles live in `wallets/{walletID}/members/{uid}` and are independent of
global roles. Administrators have no automatic wallet membership or private
finance bypass. Advisors cannot read private finance collections.

## Firestore Rules

All client writes are denied. Validated writes go through App Check-protected,
authenticated callable functions in production. Rules allow:

- Active users to read only their own profile and private finance collections.
- Current wallet members to read that wallet's membership and ledger.
- Invitation participants to read their own invitations.
- Clients to read their own requests, consents and recommendations.
- Advisors to read a summary only while the referenced consent is active and
  unexpired, both accounts are active, and the advisor still has that role.
- Administrators to read audit history and invoke a limited account directory.

The admin directory returns name, email, role and account status only. It never
returns private subcollections. Account suspension blocks protected reads and
commands immediately through access-record checks even for existing Auth tokens.
It does not delete/disable the Firebase Auth identity or claim to revoke its token.

## Trusted command processing

The Admin SDK bypasses Rules, so every callable independently verifies identity,
active account status, role, ownership or current wallet membership. User-supplied
owner IDs, admin roles, saved totals and server creation dates are ignored.

Writes occur in Firestore transactions. An operation receipt binds the operation
identifier to a SHA-256 hash of the canonical command payload and its result.
Replays return the result; changed payloads with the same identifier are rejected.
Revision checks reject stale personal-record edits. Durable tombstones prevent
recreating deleted records with revision zero. Financial totals use safe-integer
and range checks. Documents are built from whitelisted fields, never raw payloads.

Bill payments atomically record a payment, create an immutable expense, and advance
the durable recurrence anchor/index. A separate per-occurrence receipt prevents
double payment after a due-date reset. Savings contributions append immutable
history and update progress atomically. The operation receipts are deliberately
retained; deleting them carelessly can weaken retry guarantees.

Wallet invitations identify a specific Auth UID, expire in seven days, and grant
only family-member access when accepted. Acceptance requires the inviter to still
be a manager and the wallet to be active. Managers cannot remove/change the wallet
creator through member management; self privilege changes are also rejected.

Administrative changes re-check the actor inside the transaction and record an
audit event. Administrators cannot alter their own access through the UI/callable.
Concurrent cross-demotions conflict on access records and retry under current
authority instead of silently leaving both actors privileged.

## Advisor consent

Scopes are explicit and default unchecked in the UI. The backend builds snapshots
from owned data and includes only selected aggregate fields. It never copies
transaction titles, notes, transaction documents or individual goals. Consent
expires within 90 days. Revocation changes the canonical grant used by Rules and
recommendation writes; no further summary read is authorized. Metadata and an
advisor's already-viewed information are not retroactively erased. Clients retain
their own recommendation history.

Summary scopes currently mean all-time income/expense/balance totals, combined
budget count/limits, or combined savings/targets. The UI describes these exact
fields; the data is a snapshot, not ongoing access to changing private records.

## Validation and release limits

Security Rules tests cover owner isolation, unauthorized roles, direct write
denial, membership revocation, consent expiry/revocation, suspension and audit
access. Callable integration tests cover role defaults, replay protection,
ownership, stale concurrent writes, summary-only sharing and revocation.

See `DELIVERY.md` for actual execution results. Source review and syntax checks are
not substitutes for passing emulator tests and Apple platform builds. Before a
production launch, complete those checks, test App Check on real devices, review
project IAM and regional/data-retention choices, and finalize the account-deletion
workflow and privacy disclosures. No credentials, signing keys or private user
data belong in this repository.
