# Firebase setup

## Requirements

Use Node **22**, npm, Java **21**, and a Firebase project with Authentication,
Cloud Firestore and Cloud Functions enabled. Production Functions deployment
requires the appropriate billing plan and project permissions. No live project
was configured or deployed by this change.

The implementation follows Firebase's official [Apple setup](https://firebase.google.com/docs/ios/setup),
[callable functions](https://firebase.google.com/docs/functions/callable),
[transactions](https://firebase.google.com/docs/firestore/manage-data/transactions),
and [Rules testing](https://firebase.google.com/docs/rules/unit-tests) documentation.

## Install and test on Windows

```powershell
Set-Location D:\SWIFT\SpendWise
npm install
npm ci --prefix firebase/functions
npm test
npm run check:backend
npm run test:rules
npm run test:integration
```

The test scripts use the isolated `demo-spendwise` project and start/stop their
own emulators. They must not be pointed at a production project. Emulator downloads
require working DNS and HTTPS access. A local Node 20 installation may run the pure
domain tests, but Node 22 is the configured backend runtime and validation target.

To keep all emulators running for an iOS simulator:

```powershell
npx firebase emulators:start --only auth,firestore,functions --project demo-spendwise
```

Ports: Auth 9099, Firestore 8080, Functions 5001, emulator UI 4000. Function region:
`europe-west1`. The callable uses App Check in production and disables enforcement
only when the Functions emulator marks itself as running.

## Configure a real project

1. Create/select your project in Firebase Console; enable email/password sign-in.
2. Create Firestore in a region appropriate for your users and compliance needs.
   Confirm the Functions region before storing live records; the client and server
   currently both select `europe-west1`.
3. Register an Apple app with the bundle ID you will use in Xcode. Download its
   `GoogleService-Info.plist` into `SpendWiseApp/Resources/`; it is ignored by Git.
4. Register App Attest with Firebase App Check. Debug builds use the Debug provider;
   register the debug token shown by Xcode for development against a real backend.
5. Configure Firebase Authentication's password policy, email templates and email
   enumeration protection for your project. The client registration minimum is
   eight characters; Firebase's server policy remains authoritative.
6. Validate in the emulators and on a Mac before deployment.

The generated bundle ID defaults to `com.spendwise.SpendWiseApp`. Change it in
`SpendWiseApp/project.yml` if required **before** registering the Apple app.

## Shared-wallet model

`WALLET_MODEL` is a Cloud Functions parameter and defaults to `UNCONFIRMED`.
Wallet creation/invitations/membership work independently of the ledger. Ledger
contribution, expense and budget commands refuse writes until the model has been
confirmed. Do not enable a financial model merely to bypass this check.

Once the product owner confirms a contribution pool, add this setting to the
appropriate ignored `firebase/functions/.env.PROJECT_ID` file before deployment:

```dotenv
WALLET_MODEL=CONTRIBUTION_POOL
```

The implemented pool formula is contributions minus shared expenses. Members
record their own contributions; managers record expenses and shared budgets.
Negative balances represent recorded spending in excess of contributions; no
expense splitting, bank transfer or debt-settlement calculation is implied.
An expense-splitting or hybrid choice requires another domain implementation.

## Deploy deliberately

After emulator tests, Mac builds and project configuration succeed:

```powershell
npx firebase login
npx firebase deploy --only firestore,functions --project YOUR_PROJECT_ID
```

The repository does not contain a default live project alias. Always provide the
project explicitly. This command publishes security-sensitive infrastructure;
review `docs/SECURITY.md` and the test results before executing it.

## Bootstrap the first administrator

Create an ordinary account through the app and sign in once. In a trusted terminal
with Application Default Credentials authorized for the target project, run:

```powershell
Set-Location D:\SWIFT\SpendWise\firebase\functions
node bootstrap-admin.js YOUR_PROJECT_ID EXISTING_ACCOUNT_UID
```

This uses the Admin SDK, not client credentials, and records an audit event. Do not
ship service-account keys in the app or commit them. Subsequent role and status
changes use the admin UI and trusted callable. Role authority is the server-only
`access` collection; editable client profile fields cannot grant privileges.

## Recovery

An interrupted SDK installation or failed package download does not count as a
successful test. Restore network/DNS access, retry `npm install` at the root and
`npm ci --prefix firebase/functions`, then rerun the checks. Avoid overlapping
installs into the same dependency directory. If an account's access/profile pair
is inconsistent, repair it from a trusted administrative environment; clients
cannot recreate missing privilege records.
