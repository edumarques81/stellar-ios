# State: Stellar Remote — iPad Port

**Updated:** 2026-09-09
**Branch:** `feature/ipad-port`
**Current phase:** Phase 4 — next

## Progress

| Phase | Status |
|---|---|
| 0 — Setup & codebase map | ✅ complete |
| 1 — iPad device family, orientations, multitasking | ✅ complete |
| 2 — Layout-decision type (TDD) | ✅ complete |
| 3 — NavigationSplitView sidebar | ✅ complete |
| 4 — iPad-size layout adaptation | ⬜ next |
| 5 — Parity sweep + full regression + code review | ⬜ |
| 6 — Physical iPad | ⬜ blocked on hardware (expected 2026-09-10) |

## Done so far

- Branch `feature/ipad-port` created and pushed.
- `.planning/codebase/` — seven documents (679 lines), committed.
- `PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `config.json` written.
- Baseline confirmed: 205 tests green, clean build with zero warnings.
- **Phase 1 complete.** `TARGETED_DEVICE_FAMILY: "1,2"`, `UIRequiresFullScreen`
  removed, per-idiom orientations (`UISupportedInterfaceOrientations~ipad` with
  all four; iPhone stays portrait-only). Verified against the *built* Info.plist,
  not just the spec. Added `RootLayoutRenderTests` — hosts the real root view
  with the full environment graph across seven canvases from a 320pt Slide Over
  pane to 13" landscape, plus a live-resize sequence. 207 tests green on all
  three simulators. App installed and launched on the iPad Pro 11" sim against
  the live Pi backend.
- **Phase 2 complete.** `RootLayoutMode` (`Utils/RootLayoutMode.swift`) — a pure
  enum with one `resolve(horizontalSizeClass:idiom:)` function, written
  test-first (the 9 tests were red for "cannot find 'RootLayoutMode' in scope"
  before the type existed). Rules: only an iPad can reach `.sidebar`; a compact
  width means `.tabs` even on an iPad (Slide Over); a `nil` size class defers to
  the idiom rather than flashing a tab bar onto an iPad. The truth table is
  asserted exhaustively over every idiom × size class. Nothing consumes it yet —
  zero view changes, as the phase required. 216 tests green on all three sims.
- **Phase 3 complete.** `ContentView` now branches on `RootLayoutMode`. The
  `TabView` moved into `compactTabs` untouched; `regularSidebar` is the new
  `NavigationSplitView` with Now Playing / Library / Settings as tagged,
  selectable rows and LCD / VU as untagged buttons whose icons track live state.
  Both shells write the same `selectedTab`, so a rotation or Split View resize
  swaps the shell without losing the section (NAV-07). Added
  `RootNavigationShellTests`, which overrides the child trait collection to
  drive both branches from one simulator and asserts on the actual UIKit
  hierarchy (`UISplitViewController` vs `UITabBar`) — including that an iPhone
  at *regular* width still gets the tab bar. 219 tests green on all three sims.
  Verified on the iPad Pro 11" sim against the live Pi: sidebar renders, Now
  Playing plays, Library grid loads real albums.
- **Detail column is lazy-then-retained, deliberately.** Mounting all three
  sections up front fired `AlbumPickerView.onAppear` at launch, before the
  socket connected; `store.load()` went into a dead socket and was never
  retried, leaving the album grid empty for the whole session. Sections are now
  built on first visit and kept alive after — the same lifecycle `TabView` gives
  the iPhone.
- **Pre-existing bug found (not a port regression, not fixed here):** if Library
  is the section on screen at launch, the album grid stays permanently empty on
  *iPhone too* — `AlbumPickerView.onAppear` fires before the socket connects and
  nothing retries the load. Unreachable in normal use because the app launches
  on Now Playing. Confirmed by launching both simulators with `.library` as the
  default section. Worth fixing in `AlbumPickerStore` (retry on connect), out of
  scope for the port.
- **Known verification gap:** System Events has no accessibility access to
  Simulator on this Mac — it cannot read its windows, so neither rotation nor
  taps can be scripted. Landscape is verified via the built Info.plist and the
  render tests; sidebar sections were screenshotted by temporarily changing the
  default section and reverting. Real rotation and touch testing happen on the
  physical iPad in Phase 6.

## Environment

| Role | Device | Runtime | UDID |
|---|---|---|---|
| iPad primary | iPad Pro 11" (M4) | iOS 26.3 | `49C99399-FBED-4478-AD20-3B7F63D653C7` |
| iPad small | iPad mini (A17 Pro) | iOS 26.3 | `D204C330-DE77-4760-919D-8AAD044DA93E` |
| iPhone regression | iPhone 16 Pro | iOS 18.3 | `71E156C3-0CC1-4659-86AA-B044DE8CDBEB` |

Xcode 26.3 (17C529). Backend at `stellar.local:3000`.

## Open questions

- None blocking. Phase 6 needs the physical iPad.

## Notes for the next session

- `gsd-codebase-mapper` subagent spawns returned no output twice; the codebase
  map was written inline via the workflow's documented sequential fallback.
  Expect the same if other GSD phases try to spawn subagents — fall back inline
  rather than retrying indefinitely.
- Unrelated but now unblocked: Xcode 26.3 is installed, clearing the App Store
  submission blocker for ASC app id `6773923668`.
