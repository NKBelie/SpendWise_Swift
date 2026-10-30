# Delivery and verification report

The repository now contains the portable Swift domain layer, a SwiftUI iOS app
target specification with Firebase adapters, and trusted Firebase backend source.
Existing domain models/calculators/tests were extended rather than replaced by a
new application template. This is a source delivery awaiting platform and cloud
configuration/validation, **not a claim that the app is production-ready**.

## Checks actually performed

| Check | Result |
|---|---|
| Backend domain and injected command-handler tests | **14 passed** on local Node 20.20.2 |
| Firebase callable adapter module load | Passed after repairing dependencies |
| Backend and emulator-test JavaScript syntax | Passed |
| Swift domain, SwiftUI and test syntax parsing | Passed with Swift 6.4.1 frontend |
| JSON configuration and privacy XML parsing | Passed |
| PowerShell validation wrapper | Blocked by local script execution policy; its backend commands passed directly |
| `swift test` | Blocked before source compilation: Windows SDK `stdlib.h` missing |
| Firestore Rules emulator tests | Not executed: dependency/tool installation blocked by registry DNS access |
| Auth/Functions/Firestore integration tests | Not executed for the same tooling blocker |
| XcodeGen project generation and iOS build | Not executed: macOS/Xcode unavailable |
| iOS view-model tests and UI review | Written, not executed: require a compatible Mac |
| Simulator screenshots and signed archive | Not produced |
| Firebase deployment / GitHub push | No Firebase deployment; source publishing uses separate folder commits to origin/main |

Syntax parsing checks grammar only. It does not resolve SwiftUI/Firebase types,
check concurrency across SDK boundaries, link Apple frameworks or execute tests.
The backend's configured runtime is Node 22; its current local Node 20 pass does
not replace the Node 22 CI/emulator run. Command tests use a serialized in-memory
transaction double, not real Firestore transaction retries or Rules enforcement.

The backend dependencies installed successfully after a clean lockfile install.
The initial root test-tool install failed to resolve `registry.npmjs.org`; its
retry stalled without completing and was stopped. Restore connectivity before
running both emulator suites. No failed or skipped suite is counted as passed.

## Source coverage by phase

| Phase | Delivered source |
|---|---|
| 1 · Assessment | Repository findings and preserved domain package |
| 2 · Domain | Models, validators, safe calculators, insights, recurrence, transaction repository and tests |
| 3 · Design | Adaptive theme, cards, amount fields, rows, errors, loading and confirmations |
| 4 · Authentication | Onboarding, register/login/reset/logout, profile initialization and session gating |
| 5 · Personal finance | Dashboard, charts, transaction CRUD/filter/search/detail, budgets, savings/history and bills/history |
| 6 · Wallets | Creation, secure invitations, membership roles/removal; gated contribution-pool ledger and shared budgets |
| 7 · Advisor/admin | Scoped consent snapshots, requests/recommendations, trusted account/category management and audit |
| 8 · Firebase | Auth service, Firestore read repository, atomic validated callable writes, deny-by-default Rules |
| 9 · Validation | Local backend tests and syntax checks; emulator/Mac suites and manual checklist supplied |
| 10 · Documentation | README, architecture, security, setup, scripts, CI and screenshot/GitHub instructions |

## Decisions and external work still required

1. **Confirm the shared-wallet model.** The product question is still pending.
   `WALLET_MODEL=UNCONFIRMED` blocks wallet contributions, expenses and budgets.
   Contribution-pool code must only be enabled after explicit confirmation.
2. **Repair the Windows SDK** to run the portable tests locally, or run the Swift
   suite in the supplied Linux CI job with Swift 6.4.1.
3. **Run emulator suites** with Node 22 and Java 21 after dependency/download access
   is restored. Review/fix any failures before deploying Rules or Functions.
4. **Build and test on a compatible Mac**, including the iOS tests and the manual
   accessibility/UX checks below. Any Apple-platform compiler issues must be fixed
   there before treating those features as validated.
5. **Configure the actual Firebase project**, Apple bundle ID, App Check and
   signing identity. Bootstrap the first administrator using trusted credentials.
6. **Finish distribution assets/policies**: genuine screenshots, app icon, privacy
   and support URLs, account-deletion workflow and App Store disclosures.

No bank transfers, expense splitting, background notifications, continuous live
listeners or offline writes are claimed. The current interactive data limit is
5,000 records per collection; larger accounts fail clearly until pagination and
server aggregation are implemented.

## Manual acceptance checklist on Mac/emulators

- Register a user, sign out, sign in, reset password, edit profile and verify
  protected tabs disappear immediately on logout.
- Record income RWF 150,000 and expense RWF 30,000: balance must be RWF 120,000.
  Search/filter, edit, and confirm deletion; refresh on another client to verify.
- Create a Food budget of RWF 40,000 in the expense month: spending is 75% of its
  limit. At 80% a warning appears; overspending shows negative remaining funds.
- Create a savings target RWF 100,000 and contribute RWF 25,000: progress is 25%.
  Verify history, retry behavior, completion and archive preservation.
- Create a monthly bill on January 31; record a payment and verify the expense,
  payment history and February month-end due date. A second payment of the same
  occurrence must be rejected. Verify paused, cancelled, due-today and overdue states.
- Invite another account to a wallet. A third account cannot accept its invitation.
  Verify membership permissions, manager changes and removal. Test ledger actions
  only after the financial model is confirmed and enabled.
- Assign an advisor role from trusted administration. Share only spending totals;
  verify the advisor sees no titles/notes/private collections. Revoke access and
  confirm future summary reads and recommendations fail.
- Verify a personal user cannot perform admin commands, an admin cannot read
  another user's transactions, suspended accounts lose protected access, and
  account/category changes create audit records.
- Test a lost response/retry, stale concurrent edits, foreground refresh, an empty
  account, invalid amounts, dark mode, large text, VoiceOver and small iPhone layout.

## GitHub handoff

Review the local changes first. The original repository tracked only Package.swift;
the source tree and new infrastructure are now being published in separate folder
commits at the owner's request. No user work was discarded and no branch was reset.
Consult `git log` and the remote branch for current publishing status.

PowerShell commands for the owner to run after reviewing validation results:

```powershell
git status --short
git diff --check
git add -- Sources
git diff --cached --stat
git commit -m "Describe the reviewed Sources changes"
git remote -v
git push origin main
```

For future changes, repeat this process for one folder at a time; commit root-level
files separately. Commit generated lockfiles after successful dependency resolution. Before pushing,
inspect the staged files for credentials, real financial data and local Firebase
configuration. Add your own GitHub remote if one is not configured, then push the
reviewed branch and open a pull request with the actual validation results. The
CI workflow runs portable Swift and backend/emulator tests; the manual iOS workflow
requires a self-hosted Mac labeled `spendwise-ios` with compatible Xcode/Swift.
