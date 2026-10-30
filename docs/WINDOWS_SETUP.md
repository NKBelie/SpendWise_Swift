# Windows domain development

The Swift package in this repository contains platform-independent domain code.
The SwiftUI iOS application and Firebase Apple SDK integration require macOS
with Xcode; they cannot be built or run natively on Windows.

## Confirmed validation status

During validation on 2026-10-30:

- The compiler reported Swift 6.4.1, targeting `x86_64-unknown-windows-msvc`.
- A sandboxed invocation was denied permission to execute `swift-frontend.exe`.
- Running outside that sandbox reached manifest compilation, which failed with
  `'stdlib.h' file not found` and `could not build C module 'SwiftShims'`.
- Visual Studio Installer reported Visual Studio Community 2026, but no instance
  satisfying `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`.
- The standard Windows Kits directory contained no `Include` directory.
- Downloading the Microsoft Build Tools bootstrapper failed because `aka.ms`
  could not be resolved on the initial attempt.

On a subsequent attempt, the Microsoft-signed Build Tools bootstrapper downloaded
successfully and installation started. Visual Studio 2022 Build Tools became
registered, but the required C++ component and Windows SDK headers were still
absent at the last check. Installer logs showed package downloads still pending
and installer-feed request cancellations. A second bootstrapper returned exit
code 0 while the original installation remained active; that result did not
establish that the prerequisites were ready.

The original installation subsequently finished, but its error log reported that
`Win11SDK_10.0.22621` could not download because
`download.visualstudio.microsoft.com` could not be resolved (error `0x80070002`).
The C++ tools component is now registered; SDK headers remain absent. A subsequent
`swift test` still failed with `'stdlib.h' file not found` before compiling package
sources. Restore download connectivity and retry the Windows SDK component in
Visual Studio Installer before retrying package validation.

The package and tests have **not** been verified as passing. The manifest error
does not establish a source defect: the compiler cannot find required C headers.

## Install Windows prerequisites

Follow the official Swift instructions:

- https://www.swift.org/install/windows/
- https://www.swift.org/install/windows/manual/

Install the Microsoft C++ tools and a Windows SDK listed in those instructions.
Installing VS Code alone does not supply these components. The documented
Visual Studio 2022 component identifiers relevant to this x64 package are:

- `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`
- `Microsoft.VisualStudio.Component.Windows11SDK.22621`

Use the Visual Studio Installer or the official Swift installation procedure.
If the Microsoft download cannot be reached, restore network/DNS access before
retrying. Do not download individual missing headers from third-party sites.

## Verify the installation

Open a new PowerShell terminal after installation. Query the installed C++ tools:

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe' -all -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
```

The command should return an installation path. Verify Windows SDK headers:

```powershell
Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\Include' -Filter stdlib.h -Recurse
```

For a standard SDK installation, this should locate `stdlib.h` under a versioned
`ucrt` directory. If components are installed elsewhere, check that installation
instead. If Swift still cannot discover installed components, use the installed
Visual Studio Developer PowerShell for x64 and retry there.

## Build and test

```powershell
Set-Location D:\SWIFT\SpendWise
swift --version
swift build
swift test
```

Expected result: the library builds and all Swift Testing tests pass, including
parameterized cases. Tests cover personal totals, wallet balance,
manager capability, the default member role, membership JSON round trips,
separation of global roles from wallet roles, financial validation, and
deterministic invitation and consent expiration boundaries, integer overflow,
duplicate records, mixed record ownership, and monthly budget calculations
across time zone boundaries.
Transaction repository tests also cover CRUD, owner isolation, filtering,
idempotent creates and deletes, revision conflicts, concurrent edits, and
cancellation.
Recurring-bill tests cover calendar-day due states, month ends, leap years,
anchor-preserving projections, daylight-saving changes, and invalid offsets.

If validation fails, capture diagnostics with:

```powershell
swift test --verbose 2>&1 | Tee-Object -FilePath "$env:TEMP\SpendWise-swift-test.log"
```

In a managed coding environment, compiler execution may separately require
approval outside its sandbox. Missing SDK headers and sandbox execution denial
are distinct failures; resolving one does not necessarily resolve the other.
