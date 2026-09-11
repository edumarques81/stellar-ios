---
mapped: 2026-09-09
focus: arch
---

# Structure — stellar-ios

## Repo root

```
stellar-ios/
├── project.yml                 # xcodegen spec — the build's source of truth
├── Package.swift               # Swift package dependencies
├── StellarVolumiO.xcodeproj/   # GENERATED — never hand-edit
├── StellarVolumiO/             # app sources (45 .swift files)
├── StellarVolumiOTests/        # XCTest unit tests (25 files + Fixtures/)
├── scripts/                    # build.sh, test.sh, deploy-to-device.sh
├── docs/                       # app-store-publish-checklist.md, etc.
└── .planning/                  # GSD planning artefacts (this map)
```

## Source layout

```
StellarVolumiO/
├── App/
│   ├── StellarApp.swift            @main, owns + injects 12 objects
│   └── ContentView.swift           TabView (5 tags) + failure banner
├── Models/
│   ├── PlayerState.swift           init(rawDict:) parser
│   ├── AirplayState.swift
│   ├── LibraryModels.swift         LibraryAlbum, LibraryArtist
│   ├── LcdViewState.swift
│   ├── LastPlayedAlbum.swift
│   └── IngestModels.swift
├── Services/
│   ├── SocketService.swift         socket.io wrapper, lazy-init, DEBUG capture
│   └── BackendDiscoveryService.swift  NWBrowser _stellar._tcp
├── Stores/                         10 @Observable stores
│   ├── PlayerStore.swift           transport + dead-reckoned seek ticker
│   ├── AirplayStore.swift          AirPlay session + 1 Hz ticker
│   ├── AlbumPickerStore.swift
│   ├── ArtistPickerStore.swift
│   ├── AlbumTracksStore.swift
│   ├── LcdStore.swift              panel on/off
│   ├── LcdViewStore.swift          VU meter vs normal view
│   ├── LastPlayedStore.swift
│   ├── BackendConfigStore.swift    host/port resolution, defaultHost stellar.local
│   └── IngestStore.swift
├── Views/
│   ├── NowPlaying/                 NowPlayingView + Playing/Idle/Empty branches,
│   │                               SeekBar, PlayPauseButton, FormatBadgeStrip,
│   │                               AirplaySourceBadge
│   ├── Library/                    LibraryView (segmented), AlbumPickerView,
│   │                               ArtistPickerView, ArtistDetailView,
│   │                               AlbumTracksView, CachedAsyncImage
│   └── Settings/                   SettingsView, BackendServerSection,
│                                   BackendDiscoverySheet, ConnectionStatusRow,
│                                   DecodeErrorRow, IngestSection
└── Utils/
    ├── DesignTokens.swift          Stellar.Color, StellarFont
    ├── DesignTokens+Redesign.swift Stellar.Metric, Shadow, StellarGlassyBackground
    ├── StellarLogoView.swift
    ├── AlbumArtCache.swift         shared URLCache configuration
    └── TapDebouncer.swift
```

## Naming conventions

| Kind | Pattern | Example |
|---|---|---|
| Store | `<Domain>Store` | `AlbumTracksStore` |
| Service | `<Domain>Service` | `BackendDiscoveryService` |
| View | `<Noun>View` | `ArtistDetailView` |
| Sheet | `<Noun>Sheet` | `BackendDiscoverySheet` |
| Section | `<Noun>Section` | `IngestSection` |
| Test | `<Subject>Tests` | `PlayerStoreSeekTests` |
| Token namespace | `Stellar.Color.*`, `Stellar.Metric.*`, `StellarFont.*` | |

Tests live in one flat `StellarVolumiOTests/` directory (no mirrored subdirs),
plus a `Fixtures/` folder for sample payloads.

## Where iPad work will land

| Concern | Likely location |
|---|---|
| Sidebar vs tabs decision | new file under `App/` (e.g. `RootNavigation.swift`) |
| Size-class-derived layout mode | new pure type under `Utils/` or `Models/` so it is unit-testable |
| Device family / orientation / multitasking | `project.yml` only |
| Grid density, hero sizing | `Views/Library/`, `Views/NowPlaying/` |
| LCD + VU toggles relocated out of the tab bar | `App/ContentView.swift` and the new sidebar |

**Adding any new `.swift` file requires `xcodegen generate --spec project.yml`.**
