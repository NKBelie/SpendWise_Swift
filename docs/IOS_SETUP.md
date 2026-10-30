# iOS setup

## Build environment

Use a Mac with Xcode and an Apple Swift toolchain capable of reading the existing
`swift-tools-version: 6.4` package. Firebase's current [Apple setup guide](https://firebase.google.com/docs/ios/setup)
lists its Xcode and deployment prerequisites; the package's Swift requirement may
require a newer compatible Xcode/toolchain. Run both `swift --version` and
`xcrun swift --version`; merely installing Windows Swift does not configure Xcode.

The app targets iOS 17+, uses Swift Charts and Observation, and supports iPhone
and iPad. It is not a Windows executable. Full Apple SDK type checking and
simulator execution were not available during Windows development.

## Generate the application project

Install [XcodeGen](https://github.com/yonaskolb/XcodeGen), clone this repository on
the Mac and follow `FIREBASE_SETUP.md` to obtain your app's configuration.

```bash
brew install xcodegen
cp /path/to/GoogleService-Info.plist SpendWiseApp/Resources/GoogleService-Info.plist
xcodegen generate --spec SpendWiseApp/project.yml --project SpendWiseApp
open SpendWiseApp/SpendWiseApp.xcodeproj
```

The project specification contains all app sources, test sources, the local domain
package and Firebase SDK products. In Xcode, select your signing team and ensure
the bundle ID matches the Firebase Apple registration. Resolve package versions
and retain the generated Package.resolved file after successful validation.

The repository intentionally ships the reproducible XcodeGen spec rather than
claiming an Xcode project was generated/tested on Windows. Add an App Store app
icon asset and review the privacy manifest before an archive submission. There is
no fabricated app icon, simulator screenshot or signed archive in this delivery.

For an unsigned simulator build:

```bash
bash scripts/build-ios.sh
```

For the app's Swift Testing view-model tests, choose an installed simulator:

```bash
xcodebuild -showdestinations -project SpendWiseApp/SpendWiseApp.xcodeproj -scheme SpendWiseApp
xcodebuild -project SpendWiseApp/SpendWiseApp.xcodeproj -scheme SpendWiseApp \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' CODE_SIGNING_ALLOWED=NO test
```

Run the portable tests separately with `swift test` at the repository root.

## Connect to emulators

Start the Auth, Firestore and Functions emulators on the host computer. In the
Xcode scheme's Run > Arguments > Environment Variables, set:

```text
SPENDWISE_EMULATORS = 1
SPENDWISE_EMULATOR_HOST = 127.0.0.1
```

For emulators on the Windows computer, use that computer's reachable LAN address
instead of 127.0.0.1 and bind the emulator host/firewall deliberately for that
development network. Keep emulators off public networks. The app only honors
these settings in Debug builds.

The Firebase configuration's project ID must match the emulator project. Use a
separate demo/development configuration for local testing. Missing configuration
shows a setup screen instead of crashing or displaying fictional balances.

## Runtime behavior

Signed-out users see onboarding and authentication. After authentication, a
trusted callable initializes the personal-user profile. Tabs are not shown until
profile loading and account-status checks succeed. Sign-out discards workspace
view models and data. No password is stored by application code.

The app reads Firestore from the server and uses memory-only caching. It provides
explicit refresh and clear network failures; it does not promise offline writes.
Account changes are enforced on the server even while a previously opened screen
remains visible. Advisor details poll while open and hide expired snapshots.
Previously viewed information cannot be remotely erased from someone's memory
or screenshots by revoking access.

## Visual and accessibility review

Verify a small and large iPhone, iPad, light/dark appearances, large Dynamic Type,
VoiceOver reading order, keyboard navigation and error recovery. Native progress
bars and charts have textual amounts so color alone does not convey financial
state. Use `scripts/capture-screenshot.sh` for genuine simulator artifacts; see
`screenshots/README.md`.

No push/local notification infrastructure is configured. Bill reminders are
in-app indicators only. Before App Store distribution, finish product-specific
privacy/support URLs, app icon, account-deletion policy/workflow, consent copy,
release signing and the store's privacy disclosures. The included manifest is a
starting declaration for the implemented app behavior, not an App Store approval.
