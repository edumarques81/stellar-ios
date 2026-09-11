---
mapped: 2026-09-09
focus: quality
---

# Conventions — stellar-ios

## Hard rules (violating these is a review failure)

1. **`@Observable` only.** Never `ObservableObject` / `@Published` / `@StateObject`.
   Stores are `@Observable final class`, injected with `.environment(...)`, read
   with `@Environment(Type.self)`.
2. **Design tokens, never literals.** Colours via `Stellar.Color.*`, fonts via
   `StellarFont.*`, metrics via `Stellar.Metric.*`. Adding a raw hex or a magic
   font size is drift.
3. **44 × 44 pt minimum touch targets** (`Stellar.Metric.minTouchTarget`).
4. **Run `xcodegen generate --spec project.yml` after adding any `.swift` file.**
   `scripts/build.sh` does not do it for you.
5. **Conventional commits:** `<type>(<scope>): <description>` —
   `feat`, `fix`, `docs`, `refactor`, `test`, `chore`.
   Scope for this work is `ios` or a subsystem, e.g. `feat(ipad): …`.
6. **Commit *and push* at every phase boundary.** Never batch.

## Code style

- Types are `final class` (stores/services) or `struct` (models/views).
- Models parse defensively from socket payloads via `init(rawDict: [String: Any])`
  returning `nil` on malformed input — the parser rejects, the store ignores.
- Views are decomposed aggressively: `NowPlayingView` dispatches to
  `NowPlayingPlayingView` / `NowPlayingIdleView` / `NowPlayingEmptyView`;
  `SettingsView` is assembled from `*Section` subviews.
- Private helpers live in `// MARK: -` sections at the bottom of the type.
- Doc comments explain **why**, and are unusually dense in this repo — they
  frequently record a past bug and the reason for the current shape. Match that
  density; a non-obvious workaround without a comment will be flagged.

## Concurrency

- Stores are **not** `@MainActor`-annotated, but are main-confined in practice:
  `SocketService` delivers every callback through `DispatchQueue.main.async`.
- Async hops use `Task { @MainActor [weak self] in … }` — the whole task body is
  isolated. Do **not** reintroduce `await MainActor.run { self?.x }`; the nested
  `@Sendable` closure re-captures the weak `self` var and warns under Swift 6.
- Long-running tickers are stored as `Task<Void, Never>?` and cancelled in
  `deinit`. `startX()` guards `guard task == nil else { return }` so repeat
  calls are safe.
- `BackendDiscoveryService` is `@unchecked Sendable`: every property is either
  `@MainActor`-isolated or touched only inside `browserQueue.async`. Anything
  added there must keep to one of those two domains.

## Error handling

- Socket decode failures are surfaced, not swallowed: `SocketService.lastDecodeError`
  is set on the main queue and rendered by `Views/Settings/DecodeErrorRow.swift`.
- Connection failures show a non-blocking banner in `ContentView` with Retry and
  Server Settings actions, gated on a grace period (`ConnectionGraceTests`).
- Optimistic UI state (`PlayerStore.optimisticStatus`) always carries a 2 s
  timeout so a missing server push cannot lie to the UI forever.

## Scope discipline

The app is deliberately limited to **six features**: transport; album picker →
album tracks; artist picker → artist albums → album tracks; LCD on/off toggle;
backend server selection; AirPlay source mode.

Out of scope, do not add: favourites, playlists, queue editor, audio-engine
switching, streaming services, theme picker, search, lock-screen controls.

**Volume is deliberately absent from the UI.** `SocketService.setVolume` and
`toggleMute` exist with no call sites and must be **kept** — the user may revisit
volume later, but no volume is to be applied to the bit-perfect audio path.
Do not "clean up" these methods.
