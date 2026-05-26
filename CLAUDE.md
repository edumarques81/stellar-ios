# Stellar VolumiO — iOS App
# CLAUDE.md — Agent Context

## Scope

This app is a **minimal remote control** for the Stellar backend. It has exactly six user-facing features and nothing else:

1. **Transport** — play / pause / next / previous + volume + seek (Now Playing tab).
2. **Album picker → tap → Album Tracks (Play Album CTA + per-track play)** — Library tab → Albums shows a grid of all local albums; tap a tile to push the Album Tracks screen (cover + title + artist + full-width gold "Play Album" CTA + track list). Tap "Play Album" to play the whole folder; tap any track row to start playback at that track.
3. **Artist picker** — list of artists, drill into one to see their albums; tap an album to push the same Album Tracks screen described above (Library tab → Artists).
4. **LCD on/off toggle** — single switch in Settings that wakes or standbys the Pi LCD via the backend.
5. **Backend server selection** — auto-discover via Bonjour (`_stellar._tcp`) or enter host/port manually (Settings tab → "Backend Server" section).
6. **AirPlay source mode** — when the Pi's `shairport-sync` receiver is mid-session (iPhone streaming via AirPlay), the Now Playing tab swaps to display the AirPlay session info (title / artist / album / cover / sender device) with a gold "AIRPLAY · <sender>" badge. Transport buttons proxy DACP play / pause / next / prev to the iPhone via the backend; seek and the format strip are suppressed (DACP doesn't expose seek; AirPlay 1 is fixed 44.1kHz/16-bit). The branch is driven by `pushAirplayState` / `pushAirplayEnded` events on the same Socket.IO channel — no MPD fields are involved.

Anything beyond this is explicitly out of scope: no favourites, no playlists, no queue editor, no audio-engine switching, no Qobuz / Tidal / Spotify, no theme picker, no settings dashboard, no search, no lock-screen controls.

If a feature request lands here that doesn't fit the six above, push back.

## Architecture

- **Language:** Swift 6 + SwiftUI
- **Target:** iOS 17+
- **State:** `@Observable` (Observation framework — NOT `@StateObject` / `ObservableObject`)
- **Transport:** SocketIO-Client-Swift v16, Socket.IO v3 / EIO3 (matches the backend).
- **Backend host:** resolved at runtime by `Stores/BackendConfigStore.swift` from a three-tier fallback chain — custom (Settings → Manual entry) → discovered (`Services/BackendDiscoveryService.swift` + Bonjour `_stellar._tcp`) → default `192.168.86.221:3000`. `SocketService` consumes the store via init injection and rebuilds the SocketManager whenever the resolved endpoint changes. The previous hardcoded constant is gone — change the default by editing `BackendConfigStore.defaultHost` (only needed when the bundled fallback ever moves).

## File Structure

```
StellarVolumiO/
  App/            StellarApp.swift, ContentView.swift (incl. connection-failure banner)
  Models/         PlayerState.swift, LibraryModels.swift, AirplayState.swift
  Services/       SocketService.swift, BackendDiscoveryService.swift
  Stores/         PlayerStore, AirplayStore, AlbumPickerStore, ArtistPickerStore, AlbumTracksStore,
                  LcdStore, LastPlayedStore, BackendConfigStore
  Views/
    NowPlaying/   NowPlayingView.swift          (transport tab, MPD + AirPlay branches),
                  NowPlayingPlayingView.swift   (source-neutral renderer over NowPlayingDisplayState),
                  AirplaySourceBadge.swift      (gold "AIRPLAY · <sender>" pill)
    Library/      LibraryView, AlbumPickerView, ArtistPickerView, AlbumTracksView
    Settings/     SettingsView.swift            (LCD toggle + Backend Server section),
                  BackendServerSection.swift, BackendDiscoverySheet.swift,
                  ConnectionStatusRow.swift, DecodeErrorRow.swift
  Utils/          DesignTokens.swift, StellarLogoView.swift
```

## Key Rules

- **Always use `@Observable`** — never `@StateObject` / `ObservableObject`.
- **Environment injection** — stores/services are injected via `.environment()` in `StellarApp`, consumed with `@Environment` in views.
- **Design tokens** — use `Color.md*` (e.g. `Color.mdPrimary`) and `.foregroundStyle(.mdOnSurface)` shorthands. Both resolve via `DesignTokens.swift`. Never hardcode hex.
- **Font sizes** — use `StellarFont.*` tokens.
- **Touch targets** — 44×44pt minimum.
- **Dark first** — `.preferredColorScheme(.dark)` is set globally.

## Socket Event Contract

Aligned with `Volumio2-UI/CLAUDE.md` (frontend) and `stellar-volumio-audioplayer-backend/internal/transport/socketio/`.

> **Host/port note:** The socket URL no longer comes from a code constant. `SocketService.ensureInitialised()` reads `host` / `port` / `scheme` from the injected `BackendConfigStore` on every call, so any change in the store (Settings → Save, Bonjour discovery accepted, etc.) tears down the underlying manager and rebuilds it against the new endpoint.

### Listen for (backend → iOS)

| Event | Payload | Why iOS cares |
|---|---|---|
| `pushState`               | `PlayerState`              | Update Now Playing UI (MPD source) |
| `pushQueue`               | `[QueueItem]`              | (consumed by PlayerStore for queue position) |
| `pushLibraryAlbums`       | `PushLibraryAlbums`        | Populate Album picker |
| `pushLibraryArtists`      | `PushLibraryArtists`       | Populate Artist picker |
| `pushLibraryArtistAlbums` | `PushLibraryArtistAlbums`  | Populate artist drill-down |
| `pushLibraryAlbumTracks`  | `PushLibraryAlbumTracks`   | Populate Album Tracks screen (tracks + totalDuration; `error` field surfaces failure) |
| `pushLcdStatus`           | `LcdStatus`                | Reconcile LCD toggle |
| `pushAirplayState`        | `AirplayState`             | Swap Now Playing to AirPlay-source UI; carries title/artist/album/sender/coverDataURL/seek/duration/canControl/sessionID |
| `pushAirplayEnded`        | `AirplayEnded`             | Clear AirPlay UI (only if sessionID matches the currently displayed session — guards against stale ends wiping fresh sessions) |

### Emit (iOS → backend)

| Event | Payload | Source |
|---|---|---|
| `play`, `pause`, `toggle`, `stop`, `prev`, `next` | — | NowPlayingView buttons |
| `seek` | `[Int seconds]` | NowPlayingView seek bar |
| `volume` | `[Int 0-100]` | NowPlayingView volume slider |
| `mute` | — | (toggle helper, not in UI yet) |
| `getState`, `getQueue`, `getLcdStatus` | — | Sent on connect |
| `library:albums:list` | `{scope, sort, limit, offset, query?}` | AlbumPickerStore.load() |
| `library:artists:list` | `{scope, sort, limit, offset}` | ArtistPickerStore.load() |
| `library:artist:albums` | `{artist}` | ArtistPickerStore.select() |
| `library:album:tracks` | `{album, albumArtist?, uri?}` | AlbumTracksStore.load() (drill-in to Album Tracks) |
| `replaceAndPlay` | `{service, type, title, artist, albumart, uri}` | Play Album CTA (type=folder) + per-track tap (type=song) |
| `lcdWake`, `lcdStandby` | — | Settings toggle |

## Build

```bash
xcodebuild -scheme StellarVolumiO -destination 'platform=iOS Simulator,id=<sim-id>'
```

The simulator id can be looked up with `xcrun simctl list devices`. There are sometimes multiple iPhone 16 Pro entries — pin to a specific UDID rather than the device name.

## Verifying against the live backend

The app talks to the Mac stellar backend at `192.168.86.221:3000`. To smoke-test on a simulator/device on the same LAN:

1. Confirm Mac stellar is running: `lsof -nP -iTCP:3000 -sTCP:LISTEN`.
2. Build + launch the app.
3. In **Now Playing** tab: tap play, the Mac log at `~/Library/Logs/stellar-backend.err.log` should show `Play` / `Next` / `Prev` / `Seek` events.
4. In **Library → Albums**: list should populate (was 72 albums last sweep). Tap one → Album Tracks screen pushes with cover + tracks. Tap "Play Album" → whole album plays + Pi LCD switches. Tap any single track row → that one track plays.
5. In **Library → Artists**: list should populate (was 41 artists). Tap one → drill-down shows that artist's albums. Tap an album → Album Tracks screen pushes (same as #4).
6. In **Settings → LCD screen**: toggle off → Pi LCD goes dark within ~1s. Toggle on → LCD wakes.

## What's intentionally absent

- No Settings dashboard beyond the LCD toggle.
- No Audirvana / Qobuz / Tidal integration code.
- No theme picker (the colour system has a fixed "rose" palette by default; you can change it by writing `UserDefaults.standard.set("darkForest", forKey: "colorTheme")` in code, but there is no UI for it).
- No queue editor.
- No favourites.

If any of these come back, they'd need a new spec discussion first.
