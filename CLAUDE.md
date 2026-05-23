# Stellar VolumiO — iOS App
# CLAUDE.md — Agent Context

## Project
A native SwiftUI iPhone app for controlling the Stellar Volumio Hi-Fi audio player running on a Raspberry Pi.

## Architecture
- **Language:** Swift 6 + SwiftUI
- **Target:** iOS 17+
- **State:** `@Observable` (Swift 5.9+ Observation framework — NOT `@StateObject/ObservableObject`)
- **Socket:** SocketIO-Client-Swift connecting to `stellar.local:3000`
- **Design:** MD3-inspired tokens in `Utils/DesignTokens.swift`

## File Structure
```
StellarVolumiO/
  App/           → StellarApp.swift, ContentView.swift
  Models/        → PlayerState.swift (all data models)
  Services/      → SocketService.swift (all socket + commands)
  Stores/        → PlayerStore.swift, AudioEngineStore.swift
  Views/
    NowPlaying/  → NowPlayingView.swift (hero screen)
    Queue/       → QueueView.swift
    Browse/      → BrowseView.swift
    Settings/    → SettingsView.swift
  Components/    → Shared reusable components
  Utils/         → DesignTokens.swift (all colours, fonts, shapes)
```

## Key Rules
- **Always use `@Observable`** — never `@StateObject` or `ObservableObject`
- **Environment injection** — all stores/services via `.environment()` in App, accessed with `@Environment` in views
- **Design tokens only** — never hardcode hex colours; use `Color.mdPrimary` etc. from DesignTokens.swift
- **Font sizes** — always use `StellarFont.*` tokens; never raw `.font(.system(size: N))`
- **Touch targets** — minimum 44×44pt for all interactive elements
- **Test on dark** — the app is dark-first; `preferredColorScheme(.dark)` is set globally

## Socket Events (Backend → App)
| Event | Payload | Description |
|---|---|---|
| `pushState` | `PlayerState` | Current playback state (emitted ~every 1s) |
| `pushQueue` | `[QueueItem]` | Queue contents |
| `pushAudioEngineState` | `AudioEngineState` | Which engine is active |
| `pushBrowseLibrary` | browse result | Library browse results |
| `pushLastPlayedAlbum` | `LastPlayedAlbum?` | Most-recent album (resume hydration); null on miss |

## Socket Commands (App → Backend)
| Command | Params | Description |
|---|---|---|
| `play` / `pause` / `stop` | — | Playback control |
| `toggle` | — | Play/pause toggle |
| `prev` / `next` | — | Track skip |
| `seek` | `Int` (seconds) | Seek to position |
| `volume` | `Int` (0–100) | Set volume |
| `mute` | — | Toggle mute |
| `setRandom` | `["value": Bool]` | Shuffle |
| `setRepeat` | `["value": Bool]` | Repeat |
| `switchAudioEngine` | `["engine": "mpd"/"audirvana"]` | Switch engine |
| `getState` | — | Request current state |
| `getQueue` | — | Request queue |
| `getAudioEngineState` | — | Request engine state |
| `library:lastPlayed:get` | — | Refetch last-played album (proactively pushed on connect) |
| `addPlay` | `["uri": String]` | Clear queue, add URI, and play (used to resume from last-played) |

## LastPlayedAlbum Payload
Backend persists in SQLite the most-recent album played (single row, keyed
on normalized `artist|album`). Pushed proactively in the connect-time batch
and on every album-boundary broadcast. Field shape (camelCase, matches
the Volumio2-UI frontend type):

```swift
struct LastPlayedAlbum: Codable {
    let artist: String
    let album: String
    let albumArt: String       // path or URL ('/albumart?path=...' shape)
    let trackUri: String       // URI of the track that triggered the record
    let trackType: String      // e.g. 'flac'
    let sampleRate: String     // raw Volumio samplerate ('96000', 'DSD64', …)
    let bitDepth: String       // raw Volumio bitdepth ('24')
}
```

Payload is `null` on miss (fresh backend, no albums played). iOS doesn't
consume this for v1 — but documenting the contract here keeps the iOS and
web clients aligned for when iOS gains an idle-resume surface.

## Phase 1 (Current)
- [x] Project scaffold
- [x] SocketService with Socket.IO v3
- [x] PlayerStore + AudioEngineStore
- [x] Now Playing screen (full featured)
- [x] Queue screen
- [x] Browse screen (stub tiles)
- [x] Settings screen
- [x] Connection overlay

## Phase 2 (Next)
- [ ] Browse: actual library navigation (albums, artists, playlists)
- [ ] Browse: NAS + Local Music folders
- [ ] mDNS auto-discovery (NWBrowser for `_volumio._tcp`)
- [ ] Apple Remote / lock screen controls (MPRemoteCommandCenter)
- [ ] Apple Music metadata (MusicKit fallback for missing album art)
- [ ] Audirvana now-playing (when backend exposes it)

## Build
Open `Package.swift` in Xcode 15+ or run:
```bash
xcodebuild -scheme StellarVolumiO -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## Test
```bash
xcodebuild test -scheme StellarVolumiOTests -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```
