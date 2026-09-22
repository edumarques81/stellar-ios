# Coding Conventions

**Analysis Date:** 2026-09-09

## Scope note

This is `stellar-ios/` — `StellarVolumiO`, a Swift 6 / SwiftUI iPhone+iPad remote for the Stellar
Volumio appliance. It is a Swift Package (`Package.swift`) with a thin `project.yml`
(XcodeGen) wrapper that produces a signable, installable `.xcodeproj`.

## Hard rules (non-negotiable)

These are enforced by review/convention, not by a linter (no SwiftLint/SwiftFormat config exists
in this repo — see "Linting" below). Violating them breaks things silently.

1. **`@Observable` only, never `ObservableObject`.** Every store in `StellarVolumiO/Stores/` and
   `SocketService`/`BackendDiscoveryService` in `StellarVolumiO/Services/` is declared
   `@Observable final class`. `grep -rl ObservableObject StellarVolumiO/` returns nothing — keep
   it that way. `ObservableObject` + `@Published` does not compose the same way with the
   UIKit-backed `NavigationSplitView`/`TabView` hosting this app relies on for the iPad port; the
   whole store layer, and the test-hosting harness (`LayoutHosting`), assumes `@Observable`.

2. **Design tokens only — no raw colors/fonts/sizes in views.** Two token systems coexist:
   - `Color.md*` (`StellarVolumiO/Utils/DesignTokens.swift`) — Material Design 3-inspired,
     multi-theme (8 palettes selected via `UserDefaults` key `"colorTheme"`, default `"rose"`).
     Use `.foregroundStyle(.mdPrimary)`, `.background(.mdSurfaceContainer, in: ...)` — the
     `ShapeStyle where Self == Color` passthrough extension makes the dot-shorthand resolve.
   - `Stellar.Color` / `Stellar.Metric` / `Stellar.Shadow`
     (`StellarVolumiO/Utils/DesignTokens+Redesign.swift`) — a second, newer namespace ported
     directly from the Volumio2-UI Svelte redesign tokens (`Stellar.Color.gold`,
     `Stellar.Metric.playDisc`, `Stellar.Metric.contentMaxWidth`, etc.), scoped under `Stellar.*`
     specifically so it doesn't collide with `md*`.
   - Typography: `StellarFont.*` (`displayLarge` … `labelSmall`), a fixed MD3 type scale.
   - When touching a view, use the token system the surrounding code already uses in that file —
     don't mix `md*` and `Stellar.*` inside the same component without reason.

3. **44×44pt minimum touch targets.** `Stellar.Metric.minTouchTarget: CGFloat = 44`
   (`DesignTokens+Redesign.swift:43`) is the canonical constant — comment there cites Apple HIG.
   Sidebar rows in `ContentView.swift:156` explicitly pin to it. Any new tappable control
   (button, row, icon) must be sized to at least this, especially icon-only buttons that would
   otherwise size to their glyph.

4. **After adding any new `.swift` file, run `xcodegen generate --spec project.yml`.**
   `project.yml` globs `StellarVolumiO/` for sources (excluding `**/*.md`); the generated
   `.xcodeproj` is what `xcodebuild`/`scripts/build.sh`/`scripts/test.sh` actually compile. Skip
   this step and the build fails with "cannot find X in scope" for the new file, even though it's
   on disk and matches the glob — the stale `.xcodeproj` simply doesn't reference it yet.

5. **Conventional commits:** `<type>(<scope>): <description>` — `feat`, `fix`, `docs`, `refactor`,
   `test`, `chore`. Matches the workspace-wide convention (see recent `git log`:
   `fix(ingest): …`, `fix(library): …`, `test(ipad): …`).

## Naming Patterns

**Files:** One primary type per file, filename matches the type exactly —
`PlayerStore.swift` → `PlayerStore`, `AlbumArtworkSquare.swift` → `AlbumArtworkSquare`.

**Directories map to architectural layers**, not features:
`App/`, `Models/`, `Services/`, `Stores/`, `Utils/`, `Views/{Library,NowPlaying,Settings}/`,
`Components/` (small reusable leaf views, e.g. `AlbumArtworkSquare`).

**Types:** `UpperCamelCase`. Stores are suffixed `Store` (`PlayerStore`, `AlbumTracksStore`,
`IngestStore`), services suffixed `Service` (`SocketService`, `BackendDiscoveryService`), views
suffixed `View` (`NowPlayingView`, `AlbumTracksView`), models are bare nouns
(`PlayerState`, `AirplayState`, `LibraryModels.swift` groups several small model structs).

**Functions/variables:** `lowerCamelCase`. Boolean state reads as an adjective/predicate:
`isPlaying`, `isBusy`, `isAvailable`, `hasTrack`, `hasItems`, `canControl`. Actions are verbs:
`applyOptimistic(_:)`, `receiveServerState(_:)`, `bind(to:)`.

**Push/pull socket naming mirrors the wire contract.** Handler-registration methods on
`SocketService` are named `on<EventPurpose>` (`onPushAirplayState`, `onPushAirplayEnded`,
`onLibraryAlbumTracks`) or the generic `on(_:handler:)` / `onRawDict(_:parser:handler:)` /
`onRawDictNullable` for ad hoc events. Emit-side wrappers are named after the backend event with
no prefix (`play()`, `pause()`, `seek(to:)`, `lcdSetView(_:wake:)`, `airplayPlay()`).

**`Stellar.*` and `md*` design-token members** are lowerCamelCase static members grouped in
nested enums (`Stellar.Color`, `Stellar.Metric`, `Stellar.Shadow`) or as flat `static var`/`let`
prefixed `md` (`mdPrimary`, `mdOnSurfaceVariant`, `mdShapeLarge`).

## Code Style

**Formatting:** No `.swiftformat`/`.swiftlint.yml` exists in this repo — style is convention-only,
enforced by human review. Match surrounding code exactly when editing a file.

- 4-space indentation.
- `// MARK: -` section headers are used liberally to split a file into logical regions (e.g.
  `SocketService.swift` has `// MARK: - Connect`, `// MARK: - Emit`, `// MARK: - Subscribe`,
  `// MARK: - Internal socket lifecycle`, `// MARK: - Test hooks`).
- Doc comments (`///`) are dense and explain **why**, not just what — see any store or
  `SocketService` method. A comment that only restates the signature is not the house style;
  comments here almost always record a bug that was fixed, a subtlety in Swift concurrency, or a
  constraint from the wire contract / backend behavior. Preserve this style when adding code:
  explain the non-obvious reasoning, not the mechanical steps.
- Struct/array literal field alignment: when several `Palette`/model fields are declared close
  together, colons are column-aligned (see `DesignTokens.swift`'s `Palette` struct and its
  `palettes` dictionary literals).

**Linting:** None configured. `make check`-equivalent does not exist for this target; the closest
thing to a gate is `scripts/build.sh` (compile-check) and `scripts/test.sh` (test suite). Both
must pass before considering a change complete — see TESTING.md.

## Import Organization

Standard, no aliasing/enforced order beyond what Swift requires:
```swift
import Foundation
import Observation   // when @Observable is used directly (not just SwiftUI's re-export)
import SwiftUI
import SocketIO       // only in Services/SocketService.swift
```
No path aliases — Swift doesn't have them. Cross-module references are all `@testable import
StellarVolumiO` in tests, or plain type references in-target elsewhere.

## Error Handling

**No `throw`-based control flow in the store/service layer.** The dominant pattern is **tolerant
parsing with a diagnostic side channel**, not exceptions:

- `SocketService.lastDecodeError: String?` — set whenever an incoming payload fails to decode
  (wrong shape, missing dict, parser rejection), cleared on the next successful decode of the
  same or any event. Surfaced in Settings → `ConnectionStatusRow`/`DecodeErrorRow` as a
  diagnostic string, not thrown up the call stack.
- `SocketService.lastConnectionError: String?` — same pattern for transport-level failures,
  surfaced in `ContentView`'s "Can't reach backend" banner.
- Parsers are `init?(rawDict: [String: Any]) -> T?` — failable initializers, not throwing ones.
  `onRawDict` / `onRawDictNullable` treat a `nil` result as "parser rejected payload" and log to
  `lastDecodeError` rather than propagating an `Error`.
- `try?` is used to swallow errors that have a sane fallback (e.g.
  `try? config.setCustom(host:port:scheme:)` in `SocketService.connect`).
- **Defense-in-depth against force-unwraps that used to crash.** `SocketService.ensureInitialised()`
  has an explicit comment: never force-unwrap a URL built from user/discovered input — fall back
  to a hardcoded default (`"http://127.0.0.1:3000"`) that is guaranteed to parse, so a malformed
  host degrades to "wrong server" instead of a launch-time crash.
- **Optimistic UI + timeout-based reconciliation** is the pattern for anything that would
  otherwise wait on a round trip: `PlayerStore.applyOptimistic(_:)` sets local state immediately
  and starts a 2-second `Task` that clears it if the server never confirms — see
  `PlayerStore.swift:41-56`. `AirplayStore` and the seek/tick interpolators (`PlayerStore.tick`,
  `AirplayStore.tick`) follow the same "assume, then let server truth win" shape.

When adding a new socket-driven feature, follow this shape: a failable `init?(rawDict:)` parser on
the model, an `onXxx` wrapper on `SocketService`, and a store method that takes the parsed model
and updates `@Observable` state — never propagate a thrown error into view code.

## Concurrency

- **`@MainActor` isolation is used liberally** — most stores' async work explicitly hops with
  `Task { @MainActor [weak self] in ... }` rather than nested `MainActor.run` closures (see the
  comment in `PlayerStore.applyOptimistic` explaining why: the hop happens once at the top, `self`
  is read directly rather than re-captured by a nested `@Sendable` closure, avoiding a Swift 6
  concurrency error).
- **`[weak self]` on every long-lived `Task` and socket callback closure** — stores never
  strong-capture themselves in a callback that outlives the immediate call. This is also why
  `SocketService` is held **weakly** by stores (`bind(to:)`), which is the single most important
  gotcha for anyone writing tests — see TESTING.md.
- Time-based logic prefers **`ContinuousClock`/`ContinuousClock.Instant`** anchoring over
  accumulator loops (`PlayerStore.tick(now:)`) — accumulating fixed increments drifts under
  `Task.sleep` scheduling slop; anchoring against a monotonic instant self-corrects every call.

## Comments

Comments are a first-class part of this codebase's style — long, prose doc comments explaining
*why* a piece of code exists, what bug it fixes, and what would go wrong without it, are the norm
rather than the exception (see `SocketService.swift`, `PlayerStore.swift`,
`StellarVolumiOTests/Support/LayoutHosting.swift`, `StellarVolumiOUITests/ParitySweepTests.swift`
for dense examples). When writing new non-trivial logic, match this: state the failure mode being
prevented, not just the mechanism.

## Function Design

- Small, single-purpose methods on stores (`applyOptimistic`, `receiveServerState`, `tick`,
  `anchorSeek`) rather than one large "handle everything" method.
- View structs stay declarative and thin — business logic (deciding *what* to show) lives in
  stores/computed properties (`PlayerStore.currentTrackFormatBadges`,
  `PlayerStore.isPlaying`), not inline in `body`.
- Parameters favor explicit labels matching the domain vocabulary (`bind(to socket:)`,
  `tick(now:)`, `anchorSeek(_ milliseconds:, at instant:)`).

## Module Design

- **Exports:** everything in `StellarVolumiO/` is implicitly internal to the single app target;
  no public API surface to manage. Tests reach in via `@testable import StellarVolumiO`.
- **No barrel files.** Each type is imported by file-scoping through the module, not through a
  re-export aggregator.
- **Extensions used to group related functionality by concern**, not just to split large files —
  e.g. `SocketService` is one file but organized into extensions:
  `// MARK: - Transport Commands`, `// MARK: - Library + LCD Commands`,
  `// MARK: - AirPlay event surface`, `#if DEBUG … // MARK: - Test hooks`. Follow this pattern
  when adding a new command surface to `SocketService` rather than creating a new top-level type.
- **`#if DEBUG` test hooks live inside the production file they instrument**, not in a separate
  test-support target (`SocketService.swift`'s `simulateDecodeFailure`, `resetEmittedObjectCapture`,
  etc. are all guarded `#if DEBUG` at the bottom of the file). Follow this precedent for new
  test-observability hooks rather than adding a parallel mock type.

---

*Convention analysis: 2026-09-09*
