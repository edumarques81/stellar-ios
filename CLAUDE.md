# Stellar VolumiO — iOS App
# CLAUDE.md — Agent Context

## Scope

This app is a **minimal remote control** for the Stellar backend. It has exactly four user-facing features and nothing else:

1. **Transport** — play / pause / next / previous + volume + seek (Now Playing tab).
2. **Album picker** — list of all local albums; tap one to play (Library tab → Albums).
3. **Artist picker** — list of artists, drill into one to see their albums; tap an album to play (Library tab → Artists).
4. **LCD on/off toggle** — single switch in Settings that wakes or standbys the Pi LCD via the backend.

Anything beyond this is explicitly out of scope: no favourites, no playlists, no queue editor, no audio-engine switching, no Qobuz / Tidal / Spotify, no theme picker, no settings dashboard, no search, no mDNS auto-discovery, no lock-screen controls.

If a feature request lands here that doesn't fit the four above, push back.

## Architecture

- **Language:** Swift 6 + SwiftUI
- **Target:** iOS 17+
- **State:** `@Observable` (Observation framework — NOT `@StateObject` / `ObservableObject`)
- **Transport:** SocketIO-Client-Swift v16, Socket.IO v3 / EIO3 (matches the backend).
- **Backend host:** hardcoded constant `defaultHost` at the top of `Services/SocketService.swift`. Currently `192.168.86.221:3000` (the Mac that hosts stellar-backend post-M1.C). Edit that one line when the backend moves.

## File Structure

```
StellarVolumiO/
  App/            StellarApp.swift, ContentView.swift
  Models/         PlayerState.swift, LibraryModels.swift
  Services/       SocketService.swift
  Stores/         PlayerStore, AlbumPickerStore, ArtistPickerStore, LcdStore
  Views/
    NowPlaying/   NowPlayingView.swift          (transport tab)
    Library/      LibraryView, AlbumPickerView, ArtistPickerView
    Settings/     SettingsView.swift            (LCD toggle only)
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

### Listen for (backend → iOS)

| Event | Payload | Why iOS cares |
|---|---|---|
| `pushState`               | `PlayerState`              | Update Now Playing UI |
| `pushQueue`               | `[QueueItem]`              | (consumed by PlayerStore for queue position) |
| `pushLibraryAlbums`       | `PushLibraryAlbums`        | Populate Album picker |
| `pushLibraryArtists`      | `PushLibraryArtists`       | Populate Artist picker |
| `pushLibraryArtistAlbums` | `PushLibraryArtistAlbums`  | Populate artist drill-down |
| `pushLcdStatus`           | `LcdStatus`                | Reconcile LCD toggle |

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
| `replaceAndPlay` | `{service, type, title, artist, albumart, uri}` | Tap an album to play |
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
4. In **Library → Albums**: list should populate (was 72 albums last sweep). Tap one → playback starts; Pi LCD switches to that album.
5. In **Library → Artists**: list should populate (was 41 artists). Tap one → drill-down shows that artist's albums. Tap an album → playback starts.
6. In **Settings → LCD screen**: toggle off → Pi LCD goes dark within ~1s. Toggle on → LCD wakes.

## What's intentionally absent

- No Settings dashboard beyond the LCD toggle.
- No Audirvana / Qobuz / Tidal integration code.
- No theme picker (the colour system has a fixed "rose" palette by default; you can change it by writing `UserDefaults.standard.set("darkForest", forKey: "colorTheme")` in code, but there is no UI for it).
- No queue editor.
- No favourites.
- No host config UI — host is a code constant. This is deliberate.

If any of these come back, they'd need a new spec discussion first.
