---
phase: phase-5
reviewed: 2026-09-08T21:23:19Z
depth: deep
files_reviewed: 12
files_reviewed_list:
  - StellarVolumiO/App/ContentView.swift
  - StellarVolumiO/Utils/RootLayoutMode.swift
  - StellarVolumiO/Utils/DesignTokens+Redesign.swift
  - StellarVolumiO/Views/NowPlaying/NowPlayingView.swift
  - StellarVolumiO/Views/Library/AlbumTracksView.swift
  - project.yml
  - StellarVolumiOTests/RootLayoutModeTests.swift
  - StellarVolumiOTests/RootLayoutRenderTests.swift
  - StellarVolumiOTests/RootNavigationShellTests.swift
  - StellarVolumiOTests/AlbumTracksLayoutRenderTests.swift
  - StellarVolumiOTests/SheetLayoutRenderTests.swift
  - StellarVolumiOTests/AirplayLayoutRenderTests.swift
  - StellarVolumiOUITests/ParitySweepTests.swift
findings:
  critical: 5
  warning: 19
  info: 6
  total: 30
status: issues_found
---

# Phase 5: Code Review Report — `feature/ipad-port`

**Reviewed:** 2026-09-08T21:23:19Z
**Depth:** deep (`git diff main...HEAD`, source + tests; `.planning/` excluded per scope)
**Files Reviewed:** 12 source/test files + `project.yml`
**Status:** issues_found

## Summary

The navigation decision (`RootLayoutMode`) is the strongest part of the branch: it is genuinely
pure, genuinely total, and `RootLayoutModeTests` is the one new test file that tests something.
Almost everything downstream of it is weaker than it presents itself as.

Three findings dominate. First, **REG-01 is violated** — not by the navigation branch, which is
correctly guarded, but by `StellarGlassyBackground`, whose new canvas-derived radius changes the
rendering on every iPhone that is not 393 pt wide (the SE and mini shrink it, the Plus/Pro Max
grow it ~11%), on all six screens that use it. The code comment asserts the opposite.

Second, the `mountedSections` "lazy-then-retained" design is built on a **wrong premise**. Its doc
comment says it matches `TabView`, which is "lazy and retained". `TabView` is lazy, retained,
*and* re-fires `onAppear`/`onDisappear` on every selection change. The port copied two of the
three, so on iPad three documented, load-bearing refresh hooks now fire exactly once per app
launch: `SettingsView`'s `lcd.refresh()` + `ingest.requestStatus()` (the second of which gates
whether the ingest section renders *at all*), and `NowPlayingView`'s `socket.requestAirplayState()`.
The Library's own empty-grid retry — the failure the `detailColumn` comment says lazy mounting
avoids — is not avoided either; retention just moves the one-shot window.

Third, `ParitySweepTests` **cannot have been run green**. Three of its eight tests assert on
`app.buttons["pause.fill"]` / `["play.fill"]`, and `PlayPauseButton.swift:24` overrides that
button's accessibility label to `"Pause"`/`"Play"`. Those queries cannot match. That matters
beyond the tests, because the Phase 5 commit's claim is "drive all eight capabilities on iPad" and
the suite is the only evidence offered. The same file mutates live production appliance state
(replaces the MPD queue, toggles a physical LCD panel, pauses/skips/seeks) with a committed scheme,
no guard, and restore logic placed in the test body rather than a teardown block — so any failure
leaves the Pi mutated.

Underneath that, the new render-test files are largely tautological (`XCTAssertEqual(view.frame.width,
sizeWeJustAssigned)`), and because `scripts/test.sh` runs on an iPhone simulator, the entire iPad
branch — `regularSidebar`, `detailColumn`, `detailSection`, `sidebarSelection`, `centreVertically`,
`heroSideRegular` — is never executed by the default test run.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: `StellarGlassyBackground` changes iPhone rendering on every non-393pt device (REG-01)

**File:** `StellarVolumiO/Utils/DesignTokens+Redesign.swift:66-96`

**Issue:** The radius moved from a flat `280` to `min(width, height) * 0.71`. The comment claims
"the 0.71 factor is chosen so a 393 pt-wide iPhone still lands on ~280 — the phone is deliberately
unchanged." That is true for exactly one screen width. Deployment target is iOS 17, so the
supported iPhone set includes 375 pt and 430/440 pt devices:

| Device | width | new radius | old radius | delta |
|---|---|---|---|---|
| iPhone SE 2/3, 13 mini | 375 | 266.25 | 280 | −4.9% |
| iPhone 16e | 390 | 276.90 | 280 | −1.1% |
| iPhone 16 / 15 / 14 Pro | 393 | 279.03 | 280 | −0.3% |
| iPhone 15 Plus / 15 Pro Max | 430 | 305.30 | 280 | **+9.0%** |
| iPhone 16 Pro Max | 440 | 312.40 | 280 | **+11.6%** |

This is not one screen. `StellarGlassyBackground` is used by `NowPlayingView`, `LibraryView`,
`SettingsView`, `AlbumTracksView`, `ArtistDetailView` and `BackendDiscoverySheet`. Under the stated
constraint ("any change that alters iPhone behaviour or layout is a defect"), this is a defect on
five of the six supported iPhone widths.

**Fix:** Gate the scaling to the canvases that needed it, and leave the phone on the shipped
constant.

```swift
struct StellarGlassyBackground: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private static let compactRadius: CGFloat = 280   // the value that shipped
    private static let radiusFactor: CGFloat = 0.71

    var body: some View {
        GeometryReader { geo in
            let radius = horizontalSizeClass == .regular
                ? min(geo.size.width, geo.size.height) * Self.radiusFactor
                : Self.compactRadius
            ...
        }
    }
}
```

(Or key it off `RootLayoutMode` so the `idiom == .pad` guard applies here too — see WR-01.)

---

### CR-02: Retained `mountedSections` permanently defeats `SettingsView.onAppear`, which the code calls "load-bearing"

**File:** `StellarVolumiO/App/ContentView.swift:181-199` (`detailColumn`), against
`StellarVolumiO/Views/Settings/SettingsView.swift:66-75`

**Issue:** `SettingsView` carries an explicit contract:

```swift
// Load-bearing: forces a fresh `getLcdStatus` emit whenever the
// Settings tab appears, so the toggle reconciles against the Pi
// after backgrounding / tab switches.
// Same reasoning for the inbox: ... it is the only thing that decides
// whether the ingest section shows at all.
.onAppear { lcd.refresh(); ingest.requestStatus() }
```

In `detailColumn`, `SettingsView` is inserted into `mountedSections` on first visit and never
removed, so it is never torn down and `onAppear` fires **once per app launch**. Two consequences on
iPad:

1. The LCD state in Settings never reconciles against the Pi again. `LcdStore.isOn` defaults
   optimistically to `true`, and `setOn` is optimistic, so a divergence (panel toggled from the LCD
   kiosk, backend restart, a dropped `pushLcdStatus`) is never repaired.
2. `IngestSection` renders nothing unless `ingest.isAvailable`
   (`IngestSection.swift:17`), and `isAvailable` is only ever set by the response to
   `requestStatus()`. If that single emit loses the race with socket connect — which is exactly the
   race the `detailColumn` doc comment identifies for `AlbumPickerStore` — the Add-music capability
   (PARITY-08) is **invisible for the entire session with no in-app recovery path**. On iPhone,
   returning to the Settings tab retries.

`ParitySweepTests.test04IngestSectionIsReachable` cannot catch this: it visits Settings once, which
is the one visit that works.

**Fix:** Reproduce `TabView`'s full lifecycle rather than half of it — drive an explicit
visibility signal into the retained sections and re-run the refresh on transition to visible.

```swift
// in detailSection(visible:)
.onChange(of: visible) { _, nowVisible in if nowVisible { onBecameVisible?() } }
```

Or, minimally, hoist the two refreshes into `ContentView.onChange(of: selectedTab)` so a section
switch still re-arms them.

---

### CR-03: The same mechanism kills the AirPlay resync and the Library retry

**File:** `StellarVolumiO/App/ContentView.swift:169-199`, against
`StellarVolumiO/Views/NowPlaying/NowPlayingView.swift:58-65` and
`StellarVolumiO/Views/Library/AlbumPickerView.swift:27-29`

**Issue:** The `detailColumn` doc comment's premise is factually wrong:

> "both exist to match `TabView`, which creates a tab lazily and retains it afterwards."

`TabView` is lazy, retains, **and re-fires `onAppear`/`onDisappear` when the selection changes** —
which is why `SettingsView`'s comment says "after backgrounding / tab switches" and
`NowPlayingView`'s says "whenever the tab becomes visible". The port implemented lazy + retain and
dropped the third property, so:

- `NowPlayingView.onAppear { socket.requestAirplayState() }` fires once. Its own comment explains
  what that costs: "without this the view stays on its stale prior state until shairport happens to
  emit a new metadata frame." Given this project's documented history of stale `isActive: true`
  AirPlay frames on transient drops, Now Playing can park on a dead session indefinitely on iPad.
- `AlbumPickerView.onAppear { if store.albums.isEmpty && !store.loading { store.load() } }` fires
  once. The `detailColumn` comment claims lazy mounting solves this ("eager mounting is what would
  have made it reachable in normal use here"). It does not — retention makes the *first* Library
  visit the only retry. If that visit happens before the socket connects, the album grid stays
  empty for the whole session, which is the exact failure mode the comment is arguing against.

**Fix:** Same as CR-02 — the retained sections need a "became visible" edge, not just a mount edge.
Until then, at minimum re-issue `socket.requestAirplayState()` from
`ContentView.onChange(of: selectedTab)` when the new section is `.player`.

---

### CR-04: Three `ParitySweepTests` cases query a button identifier the app explicitly overrides

**File:** `StellarVolumiOUITests/ParitySweepTests.swift:57-59, 82-83, 111-112, 260-271`

**Issue:** The suite reads play/pause state as `app.buttons["pause.fill"]` / `["play.fill"]`. But
`PlayPauseButton.swift:24` sets `.accessibilityLabel(isPlaying ? "Pause" : "Play")` on the
`Button`, replacing the SF-Symbol-derived label; there is no `accessibilityIdentifier` anywhere in
the app (`grep` finds exactly two `accessibilityLabel` calls and zero identifiers). Those queries
cannot resolve. Affected:

- `isPlaying(_:)` (line 58) — always returns `false`.
- `test01LcdToggleActsWithoutNavigating:82` and `test02VuToggleActsWithoutNavigating:111` —
  `XCTAssertTrue(app.buttons["pause.fill"].exists || app.buttons["play.fill"].exists, "toggling LCD
  must leave the detail column on Now Playing")` fails unconditionally, so both tests report a
  navigation regression that is not happening.
- `test07TransportControlsDriveThePlayer:263-271` — `toggle.isHittable` is `false`, the play/pause
  round trip never runs.

`TransportIconButton` (`backward.fill` / `forward.fill`) has no `accessibilityLabel` override, so
those two queries do work — which is why this reads as plausible on inspection.

Three of eight sweep tests fail regardless of app behaviour. The suite therefore cannot have been
run green, which undermines the only evidence offered for "all eight capabilities drive on iPad".

**Fix:** Match what the app actually publishes, and add stable identifiers so this class of break
stops happening.

```swift
// StellarVolumiO/Views/NowPlaying/PlayPauseButton.swift
.accessibilityLabel(isPlaying ? "Pause" : "Play")
.accessibilityIdentifier("transport.playPause")
.accessibilityValue(isPlaying ? "Playing" : "Paused")

// ParitySweepTests
private func isPlaying(_ app: XCUIApplication) -> Bool {
    app.buttons["transport.playPause"].value as? String == "Playing"
}
```

---

### CR-05: `ParitySweepTests` mutates live production state with no guard and no failure-path restore

**File:** `StellarVolumiOUITests/ParitySweepTests.swift:19-23, 71-95, 187-220, 250-300`;
`project.yml:118-133, 148-156`

**Issue:** The suite is not read-only against a real appliance:

- `test05AlbumPickerDrillsDownAndPlays` **replaces the MPD queue permanently** with whichever album
  sorts first. There is no restore, by design ("Restore the Pi afterwards if you care about what
  was playing" — a comment, not a mechanism).
- `test01`/`test02` toggle the physical LCD panel and the kiosk's VU view.
- `test07` pauses, skips forward, skips back, and seeks to 60%.

Every restore is written **at the end of the test body**, and `setUp` sets
`continueAfterFailure = false`. Any assertion failure — including the three that fail
unconditionally per CR-04 — aborts before the restore runs, leaving the appliance mutated. Only
`test08` uses `addTeardownBlock`, which is the correct mechanism and is not applied to the
destructive cases.

Compounding it: **there is no iPad guard**. Run the suite against an iPhone simulator (the default
in `scripts/test.sh`'s environment) and `app.buttons["LCD"]` matches the *LCD tab bar item*, so
`lcd.tap()` still toggles the real panel before the rest of the suite fails on missing sidebar
elements. And there is no host guard: the suite targets whatever backend the app resolves to, which
is `stellar.local` by default — the production appliance.

A committed scheme (`StellarVolumiOUITests`) plus a docstring warning is not a guard. One
`xcodebuild test -scheme StellarVolumiOUITests` from an agent, a CI matrix, or a mis-clicked Xcode
scheme selector reconfigures the user's music.

**Fix:** Gate on an explicit opt-in and an idiom check, and move every restore into a teardown
block.

```swift
override func setUpWithError() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["STELLAR_PARITY_SWEEP"] == "1",
                      "destructive sweep — set STELLAR_PARITY_SWEEP=1 and expect the Pi's queue to change")
    try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad-only sweep")
    continueAfterFailure = false
}

// test01, before the first tap
addTeardownBlock { if app.images[wasOn ? "display.slash" : "display"].exists { lcd.tap() } }
```

Separately: split `test05` out behind its own flag, or have it snapshot and restore the queue.

---

## Warnings

### WR-01: Phase 4 bypasses NAV-06, leaving the REG-01 guard covering only navigation

**File:** `StellarVolumiO/Views/NowPlaying/NowPlayingView.swift:70`,
`StellarVolumiO/Views/Library/AlbumTracksView.swift:128-133`

**Issue:** `RootLayoutMode`'s stated purpose is that the layout decision should not "spread through
the view tree as repeated `horizontalSizeClass` checks (NAV-06)", and its rule 1 is the REG-01
guard: `guard idiom == .pad else { return .tabs }`. Phase 4 then added three raw
`horizontalSizeClass == .regular` checks outside it (`centreVertically`, `AlbumCoverHero.side`, and
implicitly the `contentMaxWidth` cap). Those checks have no idiom guard.

`RootLayoutModeTests.testPhoneNeverGetsASidebarEvenAtRegularWidth` explicitly protects the case
"someone unlocks landscape on the phone later". If that happens, an iPhone Pro Max in landscape
reports `.regular` — `RootLayoutMode` correctly keeps the tab bar, but `NowPlayingView` starts
vertically centring and `AlbumCoverHero` jumps to 320 pt. The guard the code says it has does not
extend to the layout it was extended for.

**Fix:** Route the layout steps through the same decision.

```swift
private var isRoomyCanvas: Bool {
    RootLayoutMode.resolve(horizontalSizeClass: horizontalSizeClass,
                           idiom: UIDevice.current.userInterfaceIdiom) == .sidebar
}
```

### WR-02: `sidebarSelection` swallows `nil` without re-asserting the selection

**File:** `StellarVolumiO/App/ContentView.swift:230-239`

**Issue:** `set: { guard let newValue else { return } }` discards the write. Because the underlying
`selectedTab` does not change, SwiftUI does not invalidate, so nothing pushes the old value back
into the `List`. The `List`'s internal selection has already moved to `nil`, and it will not be
corrected. Observable result: the sidebar row loses its highlight while the detail column keeps
showing that section — the two disagree about where the user is.

**Fix:** Force an invalidation so the getter re-runs, e.g. bounce the value:

```swift
set: { newValue in
    guard let newValue else {
        // Re-assert: nudge the state so the List re-reads the getter.
        let current = selectedTab
        selectedTab = current == .player ? .library : .player
        selectedTab = current
        return
    }
    selectedTab = newValue
}
```

(Or keep a separate `@State private var sidebarTag: Tab?` mirrored from `selectedTab`, which avoids
the bounce.)

### WR-03: `detailColumn` has no branch for `.lcd` / `.vu` and no fallback

**File:** `StellarVolumiO/App/ContentView.swift:169-199`

**Issue:** `mountedSections` is `Set<Tab>` and `Tab` includes `.lcd` and `.vu`. The `ZStack` handles
only `.player`, `.library`, `.settings`. Today `selectedTab` can never hold an action tag — both
binding setters intercept them — but the type permits it, and if any future path sets one (a
restored value, a sidebar row that gains a tag, a keyboard shortcut), the detail column silently
renders **empty** with no diagnostic. The failure is invisible rather than loud.

**Fix:** Either split the action cases out of `Tab` into their own type, or add an explicit
fallback:

```swift
if !mountedSections.contains(where: { [.player, .library, .settings].contains($0) }) {
    NowPlayingView().detailSection(visible: true)   // never an empty column
}
```

### WR-04: Sections mount one frame late

**File:** `StellarVolumiO/App/ContentView.swift:195-198`

**Issue:** `mountedSections.insert(section)` runs in `.onChange(of: selectedTab)`, which fires
*after* the body that reacted to the new `selectedTab`. On the first visit to each section, the
`ZStack` renders with that section still absent, then re-renders with it present. Result: a frame
of empty detail column on each of the three first visits.

**Fix:** Insert at the point of selection instead, so the set and the tab move in the same
transaction:

```swift
set: { newValue in
    guard let newValue else { return }
    mountedSections.insert(newValue)
    selectedTab = newValue
}
```

### WR-05: `mountedSections` survives a shell swap, defeating the lazy-mount rationale; NAV-07 preserves less than claimed

**File:** `StellarVolumiO/App/ContentView.swift:14-15, 29-33`

**Issue:** Two problems from the same place.

1. `mountedSections` is `@State` on `ContentView` and is never cleared. A Slide Over / Stage
   Manager resize takes the app regular → compact → regular. On the way back, `detailColumn`
   rebuilds and **all three previously-visited sections mount simultaneously**, firing
   `AlbumPickerView.onAppear`, `SettingsView.onAppear` and `NowPlayingView.onAppear` in one burst.
   That is precisely the eager mount the doc comment says it avoids.
2. `switch layoutMode` compiles to `_ConditionalContent`, so swapping branches destroys everything
   inside. `selectedTab` survives (it is `@State` on `ContentView`), but `LibraryView`'s `segment`,
   its `NavigationStack` path, and any Album Tracks drill-down do not. The `sidebarSelection` doc
   comment says the shared `selectedTab` "is what makes NAV-07 true — a rotation or a Split View
   resize swaps the shell without resetting where the user was." That claim holds for the section
   only; within a section the user is reset to the root.

`RootNavigationShellTests.testShellSwapsAcrossASizeClassChange` is named for NAV-07 but asserts
nothing about preserved selection or preserved sub-state.

**Fix:** Document the real scope of NAV-07, and hoist `LibraryView`'s `segment` and navigation path
into `ContentView` `@State` (or an `@Observable` store) so they survive the branch swap. Clearing
`mountedSections` on shell teardown would also restore the lazy property, at the cost of the
retention that CR-02/CR-03 already show is only half-working.

### WR-06: Sidebar LCD / VU buttons expose no state to VoiceOver

**File:** `StellarVolumiO/App/ContentView.swift:130-166`

**Issue:** Both action rows are `Button { … } label: { Label("LCD", systemImage: lcd.isOn ? "display" : "display.slash") }`.
The `Label`'s text is constant, so VoiceOver announces "LCD, button" whether the panel is lit or
dark, and "VU Meter, button" regardless of what the kiosk is showing. The state lives entirely in
the SF Symbol, which VoiceOver does not read when a `Label` supplies text. The port's own comment
says the icon flip "is the part the user actually reads" — that is true only for sighted users.

`SettingsView.lcdToggleRow` gets this right (it renders a literal "On"/"Standby" line), so the
sidebar is a regression relative to the app's own existing pattern.

**Fix:**

```swift
Label("LCD", systemImage: lcd.isOn ? "display" : "display.slash")
    ...
.accessibilityValue(lcd.isOn ? "On" : "Standby")
.accessibilityHint("Double tap to turn the panel \(lcd.isOn ? "off" : "on")")
.accessibilityIdentifier("sidebar.lcd")
```

### WR-07: The connection-failure banner is not adapted for the sidebar shell

**File:** `StellarVolumiO/App/ContentView.swift:29-45`

**Issue:** The banner sits in the root `ZStack(alignment: .top)` above *both* shells, spanning the
full window. On iPad that means it is drawn over the top of the sidebar, covering the navigation
title and the first rows ("Now Playing", "Library"). It is opaque
(`Color.black.opacity(0.85)`) and is a hit-testing sibling, so while it is visible those sidebar
rows are obscured and likely untappable — during a connection failure, which is exactly when the
user wants to reach Settings. Its own comment ("sits above the safe area so it doesn't fight the
tab bar") is now stale. It also stretches to 1366 pt with no `contentMaxWidth` cap, unlike every
other surface Phase 4 capped.

**Fix:** Scope the banner to the detail column in the sidebar branch, or cap and align it:

```swift
connectionFailureBanner
    .frame(maxWidth: Stellar.Metric.contentMaxWidth)
    .frame(maxWidth: .infinity, alignment: layoutMode == .sidebar ? .trailing : .center)
```

### WR-08: `LibraryView`'s `NavigationStack` is now nested inside the split view's detail column

**File:** `StellarVolumiO/App/ContentView.swift:174-176`, against
`StellarVolumiO/Views/Library/LibraryView.swift:16-39`

**Issue:** `NavigationSplitView`'s detail column already provides a navigation container.
`LibraryView` puts a `NavigationStack` inside it, and `AlbumTracksView` sets `.navigationTitle` +
`.navigationBarTitleDisplayMode(.inline)` inside *that*. Apple documents this nesting as
unsupported; the usual result is two stacked navigation bars on the Album Tracks screen and
`navigationTitle`/toolbar modifiers landing on the inner bar rather than the detail bar. Meanwhile
`SettingsView` and `NowPlayingView` have no stack at all, so the detail column's chrome differs
per section.

`ParitySweepTests.test05` only asserts that `Play Album` exists and is hittable, so it cannot see a
duplicated bar.

**Fix:** Either drive Library's drill-down through the split view's own detail navigation (move
`.navigationDestination` up to the detail column and drop `LibraryView`'s `NavigationStack` on the
sidebar branch), or wrap all three sections uniformly so the chrome is consistent. A screenshot
assertion or a `app.navigationBars.count == 1` check would pin it.

### WR-09: `testHeroFitsTheNarrowestRegularWidthCanvas` measures the window, not the detail column

**File:** `StellarVolumiOTests/AlbumTracksLayoutRenderTests.swift:89-101`

**Issue:** The test asserts `heroSideRegular (320) <= 500 - 48`, calling 500 "iPad mini detail
column". 500 is not a detail-column width — it is roughly a *window* width. In the sidebar shell
the detail column is the window minus the sidebar (~320 pt at `.balanced` with
`columnVisibility: .all`). The compact/regular threshold on iPadOS is around 590 pt, so the
narrowest window that still reports `.regular` leaves roughly 280 pt of detail. `AlbumCoverHero`
uses a **fixed** `.frame(width: side, height: side)` inside `.padding(.horizontal, 24)`, so it
needs 368 pt and cannot shrink — it clips.

The test also compares two constants to each other and never renders `AlbumCoverHero`, so it cannot
observe the overflow it claims to prevent.

**Fix:** Make the hero adaptive rather than a fixed step, and measure it for real.

```swift
.frame(maxWidth: side, maxHeight: side)
.aspectRatio(1, contentMode: .fit)
```

and add a test that hosts `AlbumTracksView` at a ~280 pt detail width with `.regular` overridden and
asserts the rendered hero's width is `<= containerWidth - 48`.

### WR-10: Four new "render test" files assert only tautologies

**Files:** `StellarVolumiOTests/RootLayoutRenderTests.swift:86-90, 106-108`;
`AlbumTracksLayoutRenderTests.swift:77-80`; `SheetLayoutRenderTests.swift:60-63, 75-78`;
`AirplayLayoutRenderTests.swift:79-82, 95-96`

**Issue:** The dominant assertion in all four files is:

```swift
host.view.frame = CGRect(origin: .zero, size: size)
host.view.layoutIfNeeded()
XCTAssertEqual(host.view.frame.width, size.width, accuracy: 0.5)
```

This re-reads the value assigned two lines earlier. `UIView.frame` is not recomputed by
`layoutIfNeeded()` for a view whose frame the caller set directly — the assertion is true by
construction and cannot fail. Likewise `XCTAssertNotNil(host.view)` (line 86) tests a
**non-optional** `UIView` property, and `XCTAssertGreaterThan(host.view.frame.height, 0)` is the
same tautology.

Net effect: 11 of the ~14 assertions in these four files are unfalsifiable. What they *do* provide
— a smoke check that the view graph composes without trapping — is real but undocumented and much
weaker than the file headers claim ("A branch that crashes, nil-derefs, or fails to compose fails
here" is accurate; "geometry regression net" is not).

**Fix:** Assert on something the layout actually produced. Host in a window, drive
`view.layoutIfNeeded()`, then walk the hierarchy for the element under test:

```swift
let hero = host.view.findSubview(identifier: "album.coverHero")
XCTAssertEqual(hero.bounds.width, expectedSide, accuracy: 1)
```

and rename the smoke cases to `testRootComposesWithoutTrapping` so the coverage claim matches.

### WR-11: The entire iPad branch has zero coverage in the default test run

**Files:** `StellarVolumiOTests/RootNavigationShellTests.swift:120-176`;
`RootLayoutRenderTests.swift:70-78`; `AirplayLayoutRenderTests.swift:66-71`;
`SheetLayoutRenderTests.swift:43-48`; against `scripts/test.sh:22`

**Issue:** `scripts/test.sh` targets an **iPhone 16 Pro** simulator.
`RootNavigationShellTests` derives its expectation from the runner:

```swift
let expectSidebar = UIDevice.current.userInterfaceIdiom == .pad
```

On the iPhone runner, `expectSidebar` is `false` in all three tests, so
`testRegularWidthBuildsTheSidebarOnPadAndTabsElsewhere` and
`testShellSwapsAcrossASizeClassChange` collapse to the same assertion as
`testCompactWidthBuildsTheTabBar`: "a tab bar exists, a split view does not." The sidebar branch is
never built.

`RootLayoutRenderTests` uses a bare `UIHostingController` with no trait override, so its seven
"iPad canvas" cases all render the `TabView`. `AirplayLayoutRenderTests` and
`SheetLayoutRenderTests` likewise never override the size class, so `centreVertically` is `false`
in every test that exists.

Consequently `regularSidebar`, `detailColumn`, `detailSection(visible:)`, `sidebarSelection`,
`centreVertically`, `heroSideRegular` and the `contentMaxWidth` cap are all executed **zero times**
by `scripts/test.sh`. `RootLayoutModeTests` covers the decision; nothing covers the shell.
(`AlbumTracksLayoutRenderTests` is the sole file that does override the trait, and its assertions
are the tautologies in WR-10.)

Also: `RootLayoutRenderTests`' header says "There is no UI test target in this repo" — stale as of
`5983f4d`, which added one.

**Fix:** Override the idiom the same way the size class is overridden, so both branches run on one
simulator — inject the idiom rather than reading `UIDevice.current`:

```swift
// ContentView
var idiomOverride: UIUserInterfaceIdiom? = nil     // tests only
private var layoutMode: RootLayoutMode {
    RootLayoutMode.resolve(horizontalSizeClass: horizontalSizeClass,
                           idiom: idiomOverride ?? UIDevice.current.userInterfaceIdiom)
}
```

Then assert the sidebar branch unconditionally instead of deriving the expectation from the runner.
Failing that, add an iPad destination to `scripts/test.sh` and `XCTSkipUnless` the idiom, so the
gap is loud rather than silent.

### WR-12: `testActiveSessionSuppressesSeekAndFormatStrip` is vacuous and its second half dodges a real bug

**File:** `StellarVolumiOTests/AirplayLayoutRenderTests.swift:106-127`, against
`StellarVolumiO/Views/NowPlaying/NowPlayingPlayingView.swift:46, 66-83`

**Issue:** Three problems.

1. `XCTAssertTrue(display.isAirplay, "a session with a sender must select the AirPlay branch")`
   cannot fail. `isAirplay` is `airplaySender != nil`, and `from(airplay:)` unconditionally sets
   `airplaySender: s.sender` (a non-optional `String`). Every value produced by that adapter has
   `isAirplay == true`.
2. `canSeek`, `samplerate`, `bitdepth` and `trackType` are **literals** in `from(airplay:)`
   (`canSeek: false`, `trackType: ""`, `samplerate: ""`, `bitdepth: ""`). Asserting them is a
   change-detector, not a behaviour test — and `NowPlayingDisplayStateTests` already covers this
   adapter.
3. The last assertion is written to avoid the bug:

```swift
XCTAssertFalse(NowPlayingDisplayState.from(airplay: .empty).airplaySender?.isEmpty == false,
               "an empty session carries no sender")
```

The comment above it says "an inactive session must not be mistaken for the AirPlay branch", but
the assertion checks the *sender*, not the branch — because
`NowPlayingDisplayState.from(airplay: .empty).isAirplay` **is `true`**. The adapter labels an
inactive session as AirPlay; it is masked only by `NowPlayingView` gating on
`airplay.state.isActive` before ever calling the adapter. The test documents a guarantee the code
does not provide.

**Fix:** Make `isAirplay` mean what it says, then assert it directly.

```swift
// NowPlayingPlayingView.swift
airplaySender: s.sender.isEmpty ? nil : s.sender,
```
```swift
XCTAssertFalse(NowPlayingDisplayState.from(airplay: .empty).isAirplay,
               "an inactive session must not select the AirPlay branch")
```

And delete the duplicated adapter assertions here in favour of `NowPlayingDisplayStateTests`,
leaving this file to do what its header promises: render the branch and inspect the hierarchy.

### WR-13: `ParitySweepTests` index-based lookups are coupled to the port's own retained-section design

**File:** `StellarVolumiOUITests/ParitySweepTests.swift:195, 234, 275, 279, 291`

**Issue:** The suite resolves elements positionally:

- `app.scrollViews.element(boundBy: 1)` — the album grid.
- `app.scrollViews.buttons.element(boundBy: 0)` — an artist's album tile.
- `app.scrollViews.firstMatch` — "the detail column".
- `detail.staticTexts.element(boundBy: 0)` — "the track title".

Every one of these indices is a function of `detailColumn`'s retained sections. When Library is
selected, `NowPlayingView` is still in the hierarchy at `opacity(0)`, and whether it appears in
`app.scrollViews` depends on whether `accessibilityHidden(true)` prunes it from the XCUI tree — an
implementation detail the port introduced and does not pin. `boundBy: 1` is a guess that happens to
be consistent with one of the two possible outcomes.

`detail.staticTexts.element(boundBy: 0)` additionally assumes the first static text in
`NowPlayingPlayingView` is the track title; the hierarchy actually starts with `AlbumArtHero` (which
can carry placeholder text) and, on the AirPlay branch, `AirplaySourceBadge`.

The app has **zero** `accessibilityIdentifier`s, so there is nothing stable to anchor on.

**Fix:** Add identifiers at the points the sweep needs and query by them:
`library.albumGrid`, `library.albumTile`, `nowPlaying.trackTitle`, `nowPlaying.elapsed`,
`sidebar.lcd`, `sidebar.vu`, `detail.column`. Then replace every `element(boundBy:)` with an
identifier query.

### WR-14: `test06`'s sidebar-exclusion predicate does not exclude the sidebar

**File:** `StellarVolumiOUITests/ParitySweepTests.swift:225-231`

**Issue:**

```swift
// Scope past the sidebar: it is a collection view too, and its rows
// would otherwise satisfy every "first row" query in this test.
let artistList = app.collectionViews.matching(
    NSPredicate(format: "label != %@", "Sidebar")).element(boundBy: 0)
```

The sidebar's backing collection view has no accessibility label of `"Sidebar"` — SwiftUI does not
assign one, and `.navigationTitle("Stellar")` titles the navigation bar, not the list. Its label is
empty, `"" != "Sidebar"` is true, so it passes the filter and `element(boundBy: 0)` can resolve to
the sidebar. `artistList.cells.element(boundBy: 0)` would then be "Now Playing", and the subsequent
`.tap()` would navigate rather than drill into an artist — producing the exact failure the comment
says it is preventing, while the test still finds an album tile afterwards (the retained
`NowPlayingView`/`LibraryView` are both in the tree) and passes for the wrong reason.

**Fix:** Give the artist list an identifier and query it: `app.collectionViews["library.artistList"]`.

### WR-15: Unguarded taps and un-awaited hittability checks in `ParitySweepTests`

**File:** `StellarVolumiOUITests/ParitySweepTests.swift:176, 183, 256-257`

**Issue:**
- `app.buttons["Done"].firstMatch.tap()` (176) — no `waitForExistence`, no assertion. If the sheet's
  dismiss control is labelled anything else, this raises a raw XCUI "no matches found" instead of
  the intended failure message.
- `manual.tap()` (183) is a bare state-restoring tap with no assertion that it collapsed anything.
- `XCTAssertTrue(app.buttons["backward.fill"].isHittable, ...)` and the `forward.fill` equivalent
  (256-257) call `isHittable` with no prior `waitForExistence`. `isHittable` on an element that has
  not resolved yet returns `false` without waiting, so this is a launch-timing flake.

**Fix:** `XCTAssertTrue(x.waitForExistence(timeout: Self.timeout))` before every `isHittable` /
`tap()`, and assert the post-condition of every restoring tap.

### WR-16: `test05` truncates album titles containing a comma

**File:** `StellarVolumiOUITests/ParitySweepTests.swift:213-218`

**Issue:** `let title = String(albumLabel.split(separator: ",").first ?? "")` assumes the tile's
XCUI label is exactly `"<title>, <artist>"` and that the title has no comma. Comma-bearing album
titles are common (`"Live, Vol. 2"`, `"Songs of Love, Loss and Longing"`), and `AlbumTile` has no
explicit `accessibilityLabel`, so the label is whatever XCUI concatenates from its subviews — which
may also include the year or track count. The assertion then searches for a truncated string and
fails on correct behaviour.

**Fix:** Give `AlbumTile` an explicit label and read the title from a dedicated element:

```swift
// AlbumTile
.accessibilityElement(children: .ignore)
.accessibilityLabel("\(album.title), \(album.artist)")
.accessibilityIdentifier("library.albumTile")
.accessibilityValue(album.title)
```
then `let title = album.value as? String ?? ""`.

### WR-17: `renderRoot` drops the `SocketService` before the assertions, violating the invariant its own sibling documents

**File:** `StellarVolumiOTests/RootLayoutRenderTests.swift:33-78`

**Issue:** `makeRoot()` carries an explicit warning:

> "The `SocketService` is deliberately returned alongside the view: stores hold it weakly, so
> letting it fall out of scope would leave every binding dead. **Callers must keep the returned
> tuple alive for the duration of the test.**"

`renderRoot(at:)` — the only caller in `testRootComposesAtEveryCanvasSize` — does not. It binds
`root` locally, calls `withExtendedLifetime(root.socket) {}` *inside* the function, and returns only
the `UIHostingController`. The socket deallocates when `renderRoot` returns, before every assertion
in the loop. This is the exact "bind a named local, never a temporary" trap this repo has hit
before. `testRootSurvivesLiveResizeSequence` (line 99) gets it right; the other does not.

Practically nothing in these tests depends on a live socket, which is why it passes — but that means
the documented precaution is decorative, and a future test that *does* depend on it will fail
silently and confusingly.

**Fix:** Return the socket and hold it in the test:

```swift
private func renderRoot(at size: CGSize) -> (host: UIHostingController<AnyView>, socket: SocketService) { ... }

for canvas in Self.canvases {
    let rendered = renderRoot(at: canvas.size)     // named local, held for the assertions
    ...
    withExtendedLifetime(rendered.socket) {}
}
```

### WR-18: `SheetLayoutRenderTests` guards a socket that is never bound to anything

**File:** `StellarVolumiOTests/SheetLayoutRenderTests.swift:29-41, 50-79`

**Issue:** `makeEnvironment()` constructs a `SocketService` and an `IngestStore`, documented as
"returned alongside because the stores hold it weakly — dropping it would leave every binding dead."
But neither sheet under test receives it: `BackendDiscoverySheet` is injected only
`.environment(env.discovery).environment(env.config)`, and `BackendDiscoverySheet` declares exactly
three environment reads (`dismiss`, `BackendDiscoveryService`, `BackendConfigStore`) — no
`SocketService`. `IngestSheet` gets only `env.ingest`. Nothing is bound, so the
`withExtendedLifetime(env.socket) {}` calls and the comment are ceremony that reads as a real
precaution. `env.ingest` is likewise unused in `testBackendDiscoverySheetComposesAtEveryPresentationSize`.

**Fix:** Drop the socket from `makeEnvironment()` and the comment with it, or inject it and mean it.

### WR-19: Unconditional layout wrappers added to the iPhone render path

**File:** `StellarVolumiO/Views/NowPlaying/NowPlayingView.swift:31, 51-52`

**Issue:** Two containers were inserted for every device even though the behaviour they enable is
iPad-only:

- `GeometryReader { geo in ScrollView { … } }` — `geo` is read only by
  `centreVertically ? geo.size.height : 0`, and `centreVertically` is `horizontalSizeClass == .regular`,
  which is never true on a portrait-locked iPhone. `GeometryReader` changes proposal and alignment
  semantics (greedy sizing, `.topLeading` child placement) and is a well-known source of subtle
  scroll-view and safe-area differences.
- `.frame(minHeight: 0, alignment: .center)` — a no-op container on iPhone, but still a new layout
  node in the tree.

REG-01 says the phone's path should be untouched. Right now the phone runs through two new layout
containers to support a branch it can never take. This is materially lower risk than CR-01, but it
is the same class of violation and it is trivially avoidable.

**Fix:** Gate the wrapper on the branch that needs it:

```swift
if centreVertically {
    GeometryReader { geo in scroll(centreTo: geo.size.height) }
} else {
    scroll(centreTo: nil)      // the exact tree the iPhone shipped with
}
```

## Info

### IN-01: `AlbumCoverHero.side` mixes a design token with a bare literal

**File:** `StellarVolumiO/Views/Library/AlbumTracksView.swift:128-133`

**Issue:** `horizontalSizeClass == .regular ? Stellar.Metric.heroSideRegular : 240`. The regular
branch uses a token, the compact branch uses a literal, against the project's stated "design tokens
via `Color.md*` / `Stellar.*` / `StellarFont.*` rather than literals" convention. The same `240` is
duplicated in `AlbumTracksLayoutRenderTests.swift:98`, so the test and the view can drift apart
without either failing.

**Fix:** Add `Stellar.Metric.heroSideCompact = 240` and use it in both places.

### IN-02: Substantial duplication across the new test files

**Files:** `RootLayoutRenderTests.swift:39-68` vs `RootNavigationShellTests.swift:31-48`;
`RootNavigationShellTests.swift:24-71` vs `AlbumTracksLayoutRenderTests.swift:27-61`

**Issue:** `makeRoot()` (the 12-store environment graph) is written twice with slightly different
contents; the `Hosted` struct and the container-plus-window-plus-trait-override boilerplate is
written twice; `withExtendedLifetime(x) {}` appears ~10 times. When the environment graph gains a
store, two files must change and only one will fail loudly.

**Fix:** Extract a shared `StellarTestHost.swift` in `StellarVolumiOTests/` providing
`makeRootEnvironment()` and `host(_:horizontalSizeClass:size:) -> Hosted`.

### IN-03: `columnVisibility` is write-only state

**File:** `StellarVolumiO/App/ContentView.swift:13, 129`

**Issue:** Initialised to `.all`, passed to `NavigationSplitView`, and never read or written by the
app. If the user collapses the sidebar there is no restore affordance and no other surface exposes
the sections. Harmless today, but it is state that exists without a purpose.

**Fix:** Either drop the binding (`NavigationSplitView { } detail: { }` manages its own visibility)
or use it — e.g. reassert `.all` on a size-class change so a Slide Over round trip does not leave
the sidebar hidden.

### IN-04: `isPlaying(_:)` helper is single-use and built on the broken identifier

**File:** `StellarVolumiOUITests/ParitySweepTests.swift:57-59`

**Issue:** Used once (line 262) and returns `false` unconditionally per CR-04. Folds into the CR-04
fix.

### IN-05: Touch-target enforcement is inconsistent across sidebar rows

**File:** `StellarVolumiO/App/ContentView.swift:118-121, 131-166`

**Issue:** The two untagged `Button` rows explicitly enforce
`minHeight: Stellar.Metric.minTouchTarget`; the three tagged navigation rows
(`Label(...).tag(...)`) do not. `List` defaults are almost certainly ≥ 44 pt on iPad, so this is
not a live violation — but the inconsistency means a future style change to the rows would silently
drop below 44 pt on only three of the five.

**Fix:** Apply the same `minHeight` to the tagged rows, or extract a `sidebarRow` helper.

### IN-06: Pre-existing sub-44pt touch targets in the failure banner (not in this diff)

**File:** `StellarVolumiO/App/ContentView.swift:271, 292`

**Issue:** Surfaced while auditing touch targets. `Retry` and `Server Settings` both use
`.frame(minHeight: Stellar.Metric.minTouchTarget * 0.65)` = 28.6 pt, below the project's stated
44×44 pt convention. This predates the branch and is out of scope for the port, but it is now the
only sub-44 pt control in the file and it appears during a connection failure — when tap accuracy
matters most.

**Fix:** Out of scope for this branch; file separately.

---

_Reviewed: 2026-09-08T21:23:19Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
