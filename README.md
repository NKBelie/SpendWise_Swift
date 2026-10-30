# SpendWise

Personal finance and shared-wallet management in Swift and SwiftUI, with Firebase
Authentication, Firestore, and trusted Cloud Functions. Money is stored as integer
Rwandan Francs (RWF).

## Project layout

```text
Sources/SpendWise/       Portable Swift domain models, calculations and repositories
Tests/SpendWiseTests/    Swift Testing domain tests
SpendWiseApp/           SwiftUI iOS app, view models, Firebase adapters and iOS tests
firebase/functions/     Authenticated, validated, atomic backend commands
firebase/firestore.rules
firebase/tests/         Security Rules and callable integration tests
scripts/                Validation, Mac build and simulator capture commands
docs/                   Architecture, security, setup and delivery notes
```

Windows supports development of the domain library. SwiftUI and Firebase's Apple
SDKs require macOS and Xcode. An XcodeGen spec creates the iOS application project;
`Package.swift` deliberately remains an independent library without Firebase.

## Start here

1. [Validation status and remaining work](docs/DELIVERY.md)
2. [Windows setup](docs/WINDOWS_SETUP.md)
3. [iOS setup and builds](docs/IOS_SETUP.md)
4. [Firebase setup and emulator tests](docs/FIREBASE_SETUP.md)
5. [Architecture](docs/ARCHITECTURE.md) and [security](docs/SECURITY.md)

## Features implemented in source

- Welcome, registration, login, password reset, logout, session gates and profile editing.
- Dashboard, integer RWF balances, six-month cash-flow chart and category insights.
- Transaction CRUD, detail screens, search, filters and deletion confirmation.
- Monthly budgets with remaining amounts, utilization and near-limit warnings.
- Savings goals, atomic contributions, contribution history, completion and archiving.
- Recurring bills, calendar scheduling, overdue states and atomic payment recording.
- Wallet creation, account-bound invitations, acceptance/decline and membership roles.
- Contribution-pool ledger implementation and shared budgets, **disabled pending
  confirmation of the financial model**. `WALLET_MODEL` defaults to `UNCONFIRMED`.
- Advisor requests, explicit scoped consent, approved summary snapshots, revocation,
  recommendations and history. No advisor access to private transaction collections.
- Trusted admin account/role/status changes, category management and audit history.
- Adaptive components, light/dark mode, Dynamic Type and accessible chart text.

Source implementation is not a claim of a verified production release. See the
delivery report for exact checks performed and environment blockers. Background
notifications, deployment, App Store assets and real simulator screenshots have
not been produced in this Windows environment.

## Local checks

PowerShell, from the repository root:

```powershell
npm test
swift test
```

For backend/emulator checks, use Node 22 and Java 21:

```powershell
npm install
npm ci --prefix firebase/functions
npm test
npm run test:rules
npm run test:integration
```

`scripts/validate.ps1` runs domain/backend checks. `-SkipSwift` permits backend-only
validation while Windows SDK prerequisites are repaired; `-Emulators` adds both
Firebase suites. Skipping a suite never counts as passing it.
If your Windows execution policy blocks local PowerShell scripts, run the listed
commands directly; no policy change is needed for those commands.

No real Firebase project, service-account credentials or Apple signing identity
is committed. No cloud resources were deployed and no GitHub changes were pushed.
