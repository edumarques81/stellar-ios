# Testing Patterns

**Analysis Date:** 2026-09-09

## Test Framework

**Runner:** XCTest exclusively. **No Swift Testing (`import Testing`, `@Test`) anywhere in this
repo** — every suite is `final class FooTests: XCTestCase` with `func testXxx()` methods.

**Two test targets exist, with very different roles:**

| Target | Location | Purpose | In default scheme? |
|---|---|---|---|
| `StellarVolumiOTests` | `StellarVolumiOTests/` | Unit + render/geometry tests, hermetic, fast | Yes — this is what `scripts/test.sh` runs |
| `StellarVolumiOUITests` | `StellarVolumiOUITests/` | `XCUIApplication`-driven end-to-end sweep against a **real backend** | No — run explicitly, see below |

**Config:** No `xctestplan` file; the scheme (`StellarVolumiO.xcodeproj/xcshareddata/xcschemes/`)
and `project.yml` define what builds. `project.yml` does not declare a `StellarVolumiOUITests`
target block visible in the excerpt read — that target's presence/wiring should be re-verified
against `project.yml` before assuming xcodegen regenerates it identically; if in doubt, run
`xcodegen generate --spec project.yml` before targeting it.

## Run Commands — `swift test` does NOT work here

```bash
export IOS_SIM_ID=71E156C3-0CC1-4659-86AA-B044DE8CDBEB   # REQUIRED — see below

scripts/test.sh                          # all tests in StellarVolumiOTests
scripts/test.sh LcdStoreTests            # one suite, via -only-testing:
scripts/test.sh PlayerStateParserTests

# Equivalent raw invocation scripts/test.sh wraps:
xcodebuild test -scheme StellarVolumiO -destination "id=$IOS_SIM_ID" -quiet
xcodebuild test -scheme StellarVolumiO -destination "id=$IOS_SIM_ID" \
  -only-testing:"StellarVolumiOTests/PlayerStoreOptimisticTests" -quiet

# The destructive, real-backend UI sweep — NOT part of the default run:
xcodebuild test -scheme StellarVolumiOUITests -destination "id=<ipad-sim-udid>"
# Full sweep including the queue-destroying test:
TEST_RUNNER_STELLAR_SWEEP_DESTRUCTIVE=1 xcodebuild test -scheme StellarVolumiOUITests \
  -destination "id=<ipad-sim-udid>"
```

### Gotchas

- **`swift test` (SwiftPM's own test runner) does not work in this repo.** The app mixes
  `@Observable` state with UIKit-backed SwiftUI hosting (`NavigationSplitView`/`TabView`
  build real `UIViewController`s), which requires a full iOS simulator runtime — SwiftPM's
  host-machine test runner cannot provide that environment. Tests must run through
  `xcodebuild test` against a simulator, i.e. via `scripts/test.sh` or `scripts/deploy-to-device.sh`'s
  sibling tooling.
- **Two "iPhone 16 Pro" simulators exist on this Mac**, so `-destination "name=iPhone 16 Pro"`
  (the fallback `scripts/test.sh` and `scripts/build.sh` use when `IOS_SIM_ID` is unset) is
  ambiguous and can pick the wrong one, or fail. **Always `export IOS_SIM_ID=<udid>`** before
  running tests or builds on this machine.
- **`scripts/test.sh` passes `-quiet` to `xcodebuild`.** This suppresses per-test pass/fail output
  — you get a final PASS/FAIL for the whole invocation (or the first failure's summary) but not a
  running count of how many tests ran or which ones. To see individual test results, drop `-quiet`
  and run the raw `xcodebuild test` command yourself, or open the result bundle
  (`-resultBundlePath`) and inspect it, or grep the (very verbose) non-quiet output for
  `Test Case '-[...]' passed/failed`.
- **After adding any new `.swift` file (test or production) you must run
  `xcodegen generate --spec project.yml`** before `scripts/test.sh` will see it — otherwise the
  build fails with "cannot find X in scope" even though the file is on disk and matches
  `project.yml`'s glob (`StellarVolumiO` target only excludes `**/*.md`; the test target's file
  list is similarly generated, not hand-maintained).
- **`StellarVolumiOUITests` (`ParitySweepTests`) talks to the real Pi backend and changes its
  playback state.** It is deliberately kept out of the `StellarVolumiO` scheme so
  `scripts/test.sh` stays hermetic. It also `XCTSkipUnless`-guards on `UIDevice.current
  .userInterfaceIdiom == .pad` (an iPhone simulator's `app.buttons["LCD"]` would match a tab item
  instead of the sidebar button and silently toggle the physical LCD panel while asserting nothing
  useful), and its one queue-destroying test (`test05AlbumPickerDrillsDownAndPlays`) only runs
  under `TEST_RUNNER_STELLAR_SWEEP_DESTRUCTIVE=1` (note the `TEST_RUNNER_` prefix — `xcodebuild`
  only forwards env vars with that prefix into the UI test runner process, stripping it back off
  on read).

## Test File Organization

**Location:** All unit/render tests live flat in `StellarVolumiOTests/` (no per-layer
subdirectories except `Fixtures/` and `Support/`) — one file per store/service/concern, not
co-located with the source file it tests.

**Naming:** `<Subject><Concern>Tests.swift`, e.g. `PlayerStoreOptimisticTests.swift`,
`PlayerStoreSeekTests.swift` (two files split by concern within the same store),
`AirplayLayoutRenderTests.swift`, `SocketEmitArgumentShapeTests.swift`,
`SocketDecodeErrorSurfaceTests.swift`, `SocketHandlerSurvivalTests.swift`. A bare `SmokeTest.swift`
exists purely to assert the test target is wired (`1 + 1 == 2`) — useful as a canary if the whole
suite reports zero tests run.

**Structure:**
```
StellarVolumiOTests/
├── Fixtures/
│   └── Fixtures.swift          # shared raw wire-shape dictionaries (see below)
├── Support/
│   └── LayoutHosting.swift     # shared render-test harness (see below)
├── SmokeTest.swift
├── <Store>Tests.swift          # one or more per store
├── <Store>LayoutRenderTests.swift   # geometry/render tests for that store's views
├── Socket*Tests.swift          # SocketService-level contract tests
└── ...
StellarVolumiOUITests/
└── ParitySweepTests.swift      # single XCUIApplication end-to-end suite
```

## Existing Test Files (as of 2026-09-09)

| File | What it covers |
|---|---|
| `AirplayLayoutRenderTests.swift` | AirPlay-mode view geometry |
| `AirplayRenderSmokeTests.swift` | AirPlay view smoke/compose checks |
| `AirplayStateTests.swift` | `AirplayState` model parsing |
| `AirplayStoreTests.swift` | `AirplayStore` state/tick/command-emit behavior |
| `AlbumArtworkSquareTests.swift` | `AlbumArtworkSquare` component |
| `AlbumLibraryFingerprintTests.swift` | Library album identity/diffing |
| `AlbumTracksLayoutRenderTests.swift` | Album tracks screen geometry |
| `AlbumTracksStoreTests.swift` | `AlbumTracksStore` |
| `AlbumTracksViewGroupingTests.swift` | Track grouping/disc logic |
| `BackendConfigStoreTests.swift` | `BackendConfigStore` (custom/discovered/default resolution) |
| `BackendDiscoveryServiceTests.swift` | Bonjour discovery service |
| `ConnectionGraceTests.swift` | `SocketService` 5s disconnect-grace window |
| `IngestStoreTests.swift` | `IngestStore` phase machine (preview/commit/busy) |
| `LastPlayedAlbumTests.swift` | `LastPlayedAlbum` model |
| `LastPlayedStoreTests.swift` | `LastPlayedStore` |
| `LcdStoreTests.swift` | `LcdStore` (wake/standby) |
| `LcdViewStoreTests.swift` | `LcdViewStore` (kiosk screen sync) |
| `LibraryAutoRefreshTests.swift` | Library auto-refresh triggers |
| `LibraryEnvelopeParserTests.swift` | Tolerant parsing of `pushLibrary*` envelope shapes |
| `LibraryIdentityTests.swift` | `UniqueIdentity`/list identity logic |
| `NowPlayingDisplayStateTests.swift` | Now Playing derived display state |
| `PlayerStateParserTests.swift` | `PlayerState.init(rawDict:)` tolerant parsing |
| `PlayerStoreOptimisticTests.swift` | Optimistic play/pause + server reconciliation |
| `PlayerStoreSeekTests.swift` | Seek anchor/tick interpolation |
| `RootLayoutModeTests.swift` | Phone vs iPad shell selection logic |
| `RootLayoutRenderTests.swift` | Root shell geometry across canvas sizes (see below) |
| `RootNavigationShellTests.swift` | Navigation/selection persistence across shells |
| `SheetLayoutRenderTests.swift` | Sheet presentation geometry |
| `SmokeTest.swift` | Target-wiring canary |
| `SocketDecodeErrorSurfaceTests.swift` | `lastDecodeError` surfacing |
| `SocketEmitArgumentShapeTests.swift` | Wire-shape regression (the `seek` `[[150]]` bug class) |
| `SocketHandlerSurvivalTests.swift` | Subscriptions survive an endpoint/socket rebuild |
| `TapDebouncerTests.swift` | `TapDebouncer` utility |

## Test Structure

Flat `XCTestCase` subclasses, `@MainActor`-annotated whenever the subject is `@Observable`
(essentially always). No `setUp`/`tearDown` boilerplate in most files — state is built fresh,
inline, per test method:

```swift
@MainActor
final class PlayerStoreOptimisticTests: XCTestCase {

    func testOptimisticPlayMakesIsPlayingTrue() {
        let store = PlayerStore()
        store.state = PlayerState.empty
        XCTAssertFalse(store.isPlaying)
        store.applyOptimistic(.play)
        XCTAssertTrue(store.isPlaying)
    }
}
```

Not table-driven in the Go sense (no `[(input, expected)]` loops feeding a shared assertion body)
— each behavior gets its own explicitly named test method with a doc comment above it explaining
the regression or contract it pins. Prefer this shape for new tests: one method per scenario, a
`///` comment stating *why* the case matters (often referencing the bug/PR/date it came from), not
a parametrized loop.

**Assertion messages are mandatory and explanatory** — nearly every `XCTAssert*` call carries a
trailing string argument stating the invariant in prose ("server state must clear optimistic",
"tick projects from the anchor, not the last value"). Match this when adding assertions.

## The critical gotcha: named `SocketService` local variable

**Stores hold their bound `SocketService` weakly.** `bind(to: SocketService())` passes a temporary
that is deallocated the instant the call returns — the weak reference goes nil, and every command
the store subsequently emits silently no-ops (no crash, no test failure signal, just nothing
happening on the wire). Every test that exercises a store's emit/bind behavior must bind to a
**named local variable** that outlives the store's calls:

```swift
// WRONG — socket deallocates immediately, actions silently no-op:
store.bind(to: SocketService())

// RIGHT:
let socket = SocketService()
store.bind(to: socket)
store.play()
XCTAssertEqual(socket.lastEmittedObjectEvent, "airplay:command")
```

This is documented inline at the point of use, e.g. `IngestStoreTests.swift:56-58`:
> "Named local, not a temporary: the store holds the socket weakly, so a `bind(to: SocketService())`
> would be deallocated before the tap and every action would silently no-op."

and `LcdViewStoreTests.swift:11`. **Grep `SocketService()` in any new store test file and confirm
every instantiation is assigned to a named `let`/`var` before `bind(to:)`.**

## Mocking

**No mocking framework** (no Mockingbird/Cuckoo/etc.). Two mechanisms substitute for mocks:

1. **`SocketService` itself is the test double** — it's real, lightweight, and constructible with
   no config (`SocketService()` defaults `config: BackendConfigStore = BackendConfigStore()`), so
   tests use the real type rather than a protocol-backed mock. Its `#if DEBUG` test hooks (bottom
   of `SocketService.swift`) exist purely to make it observable/controllable in tests without a
   live connection:
   - `socket.simulateDecodeFailure(event:reason:)` / `.simulateDecodeSuccess()` — set
     `lastDecodeError` synchronously.
   - `socket.resetEmittedObjectCapture()` / `.lastEmittedObjectEvent` / `.lastEmittedObjectPayload`
     — capture the last `emitObject(_:_:)` call.
   - `socket.resetEmittedCapture()` / `.lastEmittedEvent` / `.lastEmittedData` /
     `.lastEmittedFirstArgument` — capture the last `emit(_:data:)` call, including argument
     **shape** (array-wrapping bugs are the whole reason this exists — see
     `SocketEmitArgumentShapeTests.swift`).
   - No real network I/O happens in unit tests — `emit`/`on` calls build a `SocketManager` but
     nothing actually connects unless `.connect()` is called, which unit tests don't do.

2. **Raw dictionary fixtures stand in for wire payloads.** `StellarVolumiOTests/Fixtures/Fixtures.swift`
   is a flat `enum Fixtures` of `static let` `[String: Any]` literals modeling exact backend JSON
   shapes — canonical, "loose" (stringified/null fields), minimal, and real-backend-captured
   variants (see `pushLibraryAlbumsRealBackend`, dated "captured 2026-05-24 via socket.io probe").
   Parser tests feed these directly into `Model.init?(rawDict:)` rather than mocking the socket
   layer at all:
   ```swift
   let state = PlayerState(rawDict: Fixtures.pushStateLoose)
   ```
   When a new wire shape needs coverage, add a fixture here rather than inlining a dictionary
   literal in the test file, and prefer capturing a real backend payload when the exact shape
   matters (note the dated comment convention for real-backend captures).

## Fixtures and Factories

- **`Fixtures.swift`** (above) — canonical source for `[String: Any]` wire shapes.
- **Private per-file factory helpers** are common for building a valid-by-default model, e.g.
  `IngestStoreTests.armedPreview(token:)` builds an `IngestReport` with one importable folder and
  a valid token, parameterized only on what that specific test needs to vary.
- **`.empty` static instances on models** (`PlayerState.empty`, `AirplayState.empty`) are the
  default starting point for most tests — construct `.empty`, then mutate the one or two fields
  the test cares about via `var s = X.empty; s.field = ...`.

## Coverage

No coverage tooling/threshold configured for this target (`xccov`/`-enableCodeCoverage` not wired
into `scripts/test.sh`). No `make coverage`-equivalent exists here (compare to the Go backend,
which has one). Treat the 33 files enumerated above as the coverage baseline; there is no
automated gate enforcing it grows.

## Test Types

### Unit tests (the bulk of `StellarVolumiOTests`)
Store/model/service logic tested directly, no hosting, no simulator UI interaction beyond what
`xcodebuild test` requires to run at all. This is where new store/model logic should be tested —
fast, hermetic, no backend needed (`Fixtures` + a named `SocketService` cover everything).

### Render/geometry tests (`*LayoutRenderTests.swift`, `RootLayoutRenderTests.swift`,
`SheetLayoutRenderTests.swift`) — **this is how UI/layout behavior gets unit-tested without a UI
test target**

These are real `UIHostingController`s, hosted in a real `UIWindow`, at concrete point sizes, with
the horizontal size class and device idiom force-injected — see
`StellarVolumiOTests/Support/LayoutHosting.swift`. This is the load-bearing pattern for the iPad
port and should be the template for any new layout-planning work:

- `LayoutHosting.host(_:size:sizeClass:)` builds a `UIHostingController` inside a container
  `UIViewController`, puts it in a real `UIWindow` (required — `NavigationSplitView`/`TabView`
  only build their UIKit backing inside a window), and optionally overrides the trait collection
  to force a horizontal size class independent of whichever simulator happens to be running.
- **`\.stellarIdiom` environment key** (`StellarVolumiO/Utils/InterfaceIdiom.swift`) lets a test
  force the `.pad` branch of layout logic even when running on an iPhone simulator — production
  code never sets this, only tests do. `RootLayoutMode` reads it to decide sidebar vs. tab shell.
  **This is the mechanism: any layout decision gated on device idiom must read `\.stellarIdiom`
  (or an equivalent injected value), or it becomes untestable off-hardware.**
- `LayoutHosting.assertNothingStrandedHorizontally(in:tolerance:)` walks the real rendered UIKit
  view hierarchy and asserts no leaf subview's frame extends past the horizontal bounds of the
  pane that owns it (each `NavigationSplitView` column measured against its own bounds, not the
  window — because of `UISplitViewController`'s automatic display mode parking off-screen columns
  in portrait). This is a real geometry assertion, not a tautological "frame equals what I set."
- `StellarTestEnvironment` (also in `LayoutHosting.swift`) builds one instance of every store +
  `SocketService` + `BackendConfigStore` + `BackendDiscoveryService` and injects them via
  `.environment(...)` exactly as `StellarApp` does in production, then exposes `.inject(into:idiom:)`.
  **`socket` must come back out with the returned tuple and be kept alive by the caller** (see
  `RootLayoutRenderTests.render(...)` returning `(host, env)` and callers doing
  `withExtendedLifetime(rendered.env) {}`) — same weak-reference gotcha as store tests, just at the
  view layer.
- `RootLayoutRenderTests` is the canonical example: it renders `ContentView` at named canvas sizes
  from `320×1024` (iPad Slide Over, the narrowest canvas the app can be handed once
  `UIRequiresFullScreen` was dropped) up to `1366×1024` (iPad Pro 13" landscape), asserting nothing
  strands, and separately re-lays-out **the same host instance** through a size sequence
  (`testPadShellSurvivesLiveResizeSequence`) to catch state that survives a rebuild but not a live
  resize (rotation, Split View divider drag, Stage Manager).

**What this means for a TDD iPad-port plan:** any new layout/shell/navigation behavior should be
driven through this harness — construct the real view tree via `StellarTestEnvironment`, host it
at the target canvas size(s) with `LayoutHosting.host`, force the idiom via `\.stellarIdiom`, and
assert either geometry (`assertNothingStrandedHorizontally`) or structural facts reachable from
`UIViewController`/`UIView` (`LayoutHosting.contains(_:in:)` for "does a `UITabBarController`/
`UISplitViewController` exist in this tree", `LayoutHosting.firstSubview(in:classNameContains:)`
for finding SwiftUI-private backing views by class-name substring). This is genuinely unit-testable
— no simulator UI interaction (`XCUIApplication`) required — because it renders and inspects the
real UIKit tree in-process.

### UI/E2E tests (`StellarVolumiOUITests/ParitySweepTests.swift`) — the one UI test target

A UI test target **does exist**, but it is scoped narrowly and deliberately excluded from the
default `scripts/test.sh` run:

- Drives a real `XCUIApplication` against a **real, reachable Pi backend** — it changes playback
  state on actual hardware.
- Gated to iPad only via `XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, ...)`.
- Numbered test methods (`test01...test08`) because XCTest runs alphabetically and the suite
  wants cheap/non-destructive checks to fail first.
- `continueAfterFailure = false` plus `addTeardownBlock { ... }` for every state-mutating action —
  restoring state in `tearDown`/teardown blocks rather than at the end of the test body, because a
  failed assertion mid-test aborts the method and an inline "restore" at the bottom would never run.
- Helper methods worth reusing as a template for new UI tests: `launch()` (waits for foreground +
  first render), `tap(_:_:file:line:)` (waits for existence, asserts hittable, then taps — a bare
  `.tap()` on an unresolved element raises an unhelpful raw XCUI error instead of this suite's
  explicit failure message).
- Use this target only for true end-to-end parity/regression sweeps against real hardware, not for
  layout/geometry testing — that's what the render-test harness above is for, and it's far
  cheaper and does not require a reachable backend.

## Common Patterns

**Async/timer testing (no real sleeping):** Interpolation logic (`PlayerStore.tick`,
`AirplayStore.tick`) is tested by advancing a virtual clock, not by sleeping the test:
```swift
let anchor = store.seekAnchor!
store.tick(now: anchor.advanced(by: .seconds(1)))
XCTAssertEqual(store.state.seek, 6_000, "tick must track one second of elapsed time")
```
`tick(now:)` takes an injectable `ContinuousClock.Instant` (defaulting to `.now` in production)
specifically so tests can pass any instant without `Task.sleep`.

**Optimistic-then-reconciled state testing:** set optimistic state, assert the optimistic view,
then call `receiveServerState(_:)` and assert both the new state and that `optimisticStatus`/
equivalent was cleared — see `PlayerStoreOptimisticTests.testServerStateClearsOptimistic`.

**"No socket bound yet" defensive no-op testing:** call store command methods without ever calling
`bind(to:)` and assert no crash occurs (the weak `socket` reference is nil) — see
`AirplayStoreTests.testCommandsWithNoSocketBoundAreNoOp` and its cross-reference to
`LcdStoreTests.testSetOnWithNoSocketBoundIsNoOp`.

**Stale/out-of-order event guards:** tests explicitly cover events arriving in the "wrong" order
(a stale `pushAirplayEnded` for an old session arriving after a new session already started) to
pin defensive session-ID matching — see `AirplayStoreTests.testReceiveEndedIgnoresMismatchedSessionID`.

---

*Testing analysis: 2026-09-09*
