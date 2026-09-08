# Phase 5 — response to REVIEW.md

**Reviewed:** 2026-09-08 (`gsd-code-reviewer`, deep, 30 findings: 5 critical, 19 warning, 6 info)
**Responded:** 2026-09-09
**Branch:** `feature/ipad-port`

Verification for everything below: **233 unit tests green on all three simulators**
(iPhone 16 Pro / iOS 18.3, iPad Pro 11" and iPad mini / iOS 26.3), and the parity
sweep green on the iPad Pro 11" against the live Pi — 7 passing plus `test05`
skipped by its new opt-in, then `test05` run once deliberately with the queue
captured and restored (`Mark Knopfler — Tracker (Deluxe)`, 15 tracks, #5, 4:09,
paused — the exact state it started in).

Summary: **28 fixed, 1 rejected (CR-04), 1 deferred with evidence (WR-05 part 2).**
Two findings were answered by measurement rather than by a change (CR-04, WR-08);
both measurements are now pinned by a test so the question cannot reopen silently.

---

## Critical

### CR-01 — glassy background changed the iPhone (REG-01) — **fixed**

Real, and the reviewer's arithmetic is right: `min(w,h) * 0.71` equals 280 only at
exactly 393 pt. An iPhone SE (375) got 266.25 and a 16 Pro Max (440) got 312.4,
both against the shipping iOS 17 deployment target.

`StellarGlassyBackground` now branches: compact keeps the flat 280 pt radius it
shipped with, and only a roomy canvas derives the radius from the geometry.
`StellarVolumiO/Utils/DesignTokens+Redesign.swift`.

### CR-02 / CR-03 — retained sections never re-fire `onAppear` — **fixed**

Also real, and worse than a cosmetic gap: `SettingsView.onAppear` calls its own
refresh "Load-bearing" in the source, and `IngestStore.isAvailable` — which gates
whether the ingest section renders at all — has exactly one setter,
`requestStatus()`. A missed re-fire makes PARITY-08 invisible for the whole
session with no recovery path.

`ContentView` now drives the three lifecycle effects explicitly through
`sectionBecameVisible(_:)` — `requestAirplayState()` for the player,
`lcd.refresh()` + `ingest.requestStatus()` for settings, the load-if-empty guards
for the library — rather than relying on a re-insert that a retained view never
gets. `TabView`'s third property is now reproduced, not just its first two.

### CR-04 — "three sweep cases query an identifier the app overrides" — **rejected**

The finding claims `app.buttons["pause.fill"]` cannot resolve because
`PlayPauseButton.swift:24` sets `.accessibilityLabel(isPlaying ? "Pause" : "Play")`,
and concludes that "the suite therefore cannot have been run green".

Two pieces of hard evidence contradict it:

1. **`XCUIElementQuery`'s subscript matches `identifier` first, then `label`.** A
   SwiftUI `Button` labelled with `Image(systemName:)` gets an accessibility
   *identifier* equal to the symbol name, which `.accessibilityLabel` does not
   replace. The hierarchy dump from the live app reads:
   `Button, 0x104821880, identifier: 'pause.fill', label: 'Pause'`.
2. **The suite has been run green — repeatedly, on two different simulators**
   (iPad Pro 11" and iPad mini), including the play/pause round trip in `test07`
   whose assertions the finding says "never run".

No change made to `PlayPauseButton`. The mechanism is now written down in
`ParitySweepTests.isPlaying(_:)` so the next reader does not re-derive it.
IN-04 falls with it.

### CR-05 — destructive sweep, no guard, restores in the wrong place — **fixed**

All three limbs, plus the `TEST_RUNNER_` detail the fix needs to actually work:

- **iPad guard.** `setUpWithError` now `XCTSkipUnless`es a non-iPad idiom. This
  mattered more than it looks: on an iPhone simulator `app.buttons["LCD"]`
  matches the LCD *tab item*, so the old suite would have toggled the physical
  panel while asserting nothing about the port. Verified: on the iPhone sim all
  8 skip and the Pi is untouched.
- **Restores moved into `addTeardownBlock`.** With `continueAfterFailure = false`
  a mid-test failure aborts the method, so any restore on the last line never
  ran — the LCD would have been left off, on real hardware, silently. The two
  sidebar switches, the manual-entry disclosure and the whole transport state
  (track, then position, then play/pause, in that order because a track change
  resets the position) now restore in teardown.
- **`test05` is opt-in.** It replaces the MPD queue and cannot put it back, so it
  runs only under `TEST_RUNNER_STELLAR_SWEEP_DESTRUCTIVE=1`. Note the prefix:
  `xcodebuild` forwards only `TEST_RUNNER_`-prefixed variables to the UI-test
  runner (stripping the prefix) — the unprefixed form silently skips, which is
  how this was found.

---

## Warnings

| # | Verdict | What changed |
|---|---|---|
| WR-01 | fixed | Every layout step now routes through `RootLayoutMode.isRoomy(horizontalSizeClass:idiom:)`, so the `idiom == .pad` guard covers layout, not just navigation. Truth-table test asserts `isRoomy` agrees with `resolve` on all 21 input combinations, plus the specific "regular-width iPhone is not roomy" case. |
| WR-02 | fixed | `sidebarSelection`'s `nil` branch bumps `sidebarNonce`, which `.id()`s the `List` and forces it to re-read the getter. Highlight and detail column can no longer disagree. |
| WR-03 | fixed | New `visibleSection` maps `.lcd` / `.vu` onto `.player`, so the detail column is total over `Tab` — there is no input that renders an empty column. |
| WR-04 | fixed | `mountedSections.insert` moved into the binding setter, so the set and the tab move in one transaction. No empty first frame. |
| WR-05 (1) | fixed | `mountedSections` resets to `[visibleSection]` on a `layoutMode` change, so a Slide Over round trip no longer remounts all three sections at once. |
| WR-05 (2) | **deferred** | See below. |
| WR-06 | fixed | Sidebar LCD / VU buttons gained `.accessibilityValue` and `.accessibilityHint`, matching what `SettingsView`'s own LCD row already does. |
| WR-07 | fixed | The banner is now per-shell: inside `detailColumn` on iPad (so it cannot cover the sidebar's title and first rows during the failure that makes the user want Settings), full-width on the phone. Capped at `contentMaxWidth` like every other Phase 4 surface. |
| WR-08 | **measured, not changed** | See below. |
| WR-09 | fixed | Replaced with a rendered-geometry test at a 280 pt regular-width detail column — the narrow Stage Manager case where regular width does *not* mean a wide column. Falsifiability verified: reverting the hero to `.frame(width:height:)` turns it red (`_UIGraphicsView runs 44.0pt past its pane`), restoring `.aspectRatio(1, .fit) + .frame(maxWidth:maxHeight:)` turns it green. |
| WR-10 | fixed | All four render-test files now assert through `LayoutHosting.assertNothingStrandedHorizontally`, which walks the rendered UIKit hierarchy. The tautologies (`XCTAssertEqual(host.view.frame.width, theWidthWeJustAssigned)`) are gone. |
| WR-11 | fixed | New `\.stellarIdiom` environment key. Tests inject `.pad`, so the sidebar branch executes in the default iPhone-simulator run instead of zero times. `RootNavigationShellTests` now asserts both branches on every simulator. |
| WR-12 | fixed | The vacuous assertion is replaced by a real one, and the latent adapter defect is pinned rather than papered over — see below. |
| WR-13 | fixed | Index lookups replaced with accessibility identifiers: `album-grid`, `artist-list`, `artist-album-grid`, `album-tracks-title`, `now-playing-title`, `now-playing-album`, `elapsed-time`, `total-time`. |
| WR-14 | fixed | The `label != "Sidebar"` predicate (the sidebar's label is empty, so it excluded nothing) is gone — `app.collectionViews["artist-list"]` is unambiguous. |
| WR-15 | fixed | Every tap goes through one `tap(_:_:)` helper that waits, asserts hittable, then taps. `isHittable` does not wait on its own, which made the old transport checks a launch-timing flake. |
| WR-16 | fixed | The album title is read from `album-tracks-title` instead of parsed out of the tile's `"<title>, <artist>"` label, so a comma in the title no longer truncates it. (The nav bar truncates too — the probe run showed `'...Like Clockwork'` — which is a second reason not to read it from chrome.) |
| WR-17 | fixed | `StellarTestEnvironment` holds the `SocketService` as a stored property for the whole test, so the weak-reference trap cannot bite. |
| WR-18 | fixed | `SheetLayoutRenderTests` uses the same environment graph as everything else; the unbound socket is gone. |
| WR-19 | fixed | `NowPlayingView` builds two trees. The phone gets the exact tree it shipped with — no `GeometryReader`, no `minHeight` container. |

### WR-05 (2) — sub-state does not survive a shell swap — deferred, documented

Correct as stated: `switch layoutMode` compiles to `_ConditionalContent`, so
swapping branches destroys `LibraryView`'s `segment`, its navigation path, and any
album drill-down. `selectedTab` survives; what the user was doing *inside* a
section does not.

Not fixed here because the fix is architectural — hoisting Library's segment and
navigation path into `ContentView` state or an `@Observable` store — and it
changes iPhone behaviour (the phone's `TabView` does not currently preserve them
across anything either, so the change would be a behaviour change, not a
regression fix). It is also not reachable on the phone at all: the iPhone never
swaps shells.

**Scope of NAV-07 as actually delivered: the section survives a shell swap; the
state within a section does not.** Carried to Phase 6 as a candidate for the
post-merge follow-up list.

### WR-08 — nested `NavigationStack` in the detail column — measured, no defect

The finding predicts "two stacked navigation bars on the Album Tracks screen and
`navigationTitle`/toolbar modifiers landing on the inner bar". Probed on the iPad
Pro 11" against the live app, two pushes deep (Artists → artist → album):

```
NAVBARS count=2
NAVBAR[0] id='...Like Clockwork'  frame=(0.0, 32.0, 834.0, 54.0)   ← detail
NAVBAR[1] id='Stellar'            frame=(10.0, 32.0, 320.0, 54.0)  ← sidebar
```

One bar per column, and `.navigationTitle` lands on the detail bar as intended.
The nesting Apple documents as unsupported is not producing the symptom on iOS
26.3. Rather than restructure navigation on the strength of a prediction that
does not reproduce, `test06` now asserts `app.navigationBars.count == 2` with the
identifiers in the failure message — so if a future SwiftUI release does start
stacking them, that fails instead of shipping.

### WR-12 — the AirPlay adapter's latent false positive

Fixed the vacuous assertion. The underlying defect the reviewer spotted is real
and is now pinned by a named test rather than patched:
`NowPlayingDisplayState.from(airplay:)` maps `airplaySender: s.sender`
unconditionally, and `AirplayState.empty.sender` is `""` — not nil — so an empty
session adapts to a state claiming to be the AirPlay branch.

It is latent only: `NowPlayingView` reaches the adapter exclusively when
`airplay.state.isActive`. Mapping `""` to nil would be correct but is an iPhone
behaviour change, out of scope for a port whose first requirement is that the
phone is untouched. `testEmptySessionAdaptsToAFalsePositiveAirplayFlag_knownLatentDefect`
asserts the current behaviour and explains why, so the next reader finds it
deliberate instead of rediscovering it.

---

## Info

| # | Verdict | What changed |
|---|---|---|
| IN-01 | fixed | `Stellar.Metric.heroSideCompact` (240) added; the bare literal is gone from both the view and the test. |
| IN-02 | fixed | `StellarVolumiOTests/Support/LayoutHosting.swift` — one `host(_:size:sizeClass:)`, one `StellarTestEnvironment`, one geometry assertion, used by all four render-test files. |
| IN-03 | fixed | `columnVisibility` is now read: it reasserts `.all` when `layoutMode` returns to `.sidebar`, so a Slide Over round trip cannot leave the app with a detail column and no way out of it. |
| IN-04 | n/a | Falls with CR-04. |
| IN-05 | fixed | `sidebarRow(_:icon:)` pins the same 44 pt minimum on the three tagged rows that the two Display buttons already pinned. |
| IN-06 | out of scope | Pre-existing sub-44 pt targets in the failure banner, not in this diff. Agreed and left alone; carried to the post-merge list. |

---

## New test infrastructure

- **`StellarVolumiO/Utils/InterfaceIdiom.swift`** — `\.stellarIdiom`. Production
  never sets it; tests always do. Without it the whole iPad branch is unreachable
  from `scripts/test.sh`, which runs an iPhone simulator.
- **`RootLayoutMode.isRoomy(horizontalSizeClass:idiom:)`** — the single question
  every layout step asks.
- **`StellarVolumiOTests/Support/LayoutHosting.swift`** — trait-overriding host in
  a real window, the environment graph, and
  `assertNothingStrandedHorizontally(in:)`.

One thing that assertion had to learn, worth recording: it measures each view
against **its own pane**, not the window. `NavigationSplitView`'s columns are
`UISplitViewController` children, and in portrait the automatic display mode
parks the sidebar off-canvas (at 834×1194 the sidebar column sits at x = -100,
with every descendant inherited along with it). Measuring against the window
produced ~30 failures per canvas that said nothing about our layout. It also
skips `*DecorationView`s — a compositional list layout paints its section
background deliberately 70 pt proud of the collection view on each side.
