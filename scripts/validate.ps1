param([switch]$SkipSwift, [switch]$Emulators)
$ErrorActionPreference = 'Stop'
$spendWiseRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location -LiteralPath $spendWiseRoot
try {
    node --test firebase/functions/test/domain.test.js firebase/functions/test/commands.test.js
    if ($LASTEXITCODE -ne 0) { throw 'Backend domain tests failed.' }
    node --check firebase/functions/index.js
    if ($LASTEXITCODE -ne 0) { throw 'Backend syntax check failed.' }
    node --check firebase/functions/command-handler.js
    if ($LASTEXITCODE -ne 0) { throw 'Backend handler syntax check failed.' }
    if (-not $SkipSwift) {
        swift test
        if ($LASTEXITCODE -ne 0) { throw 'Swift tests failed. See docs/WINDOWS_SETUP.md for Windows prerequisites.' }
    }
    if ($Emulators) {
        npm run test:rules
        if ($LASTEXITCODE -ne 0) { throw 'Firestore Rules tests failed.' }
        npm run test:integration
        if ($LASTEXITCODE -ne 0) { throw 'Callable integration tests failed.' }
    }
} finally { Pop-Location }
