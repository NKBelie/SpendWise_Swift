#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift --version
xcodegen generate --spec SpendWiseApp/project.yml --project SpendWiseApp
xcodebuild -project SpendWiseApp/SpendWiseApp.xcodeproj -scheme SpendWiseApp \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/ios \
  CODE_SIGNING_ALLOWED=NO build
