---
mapped: 2026-09-09
focus: arch
---

# Architecture — stellar-ios

## Pattern

Unidirectional, socket-driven. The Pi backend is the single source of truth;
the app is a thin remote that renders pushed state and emits intents.

```
Pi backend (Socket.IO :3000)
   │  pushState / pushAirplayState / pushLibraryAlbums / pushLcdStatus …
   ▼
SocketService  ── every callback hops to DispatchQueue.main.async ──┐
   ▲                                                                ▼
   │ emit("play" / "seek" / "lcd:set" …)                        @Observable Stores
   │                                                                ▼
   └──────────────────────── Views read via @Environment ───────── SwiftUI
```

## Layers

| Layer | Path | Contents |
|---|---|---|
| App | `StellarVolumiO/App/` | `StellarApp` (`@main`, DI root), `ContentView` (top-level nav) |
| Models | `StellarVolumiO/Models/` | `PlayerState`, `AirplayState`, `LibraryModels`, `LcdViewState`, `LastPlayedAlbum`, `IngestModels` — plain value types + `init(rawDict:)` parsers |
| Services | `StellarVolumiO/Services/` | `SocketService` (socket.io wrapper), `BackendDiscoveryService` (Bonjour `NWBrowser`) |
| Stores | `StellarVolumiO/Stores/` | 10 `@Observable` classes, one per domain |
| Views | `StellarVolumiO/Views/` | `NowPlaying/`, `Library/`, `Settings/` |
| Utils | `StellarVolumiO/Utils/` | `DesignTokens`, `DesignTokens+Redesign`, `StellarLogoView`, `AlbumArtCache`, `TapDebouncer` |

## Dependency injection

`StellarApp` owns **12** objects as `@State` and injects them all with
`.environment(...)` on `ContentView`:

`SocketService`, `BackendConfigStore`, `BackendDiscoveryService`, `PlayerStore`,
`AirplayStore`, `AlbumPickerStore`, `ArtistPickerStore`, `AlbumTracksStore`,
`LcdStore`, `LcdViewStore`, `LastPlayedStore`, `IngestStore`.

Views read them with `@Environment(SocketService.self) private var socket` etc.

Construction order matters: `BackendConfigStore` is built first because
`SocketService(config:)` takes it, keeping host/port/scheme resolution
coherent. `StellarApp.init()` re-creates the config store and re-seeds
`_backendConfig`/`_socketService` so both share one instance.

On `ContentView.onAppear`, `StellarApp` calls `bind(to: socketService)` on all
nine socket-consuming stores, then `socketService.connect()` and
`discovery.startDiscovery()`.

On `UIApplication.didBecomeActiveNotification` it calls
`socketService.reconnectIfNeeded()` and `requestAirplayState()`.

## Entry point / navigation — the part the iPad port rewrites

`App/ContentView.swift` is a `ZStack(alignment: .top)` containing:

1. A **`TabView`** with five tags in `enum Tab { player, library, lcd, vu, settings }`
2. A conditional **connection-failure banner** overlaid on top

### The action-only tab trick (critical for the port)

`.lcd` and `.vu` are **never actually selected**. `tabSelection` is a proxy
`Binding<Tab>` whose setter intercepts those two tags, performs
`lcd.setOn(!lcd.isOn)` / `lcdView.toggleVuMeter()`, and deliberately does *not*
write `selectedTab` — so the getter still returns the previous tab and TabView
snaps straight back. The user stays where they were and the LCD panel changes
in place. Their `tabItem` icons are state-driven
(`display`/`display.slash`, `waveform`/`waveform.slash`); the tab content is
`Color.clear`.

**This idiom has no `NavigationSplitView` equivalent.** A sidebar list has no
"tap and snap back" behaviour. On iPad these two must become explicit toggle
controls in the sidebar (or a sidebar bottom section), not navigation
destinations. This is the single largest structural decision in the port.

### Navigation surfaces (complete inventory)

| File | Line | Surface |
|---|---|---|
| `Views/Library/LibraryView.swift` | 16 | `NavigationStack` — the only stack in the Library tab |
| `Views/Library/LibraryView.swift` | 36 | `.navigationDestination(for: LibraryAlbum.self)` → `AlbumTracksView` |
| `Views/Library/AlbumPickerView.swift` | 17 | `NavigationLink(value: album)` |
| `Views/Library/ArtistPickerView.swift` | 10 | `NavigationLink(value: artist)` |
| `Views/Library/ArtistPickerView.swift` | 34 | `.navigationDestination(for: LibraryArtist.self)` → `ArtistDetailView` |
| `Views/Library/ArtistDetailView.swift` | 76 | `NavigationLink(value: album)` — reuses the outer album destination |
| `Views/Library/AlbumTracksView.swift` | 65 | `.navigationTitle(album.title)` |
| `Views/Library/ArtistDetailView.swift` | 62 | `.navigationTitle(artist.name)` |
| `Views/Settings/IngestSection.swift` | 19 / 120 | `.sheet` → `IngestSheet` wrapped in its own `NavigationStack` |
| `Views/Settings/BackendServerSection.swift` | 96 | `.sheet` → `BackendDiscoverySheet` |
| `Views/Settings/BackendDiscoverySheet.swift` | 21 / 42 | `NavigationStack` + `.toolbar` |

`NowPlayingView` and `SettingsView` have **no** NavigationStack of their own.

One shared `LibraryAlbum` destination serves both segments: the Albums grid
pushes directly, and the Artists path pushes through `ArtistDetailView`.

## Data flow example — seek

1. User drags `SeekBar` → `dragValue` tracks the finger (`state.seek` untouched).
2. On release: `NowPlayingView.onSeek` calls
   `player.applyOptimisticSeek(seconds * 1000)` (moves both `state.seek` and the
   interpolator anchor) then `socket.seek(to: seconds)`.
3. `SocketService.emit("seek", data: [seconds])` → `emit(_:with:completion:)`
   so the Int is sent as one bare argument, not nested in an array.
4. Backend seeks MPD, broadcasts `pushState`.
5. `PlayerStore.receiveServerState` reconciles and clears the optimistic value.

Seek is **dead-reckoned** between broadcasts — a 4 Hz `startSeekTicker()` task
projects the position, and the backend re-anchors on >2 s divergence or a 5 s
heartbeat. Clients must re-anchor, never accumulate per tick.

## Layout assumptions today

**No file branches on `horizontalSizeClass`, `verticalSizeClass`, or
`UIDevice.userInterfaceIdiom`.** The port is greenfield in that respect.

Already responsive (will reflow on iPad for free):
- `AlbumPickerView.swift:7` and `ArtistDetailView.swift:15` —
  `GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)`

Fixed frames that will look undersized or stranded on a 13" canvas:

| File | Line | Frame |
|---|---|---|
| `Views/Library/AlbumTracksView.swift` | 134 | `240 × 240` album hero |
| `Views/NowPlaying/AirplaySourceBadge.swift` | 64 | `width: 240` |
| `Utils/StellarLogoView.swift` | 25, 168 | `200 × 160`, `280 × 280` |
| `Views/Settings/SettingsView.swift` | 105, 108 | `51 × 31`, `27 × 27` — the hand-rolled LCD switch |
| `Views/Settings/BackendServerSection.swift` | 52, 80, 122, 152, 165, 181 | icon `22`, label gutters `64` |

Design tokens in `Utils/DesignTokens+Redesign.swift`:
`Stellar.Metric.artCornerRadius 16`, `playDisc 72`, `playGlyphOffset 2`,
`minTouchTarget 44`. `StellarGlassyBackground` paints two radial gradients with
absolute `endRadius: 280` — tuned for phone width, will look small on iPad.
