---
mapped: 2026-09-09
focus: quality
---

# Testing — stellar-ios

## Framework and runner

- **XCTest** (not Swift Testing). Test classes are `@MainActor final class X: XCTestCase`.
- **`swift test` does not work here** — `@Observable` plus UIKit-backed SwiftUI
  means the package cannot build for the host. Everything runs on a simulator.

```bash
export IOS_SIM_ID=71E156C3-0CC1-4659-86AA-B044DE8CDBEB   # iPhone 16 Pro, iOS 18.3
scripts/test.sh

# or, when you need per-test output:
xcodebuild -project StellarVolumiO.xcodeproj -scheme StellarVolumiO \
  -destination "id=$IOS_SIM_ID" test
```

**Gotcha:** `scripts/test.sh` passes `-quiet`, which suppresses the
`Executed N tests` lines. It reports pass/fail by exit code only. Invoke
`xcodebuild test` directly when you need counts or a failing case name.

**Gotcha:** simulator device names are duplicated (two "iPhone 16 Pro" on
iOS 18.3; every iPad model exists on both 18.3 and 26.3). A `name=` destination
selector is ambiguous and fails — always select by UDID.

Current baseline: **205 tests, 0 failures**, clean build with **0 warnings**.

## Structure

One flat directory, `StellarVolumiOTests/`, 25 files plus `Fixtures/`.
Named `<Subject>Tests.swift`.

Three broad kinds:

| Kind | Example | What it covers |
|---|---|---|
| Parser tests | `PlayerStateParserTests`, `LibraryEnvelopeParserTests`, `AirplayStateTests` | `init(rawDict:)` accepting good payloads and rejecting malformed ones |
| Store behaviour tests | `PlayerStoreSeekTests`, `AlbumTracksStoreTests`, `LcdStoreTests` | state transitions driven by injected instants / synthetic events |
| Render smoke tests | `AirplayRenderSmokeTests`, `SmokeTest` | the view hierarchy actually composes |

## The render-smoke pattern — the lever for iPad layout TDD

There is **no UI test target** (`XCUIApplication` appears nowhere). Layout is
tested by hosting the real SwiftUI hierarchy in a `UIHostingController`, forcing
a layout pass, and asserting on the result. `AirplayRenderSmokeTests` is the
reference implementation: it builds the environment graph, injects state via a
`_debugInject` helper, wraps the view in `UIHostingController`, walks the tree to
force body evaluation, and asserts the host view is non-nil and laid out.

For the iPad port this pattern extends naturally: set the hosting controller's
frame to iPad dimensions (or override the size-class trait) and assert the
expected branch rendered.

**Prefer extracting layout decisions into pure, testable types.** A function or
small value type that maps `(horizontalSizeClass, orientation) -> LayoutMode` can
be unit-tested directly with no rendering at all — that is the cheapest and most
durable place to put the port's logic, and TDD should start there.

## Critical test-authoring trap

**Store tests must bind a *named* `SocketService` local.** Stores hold the socket
weakly:

```swift
// WRONG — the service deallocates immediately, every action silently no-ops
store.bind(to: SocketService())

// RIGHT
let socket = SocketService(config: BackendConfigStore())
store.bind(to: socket)
```

Because `scripts/test.sh` runs `-quiet`, this failure mode presents as tests that
pass while asserting nothing. It has bitten this repo before.

## Debug affordances available to tests

- `AirplayStore._debugInject(_:)` — force an AirPlay session.
- `SocketService` DEBUG capture: `lastEmittedEvent`, `lastEmittedData`,
  `lastEmittedFirstArgument`, `resetEmittedCapture()` — used by
  `SocketEmitArgumentShapeTests` to assert wire-argument shape without a server.

## Definition of done for a phase

1. `xcodegen generate --spec project.yml` if any file was added
2. Clean build with **zero** warnings
3. Full suite green on the iPhone regression sim **and** the iPad sims
4. Conventional commit, pushed to `feature/ipad-port`
