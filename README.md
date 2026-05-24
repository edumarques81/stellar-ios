# stellar-ios

Native iPhone remote control for the [Stellar Volumio backend](https://github.com/edumarques81/stellar-volumio-audioplayer-backend) — a Go-based audio player running on a Raspberry Pi 5 with a 1920×440 LCD dashboard frontend.

The app is a deliberately minimal remote with **four** user-facing features:

1. **Transport** — play / pause / next / previous + drag-to-seek on the Now Playing tab.
2. **Album picker** — grid of local albums; tap one to play.
3. **Artist picker** — list of artists with avatars; drill into one to see their albums.
4. **LCD on/off toggle** — single switch in Settings that wakes or standbys the Pi LCD via the backend.

Anything beyond those four is intentionally out of scope (no playlists, no Qobuz/Tidal/Spotify UI, no theme picker, no search, no lock-screen controls). The backend is the source of truth; this app is a thin SocketIO client.

## Stack

- Swift 6 / SwiftUI
- iOS 17+ target
- `@Observable` (Observation framework) for state
- [SocketIO-Client-Swift](https://github.com/socketio/socket.io-client-swift) v16 (EIO3 to match the Stellar backend's Socket.IO v3)
- xcodegen — `project.yml` is the source of truth; `StellarVolumiO.xcodeproj` is generated

## Layout

```
StellarVolumiO/
  App/            StellarApp.swift, ContentView.swift
  Models/         PlayerState.swift, LibraryModels.swift
  Services/       SocketService.swift                       # the single Socket.IO client
  Stores/         PlayerStore, AlbumPickerStore, ArtistPickerStore, LastPlayedStore, LcdStore
  Views/
    NowPlaying/   NowPlayingView + Playing/Idle/Empty subviews + SeekBar / PlayPauseButton / FormatBadgeStrip
    Library/      LibraryView, AlbumPickerView, ArtistPickerView, ArtistDetailView
    Settings/     SettingsView                              # LCD toggle (Button-based; see "iOS 18 note" below)
  Utils/          DesignTokens, DesignTokens+Redesign, StellarFont, StellarLogoView
```

## Backend host

Hardcoded constant `defaultHost` at the top of `Services/SocketService.swift`. Currently `192.168.86.221:3000` (the Mac that hosts the Stellar backend). Edit that one line when the backend moves — there is intentionally no host-config UI.

## Build

```bash
# Simulator (iPhone 16 Pro — pin to UDID if you have multiple registered)
xcodebuild -scheme StellarVolumiO -destination 'platform=iOS Simulator,id=<udid>' build

# Or the convenience scripts:
scripts/build.sh                    # builds for the iPhone 16 Pro simulator
scripts/test.sh [SuiteName]         # runs unit tests on the simulator
scripts/deploy-to-device.sh         # builds, signs, installs, and launches on a paired iPhone
```

The deploy script regenerates the `.xcodeproj` via xcodegen, builds for device, and uses `devicectl` to install. If you add a new `.swift` file and only run `scripts/build.sh`, the project file won't pick it up — run `xcodegen generate --spec project.yml` first (or just use `scripts/deploy-to-device.sh`).

## Socket event contract

Aligned with the LCD frontend at [edumarques81/Volumio2-UI-for-lcd-pannel](https://github.com/edumarques81/Volumio2-UI-for-lcd-pannel) and the backend's `internal/transport/socketio/` package.

**Backend → iOS:** `pushState`, `pushQueue`, `pushLibraryAlbums`, `pushLibraryArtists`, `pushLibraryArtistAlbums`, `pushLastPlayedAlbum`, `pushLcdStatus`.

**iOS → backend:** `play`, `pause`, `toggle`, `stop`, `prev`, `next`, `seek [int]`, `getState`, `getQueue`, `getLcdStatus`, `library:albums:list`, `library:artists:list`, `library:artist:albums`, `replaceAndPlay {service, type, title, artist, albumart, uri}`, `lcdWake`, `lcdStandby`.

## iOS 18 note

The Settings LCD toggle is intentionally implemented as a `Button` wrapping a custom `Capsule + Circle` switch graphic rather than the native `Toggle`. iOS 18.3.1 has a SwiftUI bug where `Toggle` placed in certain HStack + NavigationStack + `.toolbarBackground(.visible, ...)` arrangements silently stops receiving taps even though it renders correctly. The Button alternative is verified to dispatch taps reliably and matches the native switch visual.

## Testing

```bash
scripts/test.sh                          # full unit-test suite
scripts/test.sh LcdStoreTests            # one suite
```

The package can't be tested with `swift test` directly — `@Observable` + UIKit-backed SwiftUI requires the iOS simulator destination. Use the script wrapper.

## Design + redesign docs

- `docs/superpowers/specs/2026-05-24-ios-remote-redesign-design.md` — visual + interaction spec
- `docs/superpowers/plans/2026-05-24-ios-remote-redesign-plan.md` — 36-task implementation plan (Phases 0-4 complete as of 2026-05-25)
- `CLAUDE.md` — scope, architecture rules, event contract for AI agents working on the codebase

## License

Personal project. Not currently licensed for redistribution.
