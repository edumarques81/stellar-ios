---
mapped: 2026-09-09
focus: tech
---

# Integrations — stellar-ios

There is exactly **one** external system: the Stellar Go backend on the
Raspberry Pi 5. No databases, no auth providers, no analytics, no webhooks,
no third-party APIs are contacted by the app.

## Backend endpoint

| Item | Value |
|---|---|
| Default host | `stellar.local` (`BackendConfigStore.defaultHost`) |
| Port | `3000` |
| Scheme | plain HTTP / ws on the LAN |
| Transport | Socket.IO (via `socket.io-client-swift` 16.1.1) |
| Discovery | Bonjour `_stellar._tcp` via `NWBrowser` |

Host resolution order: **custom (user-entered) → discovered (Bonjour) →
`defaultHost`**. `SocketService` rebuilds its `SocketManager` whenever the
resolved endpoint changes.

`SocketService` is lazily initialised — every `on*`/`emit` method calls
`ensureInitialised()`, so `bind()` works before `connect()`.

## Wire contract

Canonical listing lives outside this repo at
`../docs/SOCKET-CONTRACT.md` in the `stellar-streamer` workspace. Changing an
event shape is a three-repo change (backend, Volumio2-UI, stellar-ios).

Inbound (backend → app), consumed by stores:

| Event | Store |
|---|---|
| `pushState` | `PlayerStore` |
| `pushAirplayState`, `pushAirplayEnded` | `AirplayStore` |
| `pushLibraryAlbums` | `AlbumPickerStore` |
| `pushLibraryArtists` | `ArtistPickerStore` |
| `pushLcdStatus` | `LcdStore` |
| LCD view state | `LcdViewStore` |
| last-played | `LastPlayedStore` |
| ingest progress/result | `IngestStore` |

Outbound (app → backend): `play`, `pause`, `next`, `prev`, `seek`, `volume`,
`mute`, LCD set/toggle, library/artist queries, ingest triggers.

Two contract details that are load-bearing:

- **`pushAirplayEnded` quotes the `sessionID` it ends**, and the client clears
  state only on a match. Never key end-of-session off `isActive: false` in
  `pushAirplayState` — stale `isActive: true` frames arrive on transient drops.
- **Emit argument shape:** `socket?.emit(event, with: data, completion: nil)`,
  not the variadic `emit(_:_:)`. `Array` conforms to `SocketData`, so passing an
  array to the variadic form compiles and sends the whole array as *one* nested
  argument — which silently broke seek. `SocketEmitArgumentShapeTests` pins this.

## AirPlay

The backend relays AirPlay session metadata from `shairport-sync`. In AirPlay
mode the Now Playing screen swaps to the session view and proxies transport over
DACP. **Seek and the format strip are suppressed** — DACP has no seek, and
AirPlay 1 is fixed 44.1 kHz / 16-bit.

## iOS capabilities required

Declared in `project.yml` `info.properties`:

- `NSAppTransportSecurity.NSAllowsLocalNetworking: YES` — the backend is plain
  HTTP on the LAN; the exception is scoped to local networking rather than
  disabling ATS globally.
- `NSLocalNetworkUsageDescription` — iOS 14+ local-network permission prompt.
- `NSBonjourServices: [_stellar._tcp]` — required or `NWBrowser` finds nothing.

These carry over to iPad unchanged.

## Not integrated (deliberately)

Volume: `setVolume` / `toggleMute` exist on `SocketService` but have **no call
sites** and no UI. The streamer's audio path is bit-perfect — MPD runs
`mixer_type "none"` — and the user does not want any volume applied. Keep the
methods; do not wire them up.
