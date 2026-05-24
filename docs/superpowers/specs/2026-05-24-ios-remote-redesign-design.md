# iOS Remote Redesign — Design Spec

**Date:** 2026-05-24
**Repo:** `stellar-ios`
**Branch base:** `main` @ `296e6be`
**Status:** Design approved by user. Ready for plan-writing.

## Goal

Restyle the Stellar VolumiO iOS remote in place so that it (a) actually works — what's playing, transport, library — and (b) looks and feels like the current Volumio2-UI redesign rather than the old LCD code it was scaffolded from.

The user reported on 2026-05-24:

- Can't see what's currently playing.
- Play button doesn't change to pause.
- Library shows no albums or artists.
- Layout resembles the old LCD frontend, not the current redesign.
- Volume control is not wanted.

Diagnosis: the first three symptoms collapse into one root cause — `Services/SocketService.swift:82-95` silently swallows JSON decode errors, so a single field-shape mismatch in `pushState` / `pushLibraryAlbums` / `pushLibraryArtists` hides the whole event from the store. The fourth is a pure restyle.

## Scope

Keep the existing 17-file skeleton (post-strip-down baseline, commit `5971ce0`). Fix the decode swallow. Rewrite the three views with the redesign visual language (deep near-black background, gold `#d4af6a` accent, album-art hero, format badges, glassy gradients). Add a last-played idle state and a connection-status diagnostic in Settings.

### In scope

- Bottom tab bar: **Now Playing** · **Library** · **Settings**.
- Now Playing — playing state: album art hero · title/artist/album · format badges (FLAC + kHz + bit when known) · seek bar with draggable thumb + tabular timecodes · prev / play-pause / next.
- Now Playing — idle state (MPD stopped): last-played album from `pushLastPlayedAlbum` + single "Resume" CTA that emits `addPlay {trackUri}`.
- Now Playing — first-launch empty state: dim placeholder until first `pushState`.
- Library — segmented control Albums | Artists. Albums = grid of covers; tap → `replaceAndPlay`. Artists = list; tap → ArtistDetail screen showing that artist's albums; tap album → `replaceAndPlay`.
- Settings — vertical layout, in this order: (1) LCD on/off toggle, (2) connection-status row, (3) decode-error diagnostic row (hidden when `lastDecodeError == nil`).
- Tolerant per-event parsers for `pushState`, `pushLibraryAlbums`, `pushLibraryArtists`, `pushLibraryArtistAlbums`, `pushLastPlayedAlbum`.
- Surfaced decode errors via `SocketService.lastDecodeError` (observable string).
- Optimistic UI for play-pause, Resume, and LCD toggle (2-second reconciliation timeout).
- Connection lifecycle with 5-second disconnect grace period, mirroring the frontend.

### Out of scope

- Volume, shuffle, repeat, mute, Hi-Res Audio strip, source label (NAS/USB/LOCAL).
- Album track-list view (no `library:album:tracks` consumption).
- Library search.
- Favourites, playlists, queue editor.
- Audio-engine switching, Qobuz / Tidal / Spotify, theme picker.
- Toast / banner system, retry-with-backoff for socket emits.
- mDNS auto-discovery, lock-screen controls (MPRemoteCommandCenter), Bonjour Local Network entitlement.
- Host config UI — backend host remains a code constant (`defaultHost` in `SocketService.swift`).
- Pull-to-refresh in Library; offline mode; cross-launch local cache persistence.
- Cross-album track-list browsing; queue inspection.

## Architecture

### Navigation

`ContentView.swift` keeps its existing `TabView` shell. Three tabs:

1. **Now Playing** — `NowPlayingView` (thin shell that picks one of three subviews).
2. **Library** — `LibraryView` with a top segmented control.
3. **Settings** — `SettingsView`.

All views inherit `.preferredColorScheme(.dark)` from `StellarApp`. Touch targets remain 44×44pt minimum.

### Decode-bug fix — the core change

`Services/SocketService.swift:82-95` today reads:

```swift
} catch {
    // Silently ignore decode errors — backend shape may vary
}
```

Replace with:

1. **Surface the failure.** Each decode error populates `SocketService.lastDecodeError: String?` (observable) with a string like `"pushState: missing field 'seek'"`. The Settings tab renders this in muted red below the connection status row. No toast, no overlay — diagnostic-only.
2. **Per-event tolerant parsers.** Where the wire shape isn't trivially `Decodable`, replace the auto-derived `Decodable` with a hand-written `init(rawDict: [String: Any])` that mirrors `Volumio2-UI/src/lib/components/redesign/playerStateParsers.ts`. Each parser ≤40 lines. The events that need parsers in v1:
   - `PlayerState` — `seek` (ms vs seconds), `duration` (string vs int), `samplerate` (free-text), `status` (string-to-enum).
   - `LibraryModels` — pushLibraryAlbums/Artists/ArtistAlbums envelope variations.
   - `LastPlayedAlbum` — straightforward but matches the backend payload exactly.

`SocketService.on<T: Decodable>` is retained for events where the auto-decoder still works (`pushLcdStatus` is the main one). For the tolerant-parsed events, a sibling method `onRawDict<T>(_ event: String, parser: ([String: Any]) -> T?)` extracts the first element of the `[Any]` payload as a dict and runs the parser, populating `lastDecodeError` on `nil`.

### File-structure deltas

Additions under `StellarVolumiO/`:

```
Stores/
  + LastPlayedStore.swift           // consumes pushLastPlayedAlbum
Models/
  + LastPlayedAlbum.swift           // matches backend payload
  + PlayerState+Parser.swift        // tolerant parser
  + LibraryModels+Parser.swift      // tolerant parsers for library events
Views/
  NowPlaying/
    + NowPlayingPlayingView.swift   // extracted "playing" subview
    + NowPlayingIdleView.swift      // extracted "last played + Resume" subview
    + NowPlayingEmptyView.swift     // first-launch placeholder
    + FormatBadgeStrip.swift        // reusable badge row
    + SeekBar.swift                 // extracted seek bar (testable in isolation)
    + PlayPauseButton.swift         // stable Circle + symbolEffect glyph swap
  Library/
    + ArtistDetailView.swift        // promoted from inline
  Settings/
    + ConnectionStatusRow.swift     // socket-state + decode-error diagnostic
Utils/
  + DesignTokens+Redesign.swift     // gold accent, glassy gradients, badge styles
```

Existing files modified (not rewritten): `ContentView.swift`, `Services/SocketService.swift`, `Stores/PlayerStore.swift`, `Stores/AlbumPickerStore.swift`, `Stores/ArtistPickerStore.swift`, `Stores/LcdStore.swift`, `Models/PlayerState.swift`, `Models/LibraryModels.swift`, `Views/NowPlaying/NowPlayingView.swift`, `Views/Library/LibraryView.swift`, `Views/Library/AlbumPickerView.swift`, `Views/Library/ArtistPickerView.swift`, `Views/Settings/SettingsView.swift`, `Utils/DesignTokens.swift`.

`App/StellarApp.swift` gains the `LastPlayedStore` in its environment injection. No other top-level wiring changes.

### Visual language

Direct port of the Volumio2-UI redesign tokens to Swift constants in `DesignTokens+Redesign.swift`:

- Background: `#050507` base + the two radial gradients from `PlayerLayout.svelte:60-65`.
- Gold accent: `#d4af6a`. Used for the play disc, format badges, the progress fill, the gold tab-bar tint, the Resume CTA.
- Format badges: gold-on-`rgba(212,175,106,0.18)` capsules, 9pt label, semibold.
- Album-art hero: 78% screen width, aspect 1:1, 16pt corner radius, soft drop shadow `0 8px 28px rgba(0,0,0,.5)`.
- Play disc: 72×72pt Circle, gold fill, 30pt SF Symbol, 2pt x-offset on `play.fill` to optically centre the triangle. `contentTransition(.symbolEffect(.replace.downUp))` for the glyph swap. The Circle is a sibling of the Image in a ZStack so it provably doesn't translate on state change.
- Tab-bar tint: gold for active, `mdOnSurfaceVariant` for inactive.

No hex literals outside `DesignTokens+Redesign.swift`. All views consume tokens via `Color.md*` / `StellarFont.*` shorthands.

### Data flow

| View | Reads | Writes |
| --- | --- | --- |
| `NowPlayingPlayingView` | `PlayerStore.state` | `socket.playPause()`, `prev()`, `next()`, `seek(to:)` |
| `NowPlayingIdleView` | `LastPlayedStore.album` | `socket.emitObject("addPlay", {uri: album.trackUri})` |
| `NowPlayingEmptyView` | — | — |
| `AlbumPickerView` | `AlbumPickerStore.albums` | `socket.emitObject("replaceAndPlay", ...)` |
| `ArtistPickerView` | `ArtistPickerStore.artists` | navigate to `ArtistDetailView` |
| `ArtistDetailView` | `ArtistPickerStore.selectedArtistAlbums` | `socket.emitObject("replaceAndPlay", ...)` |
| `SettingsView` | `LcdStore.status`, `SocketService.connectionState`, `SocketService.lastDecodeError` | `socket.lcdWake()` / `lcdStandby()` |

All stores remain `@Observable`, environment-injected from `StellarApp`.

### Idle vs Playing decision

`NowPlayingView` body:

```swift
if player.hasTrack && player.state.status != .stop {
    NowPlayingPlayingView()
} else if let last = lastPlayed.album {
    NowPlayingIdleView(album: last)
} else {
    NowPlayingEmptyView()
}
```

`hasTrack` = `!state.title.isEmpty`. The empty branch only matters on a fresh backend with no playback history.

### Optimistic UI

`PlayerStore` gains `optimisticStatus: PlayerStatus?`. The play-pause button toggles it locally on tap; `pushState` clears it (`server is authoritative`). `isPlaying` resolves as `optimisticStatus.map { $0 == .play } ?? (state.status == .play)`. A 2-second `Task.sleep` clears the optimistic value if no `pushState` arrives, so the UI never lies indefinitely.

Same pattern for the idle `Resume` CTA (optimistic `playing`) and the LCD toggle (optimistic `on`/`off`, reconcile on `pushLcdStatus`).

### Library load lifecycle

- `LibraryView.onAppear` once per app session: `AlbumPickerStore.loadIfEmpty()`, `ArtistPickerStore.loadIfEmpty()`.
- Segment switch: free (both lists cached in memory).
- Artist tap: `ArtistPickerStore.select(artist)` emits `library:artist:albums`. Result cached by artist name; re-tap is instant.
- No pull-to-refresh in v1.

### LastPlayed lifecycle

- Backend pushes `pushLastPlayedAlbum` on connect and on every album-boundary transition. `LastPlayedStore` listens and holds.
- The payload can be `null` on a fresh backend with no playback history — `LastPlayedStore.album` is `LastPlayedAlbum?` and the parser must accept a JSON null without populating `lastDecodeError`. In that state, `NowPlayingEmptyView` renders.
- Never auto-play on receive. Only the Resume CTA triggers playback.

### Connection lifecycle

| State | Visible effect |
| --- | --- |
| `.connecting` (first connect) | Tabs render, data is empty, status row shows amber spinner "Connecting…" |
| `.connected` | Green dot + host. `getState` / `getQueue` / `getLcdStatus` fire on connect. `pushLastPlayedAlbum` arrives unprompted. |
| `.disconnected` after 5s grace | Red dot + "Disconnected". Stale data stays on screen. |
| `.error(reason)` | Red dot + truncated reason text. |
| Reconnect | Auto via SocketIO config (`.reconnects(true)`, max wait 10s). On reconnect → re-emit the connect batch. |

5-second grace mirrors the frontend's `DISCONNECT_GRACE_PERIOD_MS`.

## Error handling

| Failure mode | Behaviour |
| --- | --- |
| JSON decode error | `SocketService.lastDecodeError` populated. Settings row renders in muted red. Other stores unaffected. |
| `replaceAndPlay` ignored by backend | No UI rollback. Tile shows a 1.5s "Sent" overlay then dismisses. Verification is via Now Playing tab. |
| Optimistic UI timeout (2s) | Button reverts silently to server-truth value. Visible reversion is the signal — no banner. |
| LCD toggle ignored (no `pushLcdStatus` within 2s) | Toggle bounces back to last known state. |
| Socket disconnect | Stale data stays. After 5s grace, status row turns red. No blocking overlay. |
| Socket emit during disconnect | Dropped by SocketIO. No retry queue. |

No toast/banner infrastructure is added. No retry-with-backoff at the application layer.

## Testing

`XCTest` only — no third-party test frameworks.

| Layer | Test |
| --- | --- |
| `PlayerState+Parser` | Table tests over wire-shape variations: `seek` as ms vs seconds, `duration` as string vs int, `samplerate` as `"96000"` / `"DSD64"` / empty, missing optional fields, status string-to-enum coverage. Lift fixtures from the Volumio2-UI parser tests. |
| `LibraryModels+Parser` | Same for `pushLibraryAlbums` / `pushLibraryArtists` / `pushLibraryArtistAlbums`. |
| `LastPlayedAlbum` parser | Real backend payload + null payload. |
| `PlayerStore` | Optimistic `optimisticStatus` clears on `pushState`. 2s timeout fires and clears. `isPlaying` resolves correctly under both. |
| `LastPlayedStore` | Receives album, holds it, replaces on next broadcast. Null payload doesn't crash. |
| `SocketService.lastDecodeError` | Malformed payload populates it with event-name + field path. Subsequent valid payload clears it. |
| `ConnectionStatusRow` | 5s disconnect grace before red dot. Reconnect mid-grace clears without flicker. |
| `AlbumPickerStore` / `ArtistPickerStore` | `loadIfEmpty()` is idempotent. Selection cache hits don't re-emit. |

**Fixtures.** `StellarVolumiOTests/Fixtures/` holds real JSON payloads captured from the live Mac backend. Realism over synthetic shapes — the bug we're fixing was specifically about wire-shape mismatches.

**No SwiftUI snapshot tests.** They break on every Swift/SwiftUI release and don't pay back the maintenance cost on a 3-screen app.

**Smoke verification** after each meaningful change:

- `xcodebuild -scheme StellarVolumiO -destination 'platform=iOS Simulator,id=<udid>'` → must succeed.
- `xcodebuild test -scheme StellarVolumiOTests -destination ...` → all green.
- LAN deploy via `scripts/deploy-to-device.sh` → app launches on the iPhone, taps round-trip to the Mac backend at `192.168.86.221:3000`.

## Manual UAT (end-of-implementation checklist)

These mirror the existing `stellar-ios/CLAUDE.md` "Verifying against the live backend" recipe, extended for the new behaviours.

1. **Now Playing — playing.** Start an album from the Library tab. Verify the Now Playing tab shows correct title/artist/album, format badges (FLAC + kHz + bit), live seek bar, and the play disc is in pause-glyph state.
2. **Play/pause stability.** Tap the disc 10 times rapidly. The Circle must not visually shift; only the glyph morphs. State converges to the server's truth on each `pushState`.
3. **Now Playing — idle.** Stop MPD. Verify the tab switches to "Last Played" with the previous album's art + title + Resume CTA. Tap Resume → playback starts.
4. **Now Playing — empty.** On a fresh backend (no `pushLastPlayedAlbum` yet), confirm the empty-state placeholder renders without crashing.
5. **Library — Albums.** Open Library, Albums segment. Grid populates with all local albums (was 72 last sweep). Tap one → playback starts; Pi LCD switches to that album.
6. **Library — Artists.** Switch to Artists segment. List populates (was 41 last sweep). Tap one → drill into their albums. Tap an album → playback starts.
7. **Settings — LCD.** Toggle off → Pi LCD goes dark within ~1s. Toggle on → LCD wakes.
8. **Settings — connection status.** Stop the Mac backend. After 5s, the row turns red with "Disconnected". Restart backend. Row turns green again.
9. **Settings — decode diagnostic.** Send a malformed payload from a tap-script (or manually corrupt a backend response in a dev branch). The diagnostic row populates. Send a valid payload — row clears.

## Risks & mitigations

| Risk | Mitigation |
| --- | --- |
| Wire-shape parsers drift from backend payload | Pull real-world fixtures into the test suite; whenever the backend changes a payload, the parser test must be updated in the same PR. |
| Optimistic UI desynchronises on flaky network | 2s reconciliation timeout enforces eventual consistency; visible reversion is acceptable. |
| `LastPlayedStore` shows a stale album the user can't actually play (e.g. NAS unmounted) | Resume CTA emits `addPlay` and waits for `pushState`. If MPD errors back via `pushToastMessage` (not consumed in v1), the optimistic state times out and reverts. Logged as a follow-up — not a v1 blocker. |
| Connection grace period masks a real outage | Same grace as the frontend; if 5s is wrong for iOS, the constant lives in one place (`SocketService`) and can be tuned. |
| Tab-bar overlap on the smallest iPhone screen | Bottom padding 24pt + `contentMargins(.bottom, 16, for: .scrollContent)` on the Now Playing scroll view guarantees clearance on iPhone SE (3rd gen). |
| SwiftUI symbol-replace transition unsupported pre-iOS 17 | App already targets iOS 17+ per `Package.swift`. |

## Open questions deferred to plan-writing

None — design is locked.

## References

- `stellar-ios/CLAUDE.md` — current scope, design tokens, event contract.
- `Volumio2-UI/src/lib/components/redesign/` — design language source.
- `Volumio2-UI/src/lib/components/redesign/playerStateParsers.ts` — parser logic to port.
- `Volumio2-UI/CLAUDE.md` — full Socket.IO event contract, `pushLastPlayedAlbum` payload spec, 5s grace period.
- `stellar-volumio-audioplayer-backend/internal/transport/socketio/` — backend handlers.
- MemPalace: `feedback_subagent_driven_execution` (per-phase, `/clear` between heavy steps), `reference_svelte5_export_function_testability` (relevant to parser-test patterns).
