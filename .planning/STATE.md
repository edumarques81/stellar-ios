# State: Stellar Remote — iPad Port

**Updated:** 2026-09-09
**Branch:** `feature/ipad-port`
**Current phase:** Phase 2 — next

## Progress

| Phase | Status |
|---|---|
| 0 — Setup & codebase map | ✅ complete |
| 1 — iPad device family, orientations, multitasking | ✅ complete |
| 2 — Layout-decision type (TDD) | ⬜ next |
| 3 — NavigationSplitView sidebar | ⬜ |
| 4 — iPad-size layout adaptation | ⬜ |
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
- **Known verification gap:** scripted simulator rotation does not work here
  (System Events cannot drive Simulator), so landscape is verified via the built
  Info.plist and the render tests rather than a rotated screenshot. Real
  rotation testing happens on the physical iPad in Phase 6.

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
