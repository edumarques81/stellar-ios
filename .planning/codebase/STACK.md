---
mapped: 2026-09-09
focus: tech
---

# Stack — stellar-ios

## Language & runtime

| Item | Value |
|---|---|
| Language | Swift, `SWIFT_VERSION: "5.9"` in `project.yml` (Swift 6 strict-concurrency *warnings* are on; language mode is still 5) |
| UI framework | SwiftUI, `@Observable` (Observation framework) — `ObservableObject` is banned by convention |
| Min deployment target | iOS 17.0 |
| Bundle id | `fit.stellar.remote` |
| Team | `3S2JYQ4JNX`, `CODE_SIGN_STYLE: Automatic` |
| Toolchain on this Mac | **Xcode 26.3 (17C529)** — clears Apple's 2026 SDK floor |
| Simulator runtimes | iOS 18.3 and iOS 26.3 |

## Project generation — read this before touching the build

The `.xcodeproj` is **generated**, never hand-edited:

```bash
xcodegen generate --spec project.yml     # REQUIRED after adding any .swift file
```

`scripts/build.sh` does **not** regenerate. Skipping this step produces
`cannot find X in scope` errors that look like source bugs but are not.

`Package.swift` is the canonical place to add Swift package dependencies;
`project.yml` is a thin Xcode wrapper so `xcodebuild` can produce a signable,
installable `.app` (a bare SwiftPM package cannot be signed and installed).

## Dependencies

| Package | Version | Product | Used by |
|---|---|---|---|
| `socket.io-client-swift` | from 16.1.0 (resolves 16.1.1) | `SocketIO` | `Services/SocketService.swift` |
| Starscream | transitive via SocketIO | — | websocket transport |

No other third-party code. Everything else is Foundation / SwiftUI / Network.

## Build settings that the iPad port must change

Located in `project.yml` under `targets.StellarVolumiO.settings.base` and
`.info.properties`:

| Key | Current | iPad impact |
|---|---|---|
| `TARGETED_DEVICE_FAMILY` | `"1"` (iPhone only) | **must become `"1,2"`** |
| `UIRequiresFullScreen` | `YES` | **deprecated on iPadOS 26**; blocks Split View / Stage Manager. Must be removed. |
| `UISupportedInterfaceOrientations` | `[UIInterfaceOrientationPortrait]` only | must gain landscape left/right and portrait-upside-down |
| `deploymentTarget.iOS` | `"17.0"` | unchanged — `NavigationSplitView` is iOS 16+ |
| `GENERATE_INFOPLIST_FILE` | `YES` | Info.plist is synthesised from the `info.properties` block; there is no plist file on disk |

Other Info.plist entries (leave alone): `NSAppTransportSecurity.NSAllowsLocalNetworking`,
`NSLocalNetworkUsageDescription`, `NSBonjourServices: [_stellar._tcp]`,
`ITSAppUsesNonExemptEncryption: false`.

## Scripts

| Script | Purpose | Notes |
|---|---|---|
| `scripts/build.sh` | `xcodebuild` against a simulator | needs `IOS_SIM_ID` exported — two "iPhone 16 Pro" sims exist, so `name=` selectors are ambiguous |
| `scripts/test.sh` | test via simulator | passes `-quiet`, which **hides per-test counts**; exit code only |
| `scripts/deploy-to-device.sh` | xcodegen → xcodebuild → `devicectl install+launch` | takes a model selector, e.g. `./scripts/deploy-to-device.sh "15 Pro"` |

`swift test` does **not** work in this repo (`@Observable` + UIKit-backed
SwiftUI); everything must go through a simulator destination.

## Simulator matrix pinned for the iPad port

| Role | Device | Runtime | UDID |
|---|---|---|---|
| iPad primary | iPad Pro 11-inch (M4) | iOS 26.3 | `49C99399-FBED-4478-AD20-3B7F63D653C7` |
| iPad small regular-width | iPad mini (A17 Pro) | iOS 26.3 | `D204C330-DE77-4760-919D-8AAD044DA93E` |
| iPhone regression | iPhone 16 Pro | iOS 18.3 | `71E156C3-0CC1-4659-86AA-B044DE8CDBEB` |

Device names are duplicated across the two runtimes — always select by UDID.
