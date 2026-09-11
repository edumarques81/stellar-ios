# State: Stellar Remote — iPad Port

**Updated:** 2026-09-11
**Branch:** `feature/ipad-port`
**Current phase:** Phase 6 — DEVICE-01 done, DEVICE-02 (manual pass) outstanding

## Progress

| Phase | Status |
|---|---|
| 0 — Setup & codebase map | ✅ complete |
| 1 — iPad device family, orientations, multitasking | ✅ complete |
| 2 — Layout-decision type (TDD) | ✅ complete |
| 3 — NavigationSplitView sidebar | ✅ complete |
| 4 — iPad-size layout adaptation | ✅ complete |
| 5 — Parity sweep + full regression + code review | ✅ complete |
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
- **Phase 4 complete.** Layout now adapts to the canvas instead of sitting at
  phone-fixed sizes. Two new tokens: `Stellar.Metric.contentMaxWidth` (560) caps
  the Now Playing reading column so it does not stretch to a 1194 pt line, and
  `heroSideRegular` (320) steps the `AlbumTracksView` cover up from the phone's
  240 on regular width. `StellarGlassyBackground` derives its radial-gradient
  radius from the canvas (`min(w, h) * 0.71`) rather than a flat 280 pt, chosen
  so a 393 pt iPhone still lands on ~280 — the phone is byte-for-byte unchanged
  (REG-01). Now Playing centres vertically only on regular width; the iPhone
  keeps its top alignment. Added `AlbumTracksLayoutRenderTests` (3) and
  `SheetLayoutRenderTests` (2). **224 tests green on all three sims.** Verified
  visually on the iPad Pro 11" sim against the live Pi and on the iPhone 16 Pro
  sim for regression.
- **Two requirement clauses needed no code — they were mis-mappings from the
  Phase 0 codebase map.** `AirplaySourceBadge`'s `.frame(width: 240)` exists
  only inside its `#Preview`, not in production, so LAYOUT-04's badge clause has
  no production call site to fix; and `StellarLogoView` has no production call
  sites at all. Recorded rather than "fixed" so a later reader does not go
  looking for the change.
- **LAYOUT-03, 06 and 07 were verify-don't-rebuild, and verified as such.** The
  album and artist grids are already `GridItem(.adaptive(minimum: 150, maximum:
  200))`, so they gain columns on a wide detail column with no change.
  `minTouchTarget` (44) is used throughout and a grep for interactive elements
  with a sub-44 explicit frame returns nothing; the only new interactive
  elements in the port are the sidebar LCD/VU buttons, which pin it explicitly.
  Both sheets are a `NavigationStack` over `maxWidth: .infinity` content with no
  hardcoded width, so they fill the iPad form sheet — pinned by
  `SheetLayoutRenderTests` at 540x620 and 704x820 so a width added later fails
  loudly instead of only stranding content on iPad.
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
- **Phase 5 parity sweep — the Simulator *can* be driven after all.** The Phase
  3/4 note below said no tap could be scripted. That was true of System Events,
  which reports zero windows for the Simulator process, and false of XCUITest,
  which drives the app through its own accessibility hierarchy and does not care.
  Added a `StellarVolumiOUITests` target (`bundle.ui-testing`) with
  `ParitySweepTests` — eight tests covering all eight capabilities plus rotation,
  green on the iPad Pro 11" and the iPad mini against the live Pi.
- **The sweep is deliberately NOT in the `StellarVolumiO` scheme.** It launches
  the app and talks to the real backend, so `scripts/test.sh` stays hermetic and
  fast. Run it explicitly:
  `xcodebuild test -scheme StellarVolumiOUITests -destination "id=<ipad-sim>"`.
- **It changes what is playing.** `test05` taps Play Album, which replaces the
  MPD queue; `test07` pauses, skips and seeks. Capture and restore around a run:
  `mpc --format "%file%" playlist` + `mpc status` before, then
  `mpc clear` → re-add → `mpc play <n>` → `mpc seek <mm:ss>` after. Done for both
  runs in this session; the Pi was left exactly where it was found.
- **Two capabilities are only half-verifiable on a simulator, by their nature.**
  AirPlay needs a real sender, so PARITY-06 is covered by
  `AirplayLayoutRenderTests` (the branch composes at every iPad canvas, and the
  suppression contract — no seek, no format strip — is asserted through
  `NowPlayingDisplayState.from(airplay:)`); a live session is DEVICE-02. Split
  View and Stage Manager cannot be driven either, so BUILD-04 keeps its rotation
  half (`ParitySweepTests.test08`, which also proves NAV-07 against a real
  rotation rather than a resize) and defers the rest to DEVICE-02.
- **REG-04 and REG-05 verified by inspection of the branch diff:** nothing under
  `Services/` is touched at all, so the wire contract and
  `SocketEmitArgumentShapeTests` are untouched; `setVolume` and `toggleMute`
  still exist in `SocketService` and still have zero call sites outside it.
- **227 tests green on all three sims**, and the simulator build emits no Swift
  warnings.
- **Phase 5 code review answered — 28 fixed, 1 rejected, 1 deferred.** Report at
  `.planning/phases/phase-5/REVIEW.md` (30 findings), response at
  `.planning/phases/phase-5/REVIEW-RESPONSE.md`. The blockers were all real
  except CR-04: the glassy background really did restyle every iPhone that is
  not exactly 393 pt wide, and retained detail sections really never re-fired
  `onAppear`, which silently disables the ingest section for a whole session.
- **CR-04 rejected on evidence.** It claimed `app.buttons["pause.fill"]` cannot
  resolve because `PlayPauseButton` overrides the accessibility *label*.
  `XCUIElementQuery`'s subscript matches `identifier` first, and the live
  hierarchy dump reads `Button, identifier: 'pause.fill', label: 'Pause'` — the
  sweep had already run green twice on two simulators.
- **WR-08 measured instead of rebuilt.** The predicted double navigation bar from
  nesting `LibraryView`'s `NavigationStack` in the detail column does not happen
  on iOS 26.3: two bars exist in the window, one per column, and
  `.navigationTitle` lands on the detail bar. `test06` now pins
  `app.navigationBars.count == 2` so a future regression fails loudly.
- **Deferred, deliberately (WR-05 part 2).** A shell swap destroys `LibraryView`'s
  segment and navigation path — `switch layoutMode` is a `_ConditionalContent`
  branch. NAV-07 as delivered preserves the *section*, not the state within it.
  The fix is architectural and would change iPhone behaviour, so it is a
  post-merge candidate rather than an in-port change.
- **`\.stellarIdiom` is the reason the iPad branch is tested at all.**
  `scripts/test.sh` runs an iPhone simulator and `RootLayoutMode` refuses a
  sidebar to anything but an iPad, so before this the entire sidebar path
  executed zero times in the default run. Tests inject the idiom; production
  never sets it.
- **The sweep is now iPad-guarded and its destructive test is opt-in.** On an
  iPhone simulator `app.buttons["LCD"]` matches the LCD *tab item* and would
  have toggled the physical panel while asserting nothing — all 8 now skip
  there. `test05` needs `TEST_RUNNER_STELLAR_SWEEP_DESTRUCTIVE=1`; note the
  prefix, `xcodebuild` forwards only `TEST_RUNNER_`-prefixed variables to the
  UI-test runner and strips it. Restores moved into `addTeardownBlock`, because
  `continueAfterFailure = false` means a failure aborts the method and an
  inline restore never runs.
- **233 tests green on all three sims**; parity sweep green on the iPad Pro 11"
  (7 + 1 skipped), and `test05` run once deliberately with the Pi's queue
  captured and restored exactly.
- **Known verification gap (Phases 3-4 only — superseded in Phase 5).** System
  Events reports zero windows for the Simulator process on this Mac, so nothing
  could be tapped *that way*, and Phases 3 and 4 worked around it by
  screenshotting with the default section temporarily changed. The conclusion
  drawn at the time — that the simulator could not be driven at all — was wrong:
  XCUITest drives the app through its own accessibility hierarchy and never
  touches the window server. See the Phase 5 notes above. Split View and Stage
  Manager remain undriveable and are still Phase 6.

## Environment

| Role | Device | Runtime | UDID |
|---|---|---|---|
| iPad primary | iPad Pro 11" (M4) | iOS 26.3 | `49C99399-FBED-4478-AD20-3B7F63D653C7` |
| iPad small | iPad mini (A17 Pro) | iOS 26.3 | `D204C330-DE77-4760-919D-8AAD044DA93E` |
| iPhone regression | iPhone 16 Pro | iOS 18.3 | `71E156C3-0CC1-4659-86AA-B044DE8CDBEB` |

Xcode 26.3 (17C529). Backend at `stellar.local:3000`.

## Open questions

- None blocking. DEVICE-01 cleared on 2026-09-11; DEVICE-02 is a manual pass on
  the iPad and is the only thing left before the merge.
- Note for DEVICE-02: the paired iPad is an **iPad12,1 (9th gen)**. It supports
  Split View and Slide Over but **not Stage Manager**, which needs an M1. The
  Stage Manager half of BUILD-04 cannot be covered on this hardware.

## Post-merge follow-up list (not port scope)

- WR-05(2): hoist `LibraryView`'s segment + navigation path so sub-state survives
  a shell swap.
- WR-12: `NowPlayingDisplayState.from(airplay:)` maps an empty sender to `""`
  rather than nil, so `from(airplay: .empty).isAirplay` is true. Latent — the
  caller gates on `isActive`. Pinned by a named test.
- IN-06: `Retry` and `Server Settings` in the connection-failure banner are
  28.6 pt tall, below the project's 44 pt convention. Predates this branch.
- `AlbumPickerStore` should retry `load()` on socket connect — the pre-existing
  empty-library-at-launch bug, reproducible on iPhone too.

## Notes for the next session

- `gsd-codebase-mapper` subagent spawns returned no output twice; the codebase
  map was written inline via the workflow's documented sequential fallback.
  Expect the same if other GSD phases try to spawn subagents — fall back inline
  rather than retrying indefinitely.
- Unrelated but now unblocked: Xcode 26.3 is installed, clearing the App Store
  submission blocker for ASC app id `6773923668`.
