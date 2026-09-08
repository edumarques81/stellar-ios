---
mapped: 2026-09-09
focus: concerns
---

# Concerns — stellar-ios

Ordered by how much each one collides with the planned iPad port.

## 1. `UIRequiresFullScreen: YES` — blocking, and deprecated

`project.yml` sets `UIRequiresFullScreen: YES` and lists only
`UIInterfaceOrientationPortrait`. On iPad this forbids Split View and Stage
Manager outright, and the key is **deprecated as of iPadOS 26**. Apple's
direction is that iPad apps participate in multitasking; keeping it is a
growing App Store liability, not just a UX one.

Removing it is mandatory for the agreed scope and is a genuine behavioural
change: every screen must survive arbitrary widths, including a ~320 pt Slide
Over pane, not merely two or three fixed device widths.

## 2. The action-only tab trick has no sidebar equivalent

`ContentView.tabSelection` turns the `.lcd` and `.vu` tags into buttons by
intercepting the binding's setter and refusing to update `selectedTab`, so
`TabView` snaps back. This is clever and well documented — and it does not
translate. `NavigationSplitView`'s sidebar is a `List` with a selection binding;
there is no "tap and bounce back" affordance.

The port must relocate LCD power and VU toggle into explicit controls. Doing
that badly risks regressing the iPhone build, because both live in the same
`ContentView`. **The iPhone path must be preserved verbatim** and the sidebar
built as a parallel branch, not a rewrite of the existing one.

## 3. No size-class awareness anywhere

Zero occurrences of `horizontalSizeClass`, `verticalSizeClass`, or
`UIDevice.userInterfaceIdiom` in the codebase. Nothing to build on — but also
nothing to unpick. Choose one mechanism and apply it consistently.

## 4. Fixed frames tuned for phone width

`AlbumTracksView` hero `240 × 240`, `AirplaySourceBadge` `width: 240`,
`StellarLogoView` `200 × 160` and `280 × 280`, and
`StellarGlassyBackground`'s absolute `endRadius: 280` radial gradients. None
break on iPad, but all read as visually undersized on an 11–13" canvas.
The album/artist grids are already `GridItem(.adaptive(...))` and reflow for
free — that part is fine.

## 5. Stores are main-confined by convention, not by the type system

No store is `@MainActor`. Safety rests entirely on `SocketService` routing every
callback through `DispatchQueue.main.async`, plus `Task { @MainActor … }` in the
tickers. It holds today, and the test suite is green, but the compiler is not
enforcing it. Any new code path that touches a store off the main queue — for
instance a size-class observer or a scene-phase handler added during the port —
would be an unchecked data race.

Not worth fixing as part of this port, but new code must respect the convention,
and annotating the stores `@MainActor` is the right eventual cleanup.

## 6. `BackendDiscoveryService: @unchecked Sendable` is a promise, not a proof

The conformance was added to silence non-Sendable capture warnings on
`browserQueue.async`. The invariant it asserts — every stored property is either
`@MainActor`-isolated or touched only inside `browserQueue` — matches the code as
written and is documented at the declaration. It is nonetheless unchecked: a
future property that respects neither domain compiles silently and races.
Multitasking makes discovery lifecycle more interesting (scenes can appear and
disappear), so this is worth re-reading during the port.

## 7. Feature scope has already drifted past "six features"

The stated scope is six features. The code ships **eight** user-facing
capabilities:

| Capability | In the stated six? |
|---|---|
| Transport / Now Playing | yes |
| Album picker → tracks | yes |
| Artist picker → albums → tracks | yes |
| LCD on/off toggle | yes |
| Backend server selection | yes |
| AirPlay source mode | yes |
| **VU meter view toggle** (`LcdViewStore`, `.vu` tab) | no — adjacent to LCD, arguably an extension of it |
| **Ingest / "Import from inbox"** (`IngestStore`, `IngestSection`, `IngestSheet`) | **no** — a genuinely separate seventh feature |

This is pre-existing and not the port's problem to solve, but it matters for
planning: the iPad sidebar has to accommodate **all** of it, and "port the six
features" would under-scope the work. Ingest in particular brings a sheet with
its own `NavigationStack`, which needs a deliberate presentation decision on
iPad (sheets present very differently on a large canvas).

## 8. Test suite cannot see layout regressions

No UI test target. The only rendering coverage is `UIHostingController`
smoke tests that assert "it composed at all". Nothing would catch the sidebar
collapsing, a pane rendering empty, or content stranded at 320 pt in Slide Over.
The port needs new tests built on that pattern, and pure layout-decision types
that can be tested without rendering.

## 9. Pre-existing, unrelated to the port

- **App Store submission** (ASC app id `6773923668`) was blocked on the Xcode 26
  SDK floor. **Xcode 26.3 is now installed**, so that blocker is cleared.
- `scripts/test.sh` runs `-quiet` and reports only an exit code, which hides both
  test counts and the identity of a failing case.
- `StellarApp.init()` constructs `BackendConfigStore()` twice — once in the
  property initialiser, once in `init` — and discards the first. Harmless, but
  confusing to read.

## Explicitly not a concern — do not "fix"

`SocketService.setVolume` and `toggleMute` have no call sites. They are retained
deliberately: the user may revisit volume control later, and no volume is to be
applied to the bit-perfect audio path in the meantime. Removing them as dead
code would be a regression against an explicit decision.
