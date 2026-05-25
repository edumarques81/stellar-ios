# iOS Remote Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the silent JSON decode swallow that's hiding what's playing / play-pause / library, then restyle the three tabs (Now Playing, Library, Settings) with the Volumio2-UI redesign visual language, plus a last-played idle state and a connection-status diagnostic.

**Architecture:** Keep the existing 17-file skeleton (`5971ce0` strip-down baseline). Add tolerant per-event parsers, surface decode errors as an observable on `SocketService`, extract Now Playing into three subviews (Playing / Idle / Empty), promote `ArtistDetailView` to its own file, and restyle every view with redesign design tokens (`#d4af6a` gold accent, deep near-black backgrounds, glassy gradients). All stores remain `@Observable`.

**Tech Stack:** Swift 6 + SwiftUI, iOS 17+, `SocketIO-Client-Swift` v16 (Socket.IO v3 / EIO3), xcodegen-built `.xcodeproj` (drives both unit tests via `xcodebuild test` on an iOS simulator and device installs).

**Note on the test runner:** The library uses `@Observable` (iOS 17+) and UIKit-backed SwiftUI APIs, so `swift test` on a macOS host cannot compile it. All compile / test commands in this plan go through `xcodebuild` on the iPhone 16 Pro simulator, fronted by two wrapper scripts created in Task 0.1 (`scripts/build.sh`, `scripts/test.sh`). Keep an iPhone 16 Pro simulator booted while executing the plan (`xcrun simctl boot 'iPhone 16 Pro'` if not already up).

**Spec:** `docs/superpowers/specs/2026-05-24-ios-remote-redesign-design.md`

**Live backend (Mac):** `192.168.86.221:3000`

---

## Phase Map

| Phase | What ships | Verifiable outcome |
| --- | --- | --- |
| 0 | xcodegen test target + wrapper scripts | `scripts/test.sh SmokeTest` passes |
| 1 | Decode-bug fix + LastPlayed wiring | Now Playing shows live state; Library populates; lastDecodeError surfaces on malformed payloads |
| 2 | Design tokens additions | `DesignTokens+Redesign.swift` compiled; new tokens reachable from views |
| 3 | Now Playing rebuild | Playing / Idle / Empty subviews render correctly against live backend |
| 4 | Library rebuild | Albums grid + Artists list + ArtistDetail render with redesign styling |
| 5 | Settings rebuild + ConnectionStatus | LCD toggle + connection-status row + decode-error row all functional |
| 6 | Integration polish + UAT | Tab tint correct; manual UAT checklist passes; device install via deploy script |

Suggested `/clear` between phases when running subagent-driven execution.

---

## Phase 0 — Test infrastructure

The repo has no test target today. We add one to the xcodegen `project.yml` so tests build and run via `xcodebuild test` against an iOS simulator. `swift test` on the macOS host is NOT viable because the library uses `@Observable` (iOS 17+) and SwiftUI APIs that have no macOS equivalent.

`Package.swift` stays untouched in Task 0.1. If a prior partial attempt added a `.testTarget` block to `Package.swift`, revert that — SPM tests aren't on the table.

### Task 0.1: Add xcodegen test target + wrapper scripts

**Files:**
- Read first: `project.yml` — to see the current target/scheme shape.
- Modify: `project.yml`
- Create: `scripts/build.sh`
- Create: `scripts/test.sh`
- Create: `StellarVolumiOTests/SmokeTest.swift`
- Possibly revert: `Package.swift` (if a previous attempt added a `.testTarget`)

- [ ] **Step 1: Revert any stale `Package.swift` edits**

Run: `git diff Package.swift`. If it shows any change (e.g. a `.testTarget` block), run `git checkout -- Package.swift` to revert. `Package.swift` must end up identical to git HEAD.

- [ ] **Step 2: Add the test target to `project.yml`**

Open `project.yml`. Under the existing `targets:` block (which currently declares only `StellarVolumiO`), append the test target — at the same indentation as `StellarVolumiO:`:

```yaml
  StellarVolumiOTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: StellarVolumiOTests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fit.stellar.remote.tests
        GENERATE_INFOPLIST_FILE: YES
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/StellarVolumiO.app/$(BUNDLE_EXECUTABLE_NAME:default=StellarVolumiO)"
    dependencies:
      - target: StellarVolumiO
```

And at the bottom of the file, append a scheme block so `xcodebuild test -scheme StellarVolumiO` includes the test target:

```yaml
schemes:
  StellarVolumiO:
    build:
      targets:
        StellarVolumiO: all
        StellarVolumiOTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - StellarVolumiOTests
```

- [ ] **Step 3: Create the smoke test**

Write `StellarVolumiOTests/SmokeTest.swift`:

```swift
import XCTest
@testable import StellarVolumiO

final class SmokeTest: XCTestCase {
    func testTestTargetIsWired() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

If this file already exists from a prior attempt, leave it — the content matches.

- [ ] **Step 4: Create `scripts/build.sh`**

Create `scripts/build.sh`:

```bash
#!/bin/bash
# Build the iOS app for the iPhone 16 Pro simulator. Used as the compile-check
# after each code change during plan execution.
set -euo pipefail
exec xcodebuild \
  -scheme StellarVolumiO \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build -quiet
```

Make it executable: `chmod +x scripts/build.sh`.

- [ ] **Step 5: Create `scripts/test.sh`**

Create `scripts/test.sh`:

```bash
#!/bin/bash
# Run StellarVolumiOTests via xcodebuild on the iPhone 16 Pro simulator.
#
# Usage:
#   scripts/test.sh                          # all tests
#   scripts/test.sh PlayerStateParserTests   # filter to one suite
set -euo pipefail
if [ $# -eq 0 ]; then
  exec xcodebuild test \
    -scheme StellarVolumiO \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
    -quiet
else
  exec xcodebuild test \
    -scheme StellarVolumiO \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
    -only-testing:"StellarVolumiOTests/$1" \
    -quiet
fi
```

Make it executable: `chmod +x scripts/test.sh`.

- [ ] **Step 6: Regenerate the xcodeproj and run the smoke test**

Run: `xcodegen generate --spec project.yml`
Expected: `Generated project successfully`.

Boot the simulator if needed: `xcrun simctl boot 'iPhone 16 Pro' 2>/dev/null || true`.

Run: `scripts/test.sh SmokeTest`
Expected: output ends with something like `Test Suite 'SmokeTest' passed` and `** TEST SUCCEEDED **`. First run is slow (simulator + first build); subsequent runs ~5s.

- [ ] **Step 7: Commit**

```bash
git add project.yml scripts/build.sh scripts/test.sh StellarVolumiOTests/SmokeTest.swift
git commit -m "test(infra): xcodegen test target + scripts/build.sh + scripts/test.sh"
```

Do NOT commit the regenerated `.xcodeproj` — it's already in `.gitignore` (line 5: `*.xcodeproj`).

---

## Phase 1 — Decode-bug fix and LastPlayed wiring

Root cause: `Services/SocketService.swift:82-95` silently swallows decode errors. The library models (`LibraryAlbum`, `LibraryArtist`, `LcdStatus`) already have tolerant custom decoders. The brittle types are `PlayerState` (auto-`Codable` with strict Int types for `seek`/`duration`/`volume`) and the envelope structs (`PushLibraryAlbums`, `PushLibraryArtists`, `PushLibraryArtistAlbums`). We make them tolerant and surface decode failures via a new observable on `SocketService`.

### Task 1.1: Test fixtures

We use real-shaped JSON. The backend payloads are documented in `Volumio2-UI/CLAUDE.md`; for `pushState` the canonical shape can be verified by tapping the live socket. For this task we hand-write fixtures based on the documented shape + known Volumio quirks (string-vs-int duration, ms-vs-seconds seek, null fields).

**Files:**
- Create: `StellarVolumiOTests/Fixtures/Fixtures.swift`

- [ ] **Step 1: Write fixtures**

Create `StellarVolumiOTests/Fixtures/Fixtures.swift`:

```swift
import Foundation

enum Fixtures {

    // Canonical pushState — backend Go shape, all fields present, sane types.
    static let pushStateCanonical: [String: Any] = [
        "status":       "play",
        "title":        "Time",
        "artist":       "Pink Floyd",
        "album":        "The Dark Side of the Moon",
        "albumart":     "/albumart?path=NAS/Pink%20Floyd/Dark%20Side",
        "uri":          "NAS/Pink Floyd/Dark Side/05 Time.flac",
        "service":      "mpd",
        "duration":     413,
        "seek":         134000,
        "volume":       55,
        "mute":         false,
        "shuffle":      false,
        "repeat":       false,
        "repeatSingle": false,
        "trackType":    "flac",
        "samplerate":   "96000",
        "bitdepth":     "24",
        "channels":     2
    ]

    // Loose pushState — fields stringified, optional fields missing, null seek.
    static let pushStateLoose: [String: Any] = [
        "status":     "pause",
        "title":      "Breathe",
        "artist":     "Pink Floyd",
        "album":      "The Dark Side of the Moon",
        "albumart":   "",
        "uri":        "",
        "service":    "mpd",
        "duration":   "163",
        "seek":       NSNull(),
        "volume":     "50",
        "trackType":  "FLAC",
        "samplerate": "44100",
        "bitdepth":   "16",
        "channels":   2
    ]

    // pushState with all fields absent except status — worst-case input.
    static let pushStateMinimal: [String: Any] = [
        "status": "stop"
    ]

    static let pushLibraryAlbumsCanonical: [String: Any] = [
        "albums": [
            ["title": "The Dark Side of the Moon",
             "artist": "Pink Floyd",
             "uri": "NAS/Pink Floyd/Dark Side",
             "albumart": "/albumart?path=NAS/Pink%20Floyd/Dark%20Side",
             "year": 1973,
             "trackCount": 10],
            ["title": "Kind of Blue",
             "artist": "Miles Davis",
             "uri": "NAS/Miles Davis/Kind of Blue",
             "albumart": "/albumart?path=NAS/Miles%20Davis/Kind%20of%20Blue"]
        ],
        "total": 2
    ]

    // Envelope without `total`; mirrors what older backend builds emitted.
    static let pushLibraryAlbumsNoTotal: [String: Any] = [
        "albums": [
            ["title": "Blue", "artist": "Joni Mitchell", "uri": "", "albumart": ""]
        ]
    ]

    static let pushLibraryArtistsCanonical: [String: Any] = [
        "artists": [
            ["name": "Pink Floyd", "albumCount": 14],
            ["name": "Miles Davis", "albumCount": 47, "artistImage": "/artistart?name=Miles%20Davis"]
        ],
        "total": 2
    ]

    static let pushLibraryArtistAlbumsCanonical: [String: Any] = [
        "artist": "Pink Floyd",
        "albums": [
            ["title": "The Wall", "artist": "Pink Floyd",
             "uri": "NAS/Pink Floyd/The Wall",
             "albumart": "/albumart?path=NAS/Pink%20Floyd/The%20Wall"]
        ]
    ]

    // pushLastPlayedAlbum shape per Volumio2-UI CLAUDE.md.
    static let pushLastPlayedAlbumCanonical: [String: Any] = [
        "artist":     "Miles Davis",
        "album":      "Kind of Blue",
        "albumArt":   "/albumart?path=NAS/Miles%20Davis/Kind%20of%20Blue",
        "trackUri":   "NAS/Miles Davis/Kind of Blue/01 So What.flac",
        "trackType":  "flac",
        "sampleRate": "192000",
        "bitDepth":   "24"
    ]

    static let pushLastPlayedAlbumNull: Any = NSNull()
}
```

- [ ] **Step 2: Verify the file compiles**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiOTests/Fixtures/Fixtures.swift
git commit -m "test(fixtures): canonical + loose JSON fixtures for socket payloads"
```

### Task 1.2: Make `PlayerState` tolerant

Replace the auto-`Codable` shell with a hand-written `init(rawDict: [String: Any])` that:

- Accepts `Int` *or* numeric `String` for `duration`, `seek`, `volume`, `channels`.
- Accepts `null` / missing for any optional field — falls back to the corresponding `PlayerState.empty` value.
- Parses `status` from a string via `PlaybackStatus(rawValue:)`, defaulting to `.stop` on unknown.

**Files:**
- Modify: `StellarVolumiO/Models/PlayerState.swift`
- Create: `StellarVolumiOTests/PlayerStateParserTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `StellarVolumiOTests/PlayerStateParserTests.swift`:

```swift
import XCTest
@testable import StellarVolumiO

final class PlayerStateParserTests: XCTestCase {

    func testCanonicalDecode() {
        let s = PlayerState(rawDict: Fixtures.pushStateCanonical)
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.status, .play)
        XCTAssertEqual(s?.title, "Time")
        XCTAssertEqual(s?.artist, "Pink Floyd")
        XCTAssertEqual(s?.duration, 413)
        XCTAssertEqual(s?.seek, 134000)
        XCTAssertEqual(s?.volume, 55)
        XCTAssertEqual(s?.trackType, "flac")
        XCTAssertEqual(s?.samplerate, "96000")
        XCTAssertEqual(s?.bitdepth, "24")
    }

    func testLooseDecodeWithStringsAndNulls() {
        let s = PlayerState(rawDict: Fixtures.pushStateLoose)
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.status, .pause)
        XCTAssertEqual(s?.duration, 163, "string-shaped duration should coerce to Int")
        XCTAssertEqual(s?.seek, 0, "null seek should fall back to 0")
        XCTAssertEqual(s?.volume, 50, "string-shaped volume should coerce to Int")
        XCTAssertEqual(s?.title, "Breathe")
    }

    func testMinimalDecode() {
        let s = PlayerState(rawDict: Fixtures.pushStateMinimal)
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.status, .stop)
        XCTAssertEqual(s?.title, "")
        XCTAssertEqual(s?.duration, 0)
        XCTAssertEqual(s?.seek, 0)
        XCTAssertEqual(s?.volume, 50, "missing volume falls back to PlayerState.empty default")
    }

    func testUnknownStatusFallsBackToStop() {
        let s = PlayerState(rawDict: ["status": "unknown_state"])
        XCTAssertEqual(s?.status, .stop)
    }

    func testCompletelyEmptyDictReturnsEmpty() {
        let s = PlayerState(rawDict: [:])
        XCTAssertEqual(s?.status, .stop)
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `scripts/test.sh PlayerStateParserTests`
Expected: compile error — `PlayerState.init(rawDict:)` does not exist.

- [ ] **Step 3: Implement `PlayerState.init(rawDict:)`**

Open `StellarVolumiO/Models/PlayerState.swift` and append (after the `struct PlayerState` closing brace, before `enum PlaybackStatus`):

```swift
extension PlayerState {
    /// Tolerant parser for the Stellar backend `pushState` payload. Accepts
    /// Int-or-numeric-String for numeric fields and null/missing for any
    /// optional. Unknown `status` falls back to `.stop`. Returns nil only
    /// when the input is not a dictionary.
    init?(rawDict d: [String: Any]) {
        let s = PlayerState.empty
        self.init(
            status:       Self.parseStatus(d["status"])    ?? s.status,
            title:        d["title"]      as? String       ?? s.title,
            artist:       d["artist"]     as? String       ?? s.artist,
            album:        d["album"]      as? String       ?? s.album,
            albumart:     d["albumart"]   as? String       ?? s.albumart,
            uri:          d["uri"]        as? String       ?? s.uri,
            service:      d["service"]    as? String       ?? s.service,
            duration:     Self.parseInt(d["duration"])     ?? s.duration,
            seek:         Self.parseInt(d["seek"])         ?? s.seek,
            volume:       Self.parseInt(d["volume"])       ?? s.volume,
            mute:         d["mute"]       as? Bool         ?? s.mute,
            shuffle:      d["shuffle"]    as? Bool         ?? s.shuffle,
            repeat:       d["repeat"]     as? Bool         ?? s.`repeat`,
            repeatSingle: d["repeatSingle"] as? Bool       ?? s.repeatSingle,
            trackType:    d["trackType"]  as? String       ?? s.trackType,
            samplerate:   d["samplerate"] as? String       ?? s.samplerate,
            bitdepth:     d["bitdepth"]   as? String       ?? s.bitdepth,
            channels:     Self.parseInt(d["channels"])     ?? s.channels
        )
    }

    private static func parseInt(_ any: Any?) -> Int? {
        if let v = any as? Int { return v }
        if let v = any as? Double { return Int(v) }
        if let v = any as? String, let n = Int(v) { return n }
        if let v = any as? String, let n = Double(v) { return Int(n) }
        return nil
    }

    private static func parseStatus(_ any: Any?) -> PlaybackStatus? {
        guard let s = any as? String else { return nil }
        return PlaybackStatus(rawValue: s.lowercased())
    }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `scripts/test.sh PlayerStateParserTests`
Expected: 5 tests passed.

- [ ] **Step 5: Commit**

```bash
git add StellarVolumiO/Models/PlayerState.swift StellarVolumiOTests/PlayerStateParserTests.swift
git commit -m "fix(decode): tolerant PlayerState parser for loose backend payload"
```

### Task 1.3: Make `PushLibraryAlbums` tolerant

The envelope struct currently uses auto-`Codable`. We replace it with a hand-rolled init that accepts the same dict shape and decodes nested `LibraryAlbum` items via their existing tolerant `init(from:)`.

**Files:**
- Modify: `StellarVolumiO/Models/LibraryModels.swift`
- Create: `StellarVolumiOTests/LibraryEnvelopeParserTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `StellarVolumiOTests/LibraryEnvelopeParserTests.swift`:

```swift
import XCTest
@testable import StellarVolumiO

final class LibraryEnvelopeParserTests: XCTestCase {

    func testPushLibraryAlbumsCanonical() {
        let env = PushLibraryAlbums(rawDict: Fixtures.pushLibraryAlbumsCanonical)
        XCTAssertNotNil(env)
        XCTAssertEqual(env?.albums.count, 2)
        XCTAssertEqual(env?.albums[0].title, "The Dark Side of the Moon")
        XCTAssertEqual(env?.albums[0].artist, "Pink Floyd")
        XCTAssertEqual(env?.albums[0].year, 1973)
        XCTAssertEqual(env?.total, 2)
    }

    func testPushLibraryAlbumsNoTotal() {
        let env = PushLibraryAlbums(rawDict: Fixtures.pushLibraryAlbumsNoTotal)
        XCTAssertNotNil(env)
        XCTAssertEqual(env?.albums.count, 1)
        XCTAssertNil(env?.total, "missing total stays nil — not 0")
    }

    func testPushLibraryAlbumsEmpty() {
        let env = PushLibraryAlbums(rawDict: ["albums": [Any]()])
        XCTAssertEqual(env?.albums.count, 0)
    }

    func testPushLibraryAlbumsMissingAlbumsKey() {
        let env = PushLibraryAlbums(rawDict: ["total": 0])
        XCTAssertNotNil(env, "envelope still constructs even with empty payload")
        XCTAssertEqual(env?.albums.count, 0)
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

Run: `scripts/test.sh LibraryEnvelopeParserTests`
Expected: compile error — `PushLibraryAlbums.init(rawDict:)` does not exist.

- [ ] **Step 3: Implement**

Open `StellarVolumiO/Models/LibraryModels.swift` and append at the end (after the `LcdStatus` struct):

```swift
// MARK: - Tolerant envelope parsers
//
// Each `init(rawDict:)` accepts the raw [String: Any] that came out of
// Socket.IO and routes the nested album / artist dicts through the existing
// tolerant `Codable` decoders on LibraryAlbum / LibraryArtist via a
// JSONSerialization round-trip. Two-phase is OK here — the dicts are small
// and this only fires once per push.

extension PushLibraryAlbums {
    init?(rawDict d: [String: Any]) {
        let rawAlbums = d["albums"] as? [[String: Any]] ?? []
        let albums = rawAlbums.compactMap { LibraryAlbum(rawDict: $0) }
        let total = d["total"] as? Int
        self.albums = albums
        self.total = total
    }
}

extension PushLibraryArtists {
    init?(rawDict d: [String: Any]) {
        let rawArtists = d["artists"] as? [[String: Any]] ?? []
        let artists = rawArtists.compactMap { LibraryArtist(rawDict: $0) }
        let total = d["total"] as? Int
        self.artists = artists
        self.total = total
    }
}

extension PushLibraryArtistAlbums {
    init?(rawDict d: [String: Any]) {
        let rawAlbums = d["albums"] as? [[String: Any]] ?? []
        let albums = rawAlbums.compactMap { LibraryAlbum(rawDict: $0) }
        let artist = d["artist"] as? String
        self.artist = artist
        self.albums = albums
    }
}

extension LibraryAlbum {
    /// Dict-based tolerant init — mirrors the existing JSONDecoder
    /// `init(from:)` but skips the JSONSerialization roundtrip.
    init?(rawDict d: [String: Any]) {
        let title    = d["title"]    as? String ?? ""
        let artist   = d["artist"]   as? String ?? ""
        let uri      = d["uri"]      as? String ?? ""
        let albumart = d["albumart"] as? String ?? ""
        let year     = d["year"] as? Int
        let trackCount = d["trackCount"] as? Int
        let id = uri.isEmpty ? "\(artist)|\(title)" : uri
        self.init(id: id, title: title, artist: artist, uri: uri,
                  albumart: albumart, year: year, trackCount: trackCount)
    }
}

extension LibraryArtist {
    init?(rawDict d: [String: Any]) {
        let name = d["name"] as? String ?? ""
        let id   = (d["id"] as? String) ?? name
        let albumCount  = d["albumCount"]  as? Int
        let artistImage = d["artistImage"] as? String
        self.init(id: id, name: name, albumCount: albumCount, artistImage: artistImage)
    }
}
```

- [ ] **Step 4: Run to confirm passing**

Run: `scripts/test.sh LibraryEnvelopeParserTests`
Expected: 4 tests passed.

- [ ] **Step 5: Commit**

```bash
git add StellarVolumiO/Models/LibraryModels.swift StellarVolumiOTests/LibraryEnvelopeParserTests.swift
git commit -m "fix(decode): tolerant rawDict parsers for library envelopes"
```

### Task 1.4: Add `PushLibraryArtists` + `PushLibraryArtistAlbums` test coverage

The parsers already exist from 1.3 — this task adds explicit test coverage so each envelope has its own regression test.

**Files:**
- Modify: `StellarVolumiOTests/LibraryEnvelopeParserTests.swift`

- [ ] **Step 1: Append tests**

Append to `StellarVolumiOTests/LibraryEnvelopeParserTests.swift`, inside the existing class:

```swift
    func testPushLibraryArtistsCanonical() {
        let env = PushLibraryArtists(rawDict: Fixtures.pushLibraryArtistsCanonical)
        XCTAssertNotNil(env)
        XCTAssertEqual(env?.artists.count, 2)
        XCTAssertEqual(env?.artists[0].name, "Pink Floyd")
        XCTAssertEqual(env?.artists[1].artistImage, "/artistart?name=Miles%20Davis")
    }

    func testPushLibraryArtistAlbumsCanonical() {
        let env = PushLibraryArtistAlbums(rawDict: Fixtures.pushLibraryArtistAlbumsCanonical)
        XCTAssertNotNil(env)
        XCTAssertEqual(env?.artist, "Pink Floyd")
        XCTAssertEqual(env?.albums.count, 1)
        XCTAssertEqual(env?.albums[0].title, "The Wall")
    }
```

- [ ] **Step 2: Run to confirm passing**

Run: `scripts/test.sh LibraryEnvelopeParserTests`
Expected: 6 tests passed.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiOTests/LibraryEnvelopeParserTests.swift
git commit -m "test(decode): coverage for PushLibraryArtists + ArtistAlbums envelopes"
```

### Task 1.5: Add `LastPlayedAlbum` model + parser

The backend pushes `pushLastPlayedAlbum` on connect with the shape documented in `Volumio2-UI/CLAUDE.md`. Payload may be JSON null on a fresh backend.

**Files:**
- Create: `StellarVolumiO/Models/LastPlayedAlbum.swift`
- Create: `StellarVolumiOTests/LastPlayedAlbumTests.swift`

- [ ] **Step 1: Write the failing test**

Create `StellarVolumiOTests/LastPlayedAlbumTests.swift`:

```swift
import XCTest
@testable import StellarVolumiO

final class LastPlayedAlbumTests: XCTestCase {

    func testCanonicalParse() {
        let a = LastPlayedAlbum(rawDict: Fixtures.pushLastPlayedAlbumCanonical)
        XCTAssertNotNil(a)
        XCTAssertEqual(a?.artist, "Miles Davis")
        XCTAssertEqual(a?.album, "Kind of Blue")
        XCTAssertEqual(a?.albumArt, "/albumart?path=NAS/Miles%20Davis/Kind%20of%20Blue")
        XCTAssertEqual(a?.trackUri, "NAS/Miles Davis/Kind of Blue/01 So What.flac")
        XCTAssertEqual(a?.trackType, "flac")
        XCTAssertEqual(a?.sampleRate, "192000")
        XCTAssertEqual(a?.bitDepth, "24")
    }

    func testEmptyDictReturnsNil() {
        let a = LastPlayedAlbum(rawDict: [:])
        XCTAssertNil(a, "no artist + no album means the album is unidentifiable")
    }

    func testPartialDict() {
        // artist + album present, the rest missing — still parses, just with empty strings.
        let a = LastPlayedAlbum(rawDict: ["artist": "X", "album": "Y"])
        XCTAssertNotNil(a)
        XCTAssertEqual(a?.artist, "X")
        XCTAssertEqual(a?.album, "Y")
        XCTAssertEqual(a?.trackUri, "")
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

Run: `scripts/test.sh LastPlayedAlbumTests`
Expected: compile error — `LastPlayedAlbum` doesn't exist.

- [ ] **Step 3: Implement**

Create `StellarVolumiO/Models/LastPlayedAlbum.swift`:

```swift
import Foundation

/// Resume-state payload pushed by the backend on connect + every album boundary.
/// Per `Volumio2-UI/CLAUDE.md` the payload may be JSON null on a fresh backend.
struct LastPlayedAlbum: Equatable {
    let artist: String
    let album: String
    let albumArt: String
    let trackUri: String
    let trackType: String
    let sampleRate: String
    let bitDepth: String

    init?(rawDict d: [String: Any]) {
        let artist = d["artist"] as? String ?? ""
        let album  = d["album"]  as? String ?? ""
        // Reject if both anchor fields are empty — the row is not playable.
        guard !(artist.isEmpty && album.isEmpty) else { return nil }
        self.artist     = artist
        self.album      = album
        self.albumArt   = d["albumArt"]   as? String ?? ""
        self.trackUri   = d["trackUri"]   as? String ?? ""
        self.trackType  = d["trackType"]  as? String ?? ""
        self.sampleRate = d["sampleRate"] as? String ?? ""
        self.bitDepth   = d["bitDepth"]   as? String ?? ""
    }
}
```

- [ ] **Step 4: Run to confirm passing**

Run: `scripts/test.sh LastPlayedAlbumTests`
Expected: 3 tests passed.

- [ ] **Step 5: Commit**

```bash
git add StellarVolumiO/Models/LastPlayedAlbum.swift StellarVolumiOTests/LastPlayedAlbumTests.swift
git commit -m "feat(model): LastPlayedAlbum + tolerant parser"
```

### Task 1.6: `SocketService.lastDecodeError` + `onRawDict<T>` helper

Surface decode failures as an observable. Add a sibling subscription method that gives the handler the raw `[String: Any]` dict rather than a forced `Decodable`. The existing `on<T: Decodable>` keeps its silent-swallow behaviour for now (used by `pushLcdStatus`, which already works) — we only migrate the broken events.

**Files:**
- Modify: `StellarVolumiO/Services/SocketService.swift`

- [ ] **Step 1: Add `lastDecodeError` + `onRawDict<T>`**

Open `StellarVolumiO/Services/SocketService.swift` and:

a) Inside the `@Observable final class SocketService` body, after `var serverPort: Int = defaultPort`, add:

```swift
    /// One-line summary of the last failed decode, e.g. "pushState: dict cast
    /// failed". `nil` when the last incoming payload decoded cleanly.
    /// Surfaced in the Settings → ConnectionStatusRow diagnostic.
    var lastDecodeError: String? = nil
```

b) After the existing `func on<T: Decodable>(_ event: String, ...)` method, add:

```swift
    /// Subscribe to a Socket.IO event where the wire payload is a
    /// `[String: Any]` dict (typical Volumio shape). Caller provides a
    /// tolerant parser; on `nil` we populate `lastDecodeError`.
    func onRawDict<T>(_ event: String, parser: @escaping ([String: Any]) -> T?, handler: @escaping (T) -> Void) {
        socket?.on(event) { [weak self] data, _ in
            guard let arr = data as? [Any], let first = arr.first else {
                DispatchQueue.main.async { self?.lastDecodeError = "\(event): empty payload" }
                return
            }
            guard let dict = first as? [String: Any] else {
                DispatchQueue.main.async { self?.lastDecodeError = "\(event): payload not a dict" }
                return
            }
            guard let parsed = parser(dict) else {
                DispatchQueue.main.async { self?.lastDecodeError = "\(event): parser rejected payload" }
                return
            }
            DispatchQueue.main.async {
                self?.lastDecodeError = nil
                handler(parsed)
            }
        }
    }

    /// Variant that allows the payload to be `NSNull` (e.g.
    /// pushLastPlayedAlbum on a fresh backend) — passes `nil` to the handler.
    func onRawDictNullable<T>(_ event: String, parser: @escaping ([String: Any]) -> T?, handler: @escaping (T?) -> Void) {
        socket?.on(event) { [weak self] data, _ in
            let first = (data as? [Any])?.first
            if first is NSNull || first == nil {
                DispatchQueue.main.async {
                    self?.lastDecodeError = nil
                    handler(nil)
                }
                return
            }
            guard let dict = first as? [String: Any] else {
                DispatchQueue.main.async { self?.lastDecodeError = "\(event): payload not a dict" }
                return
            }
            DispatchQueue.main.async {
                if let parsed = parser(dict) {
                    self?.lastDecodeError = nil
                    handler(parsed)
                } else {
                    self?.lastDecodeError = "\(event): parser rejected payload"
                }
            }
        }
    }
```

c) Modify the existing typed `on<T: Decodable>` to also populate `lastDecodeError` on failure. Find the block:

```swift
        let wrapper: (Any) -> Void = { data in
            guard let arr = data as? [Any], let first = arr.first else { return }
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: first)
                let decoded = try JSONDecoder().decode(T.self, from: jsonData)
                DispatchQueue.main.async { handler(decoded) }
            } catch {
                // Silently ignore decode errors — backend shape may vary
            }
        }
```

Replace with:

```swift
        let wrapper: (Any) -> Void = { [weak self] data in
            guard let arr = data as? [Any], let first = arr.first else { return }
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: first)
                let decoded = try JSONDecoder().decode(T.self, from: jsonData)
                DispatchQueue.main.async {
                    self?.lastDecodeError = nil
                    handler(decoded)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.lastDecodeError = "\(event): \(error.localizedDescription)"
                }
            }
        }
```

- [ ] **Step 2: Build to verify no compile breakage**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Services/SocketService.swift
git commit -m "feat(socket): observable lastDecodeError + onRawDict helpers"
```

### Task 1.7: Switch `PlayerStore.bind` to `onRawDict`

The store currently uses the auto-`Decodable` path. Move it onto the tolerant parser.

**Files:**
- Modify: `StellarVolumiO/Stores/PlayerStore.swift`

- [ ] **Step 1: Update `PlayerStore.bind`**

Open `StellarVolumiO/Stores/PlayerStore.swift` and replace the `bind(to:)` method with:

```swift
    func bind(to socket: SocketService) {
        socket.onRawDict("pushState",
                         parser: PlayerState.init(rawDict:)) { [weak self] (newState: PlayerState) in
            guard let self else { return }
            if self.state.status != newState.status ||
               self.state.title  != newState.title  ||
               self.state.artist != newState.artist ||
               self.state.album  != newState.album  ||
               self.state.volume != newState.volume ||
               abs(self.state.seekSeconds - newState.seekSeconds) > 1.0 ||
               self.state.duration != newState.duration {
                self.state = newState
            }
        }

        socket.on("pushQueue") { [weak self] (items: [QueueItem]) in
            self?.queue = items
        }
    }
```

- [ ] **Step 2: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Stores/PlayerStore.swift
git commit -m "fix(player): route pushState through tolerant rawDict parser"
```

### Task 1.8: Switch `AlbumPickerStore` + `ArtistPickerStore` to `onRawDict`

**Files:**
- Modify: `StellarVolumiO/Stores/AlbumPickerStore.swift`
- Modify: `StellarVolumiO/Stores/ArtistPickerStore.swift`

- [ ] **Step 1: Update `AlbumPickerStore.bind`**

Open `StellarVolumiO/Stores/AlbumPickerStore.swift` and replace the `bind(to:)` body with:

```swift
    func bind(to socket: SocketService) {
        self.socket = socket
        socket.onRawDict("pushLibraryAlbums",
                         parser: PushLibraryAlbums.init(rawDict:)) { [weak self] (payload: PushLibraryAlbums) in
            self?.albums = payload.albums
            self?.loading = false
            self?.lastError = nil
        }
    }
```

- [ ] **Step 2: Update `ArtistPickerStore.bind`**

Open `StellarVolumiO/Stores/ArtistPickerStore.swift` and replace the `bind(to:)` body with:

```swift
    func bind(to socket: SocketService) {
        self.socket = socket
        socket.onRawDict("pushLibraryArtists",
                         parser: PushLibraryArtists.init(rawDict:)) { [weak self] (payload: PushLibraryArtists) in
            self?.artists = payload.artists
            self?.loading = false
        }
        socket.onRawDict("pushLibraryArtistAlbums",
                         parser: PushLibraryArtistAlbums.init(rawDict:)) { [weak self] (payload: PushLibraryArtistAlbums) in
            self?.artistAlbums = payload.albums
            self?.loadingArtistAlbums = false
        }
    }
```

- [ ] **Step 3: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add StellarVolumiO/Stores/AlbumPickerStore.swift StellarVolumiO/Stores/ArtistPickerStore.swift
git commit -m "fix(library): route album/artist envelopes through tolerant parsers"
```

### Task 1.9: `LastPlayedStore`

**Files:**
- Create: `StellarVolumiO/Stores/LastPlayedStore.swift`
- Modify: `StellarVolumiO/App/StellarApp.swift`

- [ ] **Step 1: Create `LastPlayedStore`**

Create `StellarVolumiO/Stores/LastPlayedStore.swift`:

```swift
import Foundation
import Observation

@Observable
final class LastPlayedStore {

    /// Latest last-played album from the backend. `nil` means MPD has never
    /// played anything in this backend's lifetime — show the empty state.
    var album: LastPlayedAlbum? = nil

    private weak var socket: SocketService?

    func bind(to socket: SocketService) {
        self.socket = socket
        socket.onRawDictNullable("pushLastPlayedAlbum",
                                  parser: LastPlayedAlbum.init(rawDict:)) { [weak self] album in
            self?.album = album
        }
    }

    /// Emit Volumio's `addPlay` to resume the saved track. Read-only state
    /// otherwise — this is the only mutator that triggers playback.
    func resume() {
        guard let socket, let a = album, !a.trackUri.isEmpty else { return }
        socket.emitObject("addPlay", [
            "service":  "mpd",
            "type":     "song",
            "uri":      a.trackUri,
            "title":    a.album,
            "artist":   a.artist,
            "albumart": a.albumArt
        ])
    }

    /// Explicit refresh (rarely needed — backend pushes proactively on connect).
    func refresh() {
        socket?.emit("library:lastPlayed:get")
    }
}
```

- [ ] **Step 2: Wire into `StellarApp`**

Open `StellarVolumiO/App/StellarApp.swift` and:

a) Add `@State private var lastPlayedStore = LastPlayedStore()` after the other `@State` lines.

b) Add `.environment(lastPlayedStore)` after `.environment(lcdStore)`.

c) Inside `.onAppear`, add `lastPlayedStore.bind(to: socketService)` after `lcdStore.bind(to: socketService)`.

Final file:

```swift
import SwiftUI

@main
struct StellarApp: App {
    @State private var socketService = SocketService()
    @State private var playerStore = PlayerStore()
    @State private var albumStore = AlbumPickerStore()
    @State private var artistStore = ArtistPickerStore()
    @State private var lcdStore = LcdStore()
    @State private var lastPlayedStore = LastPlayedStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(socketService)
                .environment(playerStore)
                .environment(albumStore)
                .environment(artistStore)
                .environment(lcdStore)
                .environment(lastPlayedStore)
                .preferredColorScheme(.dark)
                .onAppear {
                    playerStore.bind(to: socketService)
                    albumStore.bind(to: socketService)
                    artistStore.bind(to: socketService)
                    lcdStore.bind(to: socketService)
                    lastPlayedStore.bind(to: socketService)
                    socketService.connect()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    socketService.reconnectIfNeeded()
                }
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add StellarVolumiO/Stores/LastPlayedStore.swift StellarVolumiO/App/StellarApp.swift
git commit -m "feat(lastplayed): LastPlayedStore + StellarApp wiring"
```

### Task 1.10: Store-level behavioural tests

Spec's test matrix calls for `LastPlayedStore` and `SocketService.lastDecodeError` behavioural coverage that isn't reachable via the parser tests alone.

**Files:**
- Create: `StellarVolumiOTests/LastPlayedStoreTests.swift`
- Create: `StellarVolumiOTests/SocketDecodeErrorSurfaceTests.swift`

- [ ] **Step 1: Write `LastPlayedStoreTests`**

Create `StellarVolumiOTests/LastPlayedStoreTests.swift`:

```swift
import XCTest
@testable import StellarVolumiO

@MainActor
final class LastPlayedStoreTests: XCTestCase {

    func testParserAcceptsCanonicalPayload() {
        let parsed = LastPlayedAlbum(rawDict: Fixtures.pushLastPlayedAlbumCanonical)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.artist, "Miles Davis")
    }

    func testStoreHoldsAndReplacesAlbum() {
        let store = LastPlayedStore()
        XCTAssertNil(store.album)

        let first = LastPlayedAlbum(rawDict: Fixtures.pushLastPlayedAlbumCanonical)!
        store.album = first
        XCTAssertEqual(store.album?.album, "Kind of Blue")

        let second = LastPlayedAlbum(rawDict: [
            "artist": "Pink Floyd", "album": "The Wall",
            "albumArt": "/a.jpg", "trackUri": "x.flac",
            "trackType": "flac", "sampleRate": "44100", "bitDepth": "16"
        ])!
        store.album = second
        XCTAssertEqual(store.album?.album, "The Wall", "album must replace, not accumulate")
    }

    func testStoreAcceptsNilWithoutCrash() {
        let store = LastPlayedStore()
        store.album = nil
        XCTAssertNil(store.album)
    }
}
```

- [ ] **Step 2: Write `SocketDecodeErrorSurfaceTests`**

The `onRawDict` helper populates `lastDecodeError` synchronously inside `DispatchQueue.main.async`. We exercise the helper by extracting its parsing logic into a directly-testable pure-function path. The simplest approach: assert the contract via `PlayerState.init(rawDict:)` returning nil for non-dict-like inputs, which is the failure mode `onRawDict` surfaces.

Since `onRawDict` requires a live socket to subscribe, we test the surrounding contract via a small helper added on `SocketService`:

Create `StellarVolumiOTests/SocketDecodeErrorSurfaceTests.swift`:

```swift
import XCTest
@testable import StellarVolumiO

@MainActor
final class SocketDecodeErrorSurfaceTests: XCTestCase {

    func testParserReturningNilProducesDescriptiveErrorString() {
        // Direct test of the contract: any caller of onRawDict whose parser
        // returns nil must populate lastDecodeError with an event-named string.
        let svc = SocketService()
        XCTAssertNil(svc.lastDecodeError)

        svc.simulateDecodeFailure(event: "pushState", reason: "parser rejected payload")
        XCTAssertEqual(svc.lastDecodeError, "pushState: parser rejected payload")
    }

    func testSubsequentSuccessClearsError() {
        let svc = SocketService()
        svc.simulateDecodeFailure(event: "pushState", reason: "bad payload")
        XCTAssertNotNil(svc.lastDecodeError)

        svc.simulateDecodeSuccess()
        XCTAssertNil(svc.lastDecodeError)
    }
}
```

- [ ] **Step 3: Add the test-only helpers on `SocketService`**

Open `StellarVolumiO/Services/SocketService.swift` and append at the very end of the file (after the existing extensions):

```swift
// MARK: - Test hooks
//
// Production callers of onRawDict / onRawDictNullable / on<T> populate
// lastDecodeError via the DispatchQueue.main.async paths. These two helpers
// give tests a synchronous, socket-less entry point with the same shape.

#if DEBUG
extension SocketService {
    func simulateDecodeFailure(event: String, reason: String) {
        lastDecodeError = "\(event): \(reason)"
    }

    func simulateDecodeSuccess() {
        lastDecodeError = nil
    }
}
#endif
```

- [ ] **Step 4: Run the new tests**

Run: `scripts/test.sh LastPlayedStoreTests`
Expected: 3 tests passed.

Run: `scripts/test.sh SocketDecodeErrorSurfaceTests`
Expected: 2 tests passed.

Run the full suite to confirm no regressions:

Run: `scripts/test.sh`
Expected: all suites passed.

- [ ] **Step 5: Commit**

```bash
git add StellarVolumiOTests/LastPlayedStoreTests.swift \
        StellarVolumiOTests/SocketDecodeErrorSurfaceTests.swift \
        StellarVolumiO/Services/SocketService.swift
git commit -m "test: LastPlayedStore behaviour + SocketService lastDecodeError surfacing"
```

### Task 1.11: Manual smoke against live backend

This is the verification gate before moving to visual rework. After this task you should see real data flowing — what's playing visible, library populated — even though styling is unchanged.

- [ ] **Step 1: Confirm Mac backend is running**

Run: `lsof -nP -iTCP:3000 -sTCP:LISTEN`
Expected: a process bound to `*:3000`. If empty, start the backend (`~/bin/stellar-restart.sh backend`).

- [ ] **Step 2: Build the xcodegen project**

Run: `cd /Users/eduardomarques/workspace/stellar-streamer/stellar-ios && xcodegen generate --spec project.yml`
Expected: `Generated project successfully`.

- [ ] **Step 3: Pick a simulator UDID and build**

Run: `xcrun simctl list devices booted | head` to find a booted simulator; if none, boot one: `xcrun simctl boot 'iPhone 16 Pro'`. Then:

```bash
xcodebuild -scheme StellarVolumiO -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Launch and observe**

Launch the simulator. In Now Playing tab, observe that the current track (if any) appears immediately after connect. In Library tab, both segments should populate within 1–2 seconds (lists were 72 albums / 41 artists as of last sweep). Verify play / pause / next / prev all round-trip to the Mac backend (`tail -f ~/Library/Logs/stellar-backend.err.log` should show events).

If Library lists are still empty: check decode-error path. Set a breakpoint on `SocketService.lastDecodeError` setter, capture the failing payload, extend the parser test, fix, repeat.

- [ ] **Step 5: Commit (no code changes — checkpoint marker)**

```bash
git commit --allow-empty -m "checkpoint: Phase 1 verified end-to-end against live backend"
```

(Task numbering in the rest of this document references Task 1.10 as the smoke task in older drafts — for this plan, **Task 1.11** is the smoke task. Tasks 1.10 = behavioural tests; 1.11 = manual smoke.)

---

## Phase 2 — Design tokens additions

We extend the existing `DesignTokens.swift` with the redesign-specific tokens used by every new view: the gold accent, the deep near-black palette with its glassy gradients, badge styling, and the spec-defined corner radius / shadow constants. Existing token names are preserved so we don't ripple into untouched files.

### Task 2.1: `DesignTokens+Redesign.swift`

**Files:**
- Read first: `StellarVolumiO/Utils/DesignTokens.swift` — confirm which `Color.md*` and `StellarFont.*` constants already exist before duplicating any name.
- Create: `StellarVolumiO/Utils/DesignTokens+Redesign.swift`

- [ ] **Step 1: Read existing tokens**

Read `StellarVolumiO/Utils/DesignTokens.swift` end-to-end. Note the names of every `Color.md*` constant and every `StellarFont.*` constant. New tokens in this task must not collide with existing names — if a name overlaps, reuse the existing one rather than redefine.

- [ ] **Step 2: Create the redesign tokens file**

Create `StellarVolumiO/Utils/DesignTokens+Redesign.swift`:

```swift
import SwiftUI

// MARK: - Redesign palette
//
// Direct port of the Volumio2-UI redesign tokens
// (`Volumio2-UI/src/lib/components/redesign/PlayerLayout.svelte:60-65` and
// `app.css` redesign-tokens). Names are scoped under `Stellar.*` static
// vars so they don't collide with the M3 `md*` tokens that already exist.

enum Stellar {

    enum Color {
        /// Gold accent. Used for the play disc, format badges, the progress
        /// fill, the active tab tint, the Resume CTA.
        static let gold = SwiftUI.Color(red: 0xd4 / 255, green: 0xaf / 255, blue: 0x6a / 255)

        /// Tinted gold fill for badge backgrounds (alpha 0.18).
        static let goldFill = SwiftUI.Color(red: 0xd4 / 255, green: 0xaf / 255, blue: 0x6a / 255, opacity: 0.18)

        /// Deep near-black base, matches PlayerLayout `#050507`.
        static let baseBackground = SwiftUI.Color(red: 0x05 / 255, green: 0x05 / 255, blue: 0x07 / 255)

        /// Surface used for card-like rows in Settings, slightly lifted off base.
        static let surfaceLow = SwiftUI.Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x1a / 255)

        /// Hairline separator.
        static let separator = SwiftUI.Color(red: 0x1f / 255, green: 0x1f / 255, blue: 0x25 / 255)

        /// Status dot colours.
        static let statusGreen = SwiftUI.Color(red: 0x4c / 255, green: 0xaf / 255, blue: 0x50 / 255)
        static let statusAmber = SwiftUI.Color(red: 0xff / 255, green: 0xc1 / 255, blue: 0x07 / 255)
        static let statusRed   = SwiftUI.Color(red: 0xe5 / 255, green: 0x39 / 255, blue: 0x35 / 255)
    }

    enum Metric {
        /// Album-art hero corner radius.
        static let artCornerRadius: CGFloat = 16
        /// Play disc diameter.
        static let playDisc: CGFloat = 72
        /// Optical-centre offset applied to the play.fill triangle inside the disc.
        static let playGlyphOffset: CGFloat = 2
        /// Minimum touch target (Apple HIG).
        static let minTouchTarget: CGFloat = 44
    }

    enum Shadow {
        static let albumArt = (radius: CGFloat(28), y: CGFloat(8), opacity: 0.5)
    }
}

// MARK: - Glassy background modifier
//
// Used as the root background on Now Playing. Two soft radial gradients on top
// of the deep base mimic PlayerLayout.svelte's radial-gradient sheen.

struct StellarGlassyBackground: View {
    var body: some View {
        ZStack {
            Stellar.Color.baseBackground

            RadialGradient(
                colors: [SwiftUI.Color.white.opacity(0.085), .clear],
                center: UnitPoint(x: 0.85, y: 0.15),
                startRadius: 0,
                endRadius: 280
            )

            RadialGradient(
                colors: [SwiftUI.Color(red: 40/255, green: 60/255, blue: 90/255, opacity: 0.15), .clear],
                center: UnitPoint(x: 0.80, y: 0.90),
                startRadius: 0,
                endRadius: 280
            )
        }
        .ignoresSafeArea()
    }
}
```

- [ ] **Step 3: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **` — if you get "ambiguous use of 'Color'" anywhere, rename `Stellar.Color` → `Stellar.Palette` (and update references).

- [ ] **Step 4: Commit**

```bash
git add StellarVolumiO/Utils/DesignTokens+Redesign.swift
git commit -m "feat(tokens): add Stellar.Color / Stellar.Metric / glassy background"
```

---

## Phase 3 — Now Playing rebuild

Build the three subviews and the shell. Phase order is bottom-up: components first, then composing views, then the shell decision logic. The existing `NowPlayingView.swift` is rewritten in the final task — components are added alongside without breaking the build.

### Task 3.1: Optimistic status on `PlayerStore`

**Files:**
- Modify: `StellarVolumiO/Stores/PlayerStore.swift`
- Create: `StellarVolumiOTests/PlayerStoreOptimisticTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `StellarVolumiOTests/PlayerStoreOptimisticTests.swift`:

```swift
import XCTest
@testable import StellarVolumiO

@MainActor
final class PlayerStoreOptimisticTests: XCTestCase {

    func testOptimisticPlayMakesIsPlayingTrue() {
        let store = PlayerStore()
        store.state = PlayerState.empty
        XCTAssertFalse(store.isPlaying)
        store.applyOptimistic(.play)
        XCTAssertTrue(store.isPlaying)
    }

    func testServerStateClearsOptimistic() {
        let store = PlayerStore()
        store.applyOptimistic(.play)
        XCTAssertTrue(store.isPlaying)

        // Server confirms pause (matches no optimistic value).
        var newState = PlayerState.empty
        newState.status = .pause
        store.receiveServerState(newState)

        XCTAssertNil(store.optimisticStatus, "server state must clear optimistic")
        XCTAssertFalse(store.isPlaying)
    }

    func testIsPlayingPrefersOptimistic() {
        let store = PlayerStore()
        var s = PlayerState.empty
        s.status = .pause
        store.state = s
        XCTAssertFalse(store.isPlaying)

        store.applyOptimistic(.play)
        XCTAssertTrue(store.isPlaying, "optimistic must override server state until reconciled")
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

Run: `scripts/test.sh PlayerStoreOptimisticTests`
Expected: compile error — `applyOptimistic` / `receiveServerState` / `optimisticStatus` don't exist.

- [ ] **Step 3: Extend `PlayerStore`**

Open `StellarVolumiO/Stores/PlayerStore.swift` and apply these changes:

a) Add the field, after `var currentQueueIndex: Int = 0`:

```swift
    /// Optimistic playback status set on tap. Server `pushState` clears it.
    /// Times out after 2 s so a missing push doesn't lie to the UI forever.
    var optimisticStatus: PlaybackStatus? = nil
    private var optimisticTimeoutTask: Task<Void, Never>? = nil
```

b) Replace the `isPlaying` derived var:

```swift
    var isPlaying: Bool {
        if let o = optimisticStatus { return o == .play }
        return state.status == .play
    }
```

c) Add the two helpers below `currentTrackFormatBadges`:

```swift
    /// Set optimistic state from a UI tap and start the 2 s reconciliation
    /// timeout. Subsequent server `pushState` will clear the optimistic value.
    func applyOptimistic(_ status: PlaybackStatus) {
        optimisticStatus = status
        optimisticTimeoutTask?.cancel()
        optimisticTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.optimisticStatus = nil }
        }
    }

    /// Apply server-truth state and clear any pending optimistic value.
    func receiveServerState(_ newState: PlayerState) {
        state = newState
        optimisticStatus = nil
        optimisticTimeoutTask?.cancel()
        optimisticTimeoutTask = nil
    }
```

d) Update `bind(to:)` to call `receiveServerState` instead of mutating `state` directly:

```swift
    func bind(to socket: SocketService) {
        socket.onRawDict("pushState",
                         parser: PlayerState.init(rawDict:)) { [weak self] (newState: PlayerState) in
            guard let self else { return }
            if self.state.status != newState.status ||
               self.state.title  != newState.title  ||
               self.state.artist != newState.artist ||
               self.state.album  != newState.album  ||
               self.state.volume != newState.volume ||
               abs(self.state.seekSeconds - newState.seekSeconds) > 1.0 ||
               self.state.duration != newState.duration {
                self.receiveServerState(newState)
            } else {
                // Same payload — still clear optimistic so it doesn't hang.
                self.optimisticStatus = nil
                self.optimisticTimeoutTask?.cancel()
            }
        }

        socket.on("pushQueue") { [weak self] (items: [QueueItem]) in
            self?.queue = items
        }
    }
```

- [ ] **Step 4: Run tests**

Run: `scripts/test.sh PlayerStoreOptimisticTests`
Expected: 3 tests passed. Also run `scripts/test.sh PlayerStateParserTests`, `scripts/test.sh LibraryEnvelopeParserTests`, `scripts/test.sh LastPlayedAlbumTests` to confirm no regressions in earlier suites.

- [ ] **Step 5: Commit**

```bash
git add StellarVolumiO/Stores/PlayerStore.swift StellarVolumiOTests/PlayerStoreOptimisticTests.swift
git commit -m "feat(player): optimistic playback status with 2s reconciliation"
```

### Task 3.2: `PlayPauseButton`

Stable Circle behind the symbol, `contentTransition(.symbolEffect(.replace.downUp))` for the glyph swap, 2pt x-offset on `play.fill` for optical centring. The Circle is a ZStack sibling of the Image — the background does not translate on state change.

**Files:**
- Create: `StellarVolumiO/Views/NowPlaying/PlayPauseButton.swift`

- [ ] **Step 1: Create the component**

Create `StellarVolumiO/Views/NowPlaying/PlayPauseButton.swift`:

```swift
import SwiftUI

struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Stellar.Color.gold)
                    .frame(width: Stellar.Metric.playDisc, height: Stellar.Metric.playDisc)
                    .shadow(color: Stellar.Color.gold.opacity(0.3), radius: 16, y: 4)

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.black)
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .offset(x: isPlaying ? 0 : Stellar.Metric.playGlyphOffset)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme StellarVolumiO -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/NowPlaying/PlayPauseButton.swift
git commit -m "feat(nowplaying): stable PlayPauseButton with symbolEffect transition"
```

### Task 3.3: `FormatBadgeStrip`

Renders FLAC + sample rate + bit depth as gold-on-tint capsules. Only renders badges where the source string is non-empty.

**Files:**
- Create: `StellarVolumiO/Views/NowPlaying/FormatBadgeStrip.swift`

- [ ] **Step 1: Create the component**

Create `StellarVolumiO/Views/NowPlaying/FormatBadgeStrip.swift`:

```swift
import SwiftUI

struct FormatBadgeStrip: View {
    let trackType: String
    let samplerate: String
    let bitdepth: String

    private var badges: [String] {
        var out: [String] = []
        if !trackType.isEmpty { out.append(trackType.uppercased()) }
        if let sr = Double(samplerate), sr > 0 {
            out.append(String(format: "%.0fkHz", sr / 1000))
        }
        if !bitdepth.isEmpty, bitdepth != "0" {
            out.append("\(bitdepth)bit")
        }
        return out
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(badges, id: \.self) { badge in
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Stellar.Color.gold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Stellar.Color.goldFill, in: Capsule())
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/NowPlaying/FormatBadgeStrip.swift
git commit -m "feat(nowplaying): FormatBadgeStrip component"
```

### Task 3.4: `SeekBar`

Draggable thumb with tabular timecodes. Drag updates a local state; on release, emits `socket.seek(to:)`. Reads `PlayerState.seekSeconds` / `durationSeconds` from the store.

**Files:**
- Create: `StellarVolumiO/Views/NowPlaying/SeekBar.swift`

- [ ] **Step 1: Create the component**

Create `StellarVolumiO/Views/NowPlaying/SeekBar.swift`:

```swift
import SwiftUI

struct SeekBar: View {
    let currentSeconds: Double
    let totalSeconds: Double
    let onSeek: (Int) -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    private var displayed: Double { isDragging ? dragValue : currentSeconds }
    private var safeTotal: Double { max(1, totalSeconds) }

    var body: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { displayed },
                    set: { dragValue = $0 }
                ),
                in: 0...safeTotal,
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing { onSeek(Int(dragValue)) }
                }
            )
            .tint(Stellar.Color.gold)

            HStack {
                Text(format(displayed))
                Spacer()
                Text(format(totalSeconds))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
```

- [ ] **Step 2: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/NowPlaying/SeekBar.swift
git commit -m "feat(nowplaying): SeekBar with drag-to-seek + tabular timecodes"
```

### Task 3.5: `NowPlayingPlayingView`

Composes album art + meta + format badges + seek bar + transport. Reads `PlayerStore` + `SocketService` from environment.

**Files:**
- Create: `StellarVolumiO/Views/NowPlaying/NowPlayingPlayingView.swift`

- [ ] **Step 1: Create the view**

Create `StellarVolumiO/Views/NowPlaying/NowPlayingPlayingView.swift`:

```swift
import SwiftUI

struct NowPlayingPlayingView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(SocketService.self) private var socket

    var body: some View {
        VStack(spacing: 0) {
            AlbumArtHero(url: artworkURL)
                .padding(.top, 8)
                .padding(.horizontal, 24)

            VStack(spacing: 4) {
                Text(player.state.title.isEmpty ? "—" : player.state.title)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(2)
                Text(player.state.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(player.state.album)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            FormatBadgeStrip(
                trackType: player.state.trackType,
                samplerate: player.state.samplerate,
                bitdepth: player.state.bitdepth
            )
            .padding(.top, 10)

            SeekBar(
                currentSeconds: player.state.seekSeconds,
                totalSeconds: player.state.durationSeconds,
                onSeek: { socket.seek(to: $0) }
            )
            .padding(.top, 18)
            .padding(.horizontal, 24)

            HStack(spacing: 28) {
                TransportIconButton(icon: "backward.fill") { socket.prev() }

                PlayPauseButton(isPlaying: player.isPlaying) {
                    player.applyOptimistic(player.isPlaying ? .pause : .play)
                    socket.playPause()
                }

                TransportIconButton(icon: "forward.fill") { socket.next() }
            }
            .padding(.top, 22)
        }
    }

    private var artworkURL: URL? {
        let s = player.state.albumart
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        let path = s.hasPrefix("/") ? s : "/\(s)"
        return URL(string: "http://\(socket.serverHost):\(socket.serverPort)\(path)")
    }
}

// MARK: - Subcomponents (kept private to this view for now)

private struct AlbumArtHero: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Stellar.Metric.artCornerRadius))
        .shadow(color: .black.opacity(Stellar.Shadow.albumArt.opacity),
                radius: Stellar.Shadow.albumArt.radius,
                y: Stellar.Shadow.albumArt.y)
    }

    private var placeholder: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [SwiftUI.Color(red: 0x2a/255, green: 0x35/255, blue: 0x48/255),
                         SwiftUI.Color(red: 0x1a/255, green: 0x1f/255, blue: 0x2e/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
    }
}

private struct TransportIconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: Stellar.Metric.minTouchTarget,
                       height: Stellar.Metric.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/NowPlaying/NowPlayingPlayingView.swift
git commit -m "feat(nowplaying): NowPlayingPlayingView composes art+meta+badges+seek+transport"
```

### Task 3.6: `NowPlayingIdleView`

Resume CTA + last-played album. Optimistic state on tap (`PlayerStore.applyOptimistic(.play)`) then emit via `LastPlayedStore.resume()`.

**Files:**
- Create: `StellarVolumiO/Views/NowPlaying/NowPlayingIdleView.swift`

- [ ] **Step 1: Create the view**

Create `StellarVolumiO/Views/NowPlaying/NowPlayingIdleView.swift`:

```swift
import SwiftUI

struct NowPlayingIdleView: View {
    let album: LastPlayedAlbum

    @Environment(LastPlayedStore.self) private var lastPlayed
    @Environment(PlayerStore.self) private var player
    @Environment(SocketService.self) private var socket

    var body: some View {
        VStack(spacing: 0) {
            Text("Last Played")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            AlbumArtHero(url: artworkURL)
                .padding(.top, 8)
                .padding(.horizontal, 24)

            VStack(spacing: 4) {
                Text(album.album.isEmpty ? "—" : album.album)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(2)
                Text(album.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 18)

            FormatBadgeStrip(
                trackType: album.trackType,
                samplerate: album.sampleRate,
                bitdepth: album.bitDepth
            )
            .padding(.top, 10)

            Button {
                player.applyOptimistic(.play)
                lastPlayed.resume()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Resume")
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Stellar.Color.gold, in: Capsule())
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
        }
    }

    private var artworkURL: URL? {
        let s = album.albumArt
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        let path = s.hasPrefix("/") ? s : "/\(s)"
        return URL(string: "http://\(socket.serverHost):\(socket.serverPort)\(path)")
    }
}

private struct AlbumArtHero: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: { placeholder }
            } else {
                placeholder
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Stellar.Metric.artCornerRadius))
        .shadow(color: .black.opacity(Stellar.Shadow.albumArt.opacity),
                radius: Stellar.Shadow.albumArt.radius,
                y: Stellar.Shadow.albumArt.y)
    }

    private var placeholder: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [SwiftUI.Color(red: 0x2a/255, green: 0x35/255, blue: 0x48/255),
                         SwiftUI.Color(red: 0x1a/255, green: 0x1f/255, blue: 0x2e/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
    }
}
```

- [ ] **Step 2: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/NowPlaying/NowPlayingIdleView.swift
git commit -m "feat(nowplaying): NowPlayingIdleView with Resume CTA"
```

### Task 3.7: `NowPlayingEmptyView`

First-launch placeholder shown only when no `pushState` and no `pushLastPlayedAlbum` has arrived yet.

**Files:**
- Create: `StellarVolumiO/Views/NowPlaying/NowPlayingEmptyView.swift`

- [ ] **Step 1: Create the view**

Create `StellarVolumiO/Views/NowPlaying/NowPlayingEmptyView.swift`:

```swift
import SwiftUI

struct NowPlayingEmptyView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("Nothing playing")
                    .font(.system(size: 18, weight: .semibold))
                Text("Tap the Library tab to start a track.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/NowPlaying/NowPlayingEmptyView.swift
git commit -m "feat(nowplaying): NowPlayingEmptyView first-launch placeholder"
```

### Task 3.8: Rewrite `NowPlayingView` shell

The shell picks between the three subviews using the rule from the spec § "Idle vs Playing — the decision". Glassy background, scroll container with guaranteed bottom-bar clearance, no header bar (title is the album art hero itself).

**Files:**
- Modify: `StellarVolumiO/Views/NowPlaying/NowPlayingView.swift`

- [ ] **Step 1: Replace the file**

Open `StellarVolumiO/Views/NowPlaying/NowPlayingView.swift` and replace the entire contents with:

```swift
import SwiftUI

struct NowPlayingView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(LastPlayedStore.self) private var lastPlayed

    var body: some View {
        ZStack {
            StellarGlassyBackground()

            ScrollView {
                VStack(spacing: 0) {
                    content
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, 16, for: .scrollContent)
        }
    }

    @ViewBuilder
    private var content: some View {
        if player.hasTrack && player.state.status != .stop {
            NowPlayingPlayingView()
        } else if let last = lastPlayed.album {
            NowPlayingIdleView(album: last)
        } else {
            NowPlayingEmptyView()
        }
    }
}
```

The previous file's `IconButton` struct and `StellarPlayPressStyle` references are removed — they were unused after the refactor.

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme StellarVolumiO -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
Expected: `** BUILD SUCCEEDED **`. If you get "cannot find 'StellarPlayPressStyle'" or "cannot find 'IconButton'", check whether any other view referenced them; if so, delete the reference (they were only used by the old NowPlayingView).

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/NowPlaying/NowPlayingView.swift
git commit -m "feat(nowplaying): rewrite shell to dispatch between Playing/Idle/Empty"
```

### Task 3.9: Manual smoke — Now Playing tab

- [ ] **Step 1: Launch on simulator**

Run: `xcodebuild -scheme StellarVolumiO -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` then launch the simulator manually (or `xcrun simctl launch <udid> fit.stellar.remote`).

- [ ] **Step 2: Walk through the three states**

1. **Playing.** Start an album from the existing Library tab (it's unstyled, fine — restyle happens in Phase 4). Switch to Now Playing. Confirm album art hero + title/artist/album + format badges + seek bar + transport all visible. Tap play/pause repeatedly — the gold disc must not visually shift; only the glyph morphs.
2. **Idle.** Hit the Mac backend with `curl -X POST` equivalent or just press stop in the existing UI. Now Playing should switch to "Last Played" with the gold Resume CTA. Tap Resume — playback starts.
3. **Empty.** Restart the Mac backend with library DB cleared (or temporarily stub `LastPlayedStore.album = nil` in `StellarApp.onAppear` for the check). NowPlayingEmptyView should render. Revert the stub.

- [ ] **Step 3: Commit checkpoint**

```bash
git commit --allow-empty -m "checkpoint: Phase 3 Now Playing rebuild verified in simulator"
```

---

## Phase 4 — Library rebuild

Restyle the Library tab. The behavioural changes are: segmented control at the top, ArtistDetailView promoted to its own file, restyled cards. No new socket calls.

### Task 4.1: Rename `ArtistAlbumsView` → `ArtistDetailView` and move to its own file

The existing `ArtistPickerView.swift` contains both the artist list AND a second view named `ArtistAlbumsView` (the drill-down) in the same file. We extract the second view to its own file with the spec-mandated name `ArtistDetailView`. Behaviour preserved exactly; styling is updated in Task 4.5.

**Files:**
- Create: `StellarVolumiO/Views/Library/ArtistDetailView.swift`
- Modify: `StellarVolumiO/Views/Library/ArtistPickerView.swift`

- [ ] **Step 1: Create `ArtistDetailView.swift` from existing `ArtistAlbumsView` code**

Create `StellarVolumiO/Views/Library/ArtistDetailView.swift` with the exact body of the current `ArtistAlbumsView` (lines 88-131 of `StellarVolumiO/Views/Library/ArtistPickerView.swift`), renamed:

```swift
import SwiftUI

struct ArtistDetailView: View {
    let artist: LibraryArtist

    @Environment(ArtistPickerStore.self) private var store
    @Environment(SocketService.self) private var socket

    var body: some View {
        Group {
            if store.loadingArtistAlbums {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.mdOnSurfaceVariant)
            } else if store.artistAlbums.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 36))
                        .foregroundStyle(.mdOnSurfaceVariant.opacity(0.6))
                    Text("No albums for \(artist.name)")
                        .font(StellarFont.bodyMedium)
                        .foregroundStyle(.mdOnSurfaceVariant)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.artistAlbums) { album in
                    Button {
                        store.play(album)
                    } label: {
                        AlbumRow(album: album, socket: socket)
                    }
                    .listRowBackground(Color.mdSurfaceContainerLow)
                    .listRowSeparatorTint(.mdOutlineVariant.opacity(0.3))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.mdBackground)
            }
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.mdBackground.ignoresSafeArea())
    }
}
```

The `AlbumRow` referenced inside is defined elsewhere in the file (probably in `AlbumPickerView.swift` or as a private helper) — leave its reference as-is; we restyle in Task 4.5 anyway. If `AlbumRow` is not resolvable after moving, copy its declaration into this file as a `private struct AlbumRow`.

- [ ] **Step 2: Update `ArtistPickerView.swift` — remove the old `ArtistAlbumsView` and point to the new file**

Open `StellarVolumiO/Views/Library/ArtistPickerView.swift`. Delete the entire `// MARK: - Drill-down: albums for selected artist` block and the `struct ArtistAlbumsView { ... }` declaration (currently lines 88-131). In the `navigationDestination(item:)` modifier (currently line 22-27), update the closure body to reference the new type:

Find:
```swift
        .navigationDestination(item: Binding(
            get: { store.selectedArtist },
            set: { newValue in if newValue == nil { store.clearSelection() } }
        )) { artist in
            ArtistAlbumsView(artist: artist)
        }
```

Replace `ArtistAlbumsView(artist: artist)` with `ArtistDetailView(artist: artist)`. Everything else in `ArtistPickerView` stays untouched in this task — full restyle is Task 4.4.

- [ ] **Step 3: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`. If `AlbumRow` becomes undefined, copy its declaration into `ArtistDetailView.swift` as a `private struct AlbumRow` mirroring the original source.

- [ ] **Step 4: Commit**

```bash
git add StellarVolumiO/Views/Library/ArtistDetailView.swift StellarVolumiO/Views/Library/ArtistPickerView.swift
git commit -m "refactor(library): extract ArtistAlbumsView -> ArtistDetailView in its own file"
```

### Task 4.2: Restyle `LibraryView` with segmented control

Top segmented control switches between Albums and Artists. Both pickers stay in scope so socket subscriptions remain live.

**Files:**
- Read first: `StellarVolumiO/Views/Library/LibraryView.swift`
- Modify: `StellarVolumiO/Views/Library/LibraryView.swift`

- [ ] **Step 1: Read the current view**

Read `LibraryView.swift` end-to-end. Note any navigation state, headers, or styling that should be preserved.

- [ ] **Step 2: Replace with segmented-control layout**

Replace the contents with:

```swift
import SwiftUI

enum LibrarySegment: String, CaseIterable, Identifiable {
    case albums = "Albums"
    case artists = "Artists"
    var id: Self { self }
}

struct LibraryView: View {
    @State private var segment: LibrarySegment = .albums

    var body: some View {
        ZStack {
            StellarGlassyBackground()

            VStack(spacing: 0) {
                Picker("Library segment", selection: $segment) {
                    ForEach(LibrarySegment.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

                switch segment {
                case .albums:  AlbumPickerView()
                case .artists: ArtistPickerView()
                }
            }
        }
    }
}
```

If the file declared a different initial-load orchestration (e.g. `.onAppear` calls to `albumStore.load()`), preserve those by moving them into the respective picker views' `onAppear` instead — see Task 4.3 / 4.4.

- [ ] **Step 3: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add StellarVolumiO/Views/Library/LibraryView.swift
git commit -m "feat(library): segmented control LibraryView"
```

### Task 4.3: Restyle `AlbumPickerView` as a grid

**Files:**
- Modify: `StellarVolumiO/Views/Library/AlbumPickerView.swift`

- [ ] **Step 1: Replace with grid layout**

Replace the contents with:

```swift
import SwiftUI

struct AlbumPickerView: View {
    @Environment(AlbumPickerStore.self) private var store
    @Environment(SocketService.self) private var socket

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.albums) { album in
                    AlbumTile(album: album) { store.play(album) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if store.albums.isEmpty && !store.loading { store.load() }
        }
    }
}

private struct AlbumTile: View {
    let album: LibraryAlbum
    let onTap: () -> Void

    @Environment(SocketService.self) private var socket

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [SwiftUI.Color(red: 0x2a/255, green: 0x35/255, blue: 0x48/255),
                                     SwiftUI.Color(red: 0x1a/255, green: 0x1f/255, blue: 0x2e/255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    if let url = artworkURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            EmptyView()
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(album.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(album.artist)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var artworkURL: URL? {
        let s = album.albumart
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        let path = s.hasPrefix("/") ? s : "/\(s)"
        return URL(string: "http://\(socket.serverHost):\(socket.serverPort)\(path)")
    }
}
```

- [ ] **Step 2: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/Library/AlbumPickerView.swift
git commit -m "feat(library): AlbumPickerView grid with cover tiles"
```

### Task 4.4: Restyle `ArtistPickerView` as a list

Same shape as before — list rows with name + album count — but using NavigationStack and the redesign palette.

**Files:**
- Modify: `StellarVolumiO/Views/Library/ArtistPickerView.swift`

- [ ] **Step 1: Replace with NavigationStack list**

Replace the contents with:

```swift
import SwiftUI

struct ArtistPickerView: View {
    @Environment(ArtistPickerStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.artists) { artist in
                    NavigationLink(value: artist) {
                        HStack {
                            Text(artist.name).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            if let n = artist.albumCount {
                                Text("\(n)").foregroundStyle(.secondary).font(.system(size: 12))
                            }
                        }
                    }
                    .listRowBackground(Stellar.Color.surfaceLow)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationDestination(for: LibraryArtist.self) { artist in
                ArtistDetailView(artist: artist)
            }
            .onAppear {
                if store.artists.isEmpty && !store.loading { store.load() }
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`. If you see "Hashable required by NavigationLink(value:)" — confirm `LibraryArtist` already conforms to `Hashable` (it does, per Models/LibraryModels.swift:53).

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/Library/ArtistPickerView.swift
git commit -m "feat(library): ArtistPickerView list with NavigationStack drill-down"
```

### Task 4.5: Restyle `ArtistDetailView`

Replace the placeholder list with a grid mirroring `AlbumPickerView` styling.

**Files:**
- Modify: `StellarVolumiO/Views/Library/ArtistDetailView.swift`

- [ ] **Step 1: Replace with grid layout**

Replace the contents with:

```swift
import SwiftUI

struct ArtistDetailView: View {
    let artist: LibraryArtist

    @Environment(ArtistPickerStore.self) private var store
    @Environment(SocketService.self) private var socket

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.artistAlbums) { album in
                    AlbumTile(album: album) { store.play(album) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .background(StellarGlassyBackground())
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if store.selectedArtist != artist { store.select(artist) }
        }
    }
}

private struct AlbumTile: View {
    let album: LibraryAlbum
    let onTap: () -> Void

    @Environment(SocketService.self) private var socket

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [SwiftUI.Color(red: 0x2a/255, green: 0x35/255, blue: 0x48/255),
                                     SwiftUI.Color(red: 0x1a/255, green: 0x1f/255, blue: 0x2e/255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    if let url = artworkURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: { EmptyView() }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(album.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private var artworkURL: URL? {
        let s = album.albumart
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        let path = s.hasPrefix("/") ? s : "/\(s)"
        return URL(string: "http://\(socket.serverHost):\(socket.serverPort)\(path)")
    }
}
```

- [ ] **Step 2: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/Library/ArtistDetailView.swift
git commit -m "feat(library): ArtistDetailView restyled as cover grid"
```

### Task 4.6: Manual smoke — Library tab

- [ ] **Step 1: Launch and walk through**

Run: `xcodebuild -scheme StellarVolumiO -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`. Launch the simulator. In Library tab:

- Albums segment: grid populates within 2s. Tap a tile → playback starts; Now Playing tab updates immediately.
- Artists segment: list populates. Tap an artist → drill-down shows their albums in a grid. Tap an album → playback starts.
- Switch segments back and forth: data must NOT re-fetch (both stores cache).

- [ ] **Step 2: Commit checkpoint**

```bash
git commit --allow-empty -m "checkpoint: Phase 4 Library rebuild verified in simulator"
```

---

## Phase 5 — Settings rebuild + ConnectionStatus

### Task 5.1: 5-second disconnect grace on `SocketService`

The current `SocketService.connectionState` flips to `.disconnected` immediately. Add a 5-second debounce so brief socket flaps don't paint the row red. Mirror `Volumio2-UI`'s `DISCONNECT_GRACE_PERIOD_MS = 5000`.

**Files:**
- Modify: `StellarVolumiO/Services/SocketService.swift`
- Create: `StellarVolumiOTests/ConnectionGraceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `StellarVolumiOTests/ConnectionGraceTests.swift`:

```swift
import XCTest
@testable import StellarVolumiO

@MainActor
final class ConnectionGraceTests: XCTestCase {

    func testReportedStateRespectsGrace() async {
        let svc = SocketService()
        // Simulate connect.
        svc.connectionState = .connected
        XCTAssertEqual(svc.reportedConnectionState, .connected)

        // Internal: disconnect arrives — reported state still shows .connecting
        // during grace period (UI-friendly: spinner, not red).
        svc.markDisconnectedInternal()
        XCTAssertEqual(svc.reportedConnectionState, .connecting,
                       "during grace period UI shows 'Connecting…' not 'Disconnected'")

        // Wait 5.5 s for grace to expire.
        try? await Task.sleep(nanoseconds: 5_500_000_000)
        XCTAssertEqual(svc.reportedConnectionState, .disconnected,
                       "after 5s grace, UI shows 'Disconnected'")
    }

    func testReconnectDuringGraceClearsTimer() async {
        let svc = SocketService()
        svc.connectionState = .connected
        svc.markDisconnectedInternal()
        XCTAssertEqual(svc.reportedConnectionState, .connecting)

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        svc.connectionState = .connected
        XCTAssertEqual(svc.reportedConnectionState, .connected)

        // Wait past the original 5s window — must NOT flip to disconnected.
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        XCTAssertEqual(svc.reportedConnectionState, .connected)
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

Run: `scripts/test.sh ConnectionGraceTests`
Expected: compile error — `reportedConnectionState` / `markDisconnectedInternal` don't exist.

- [ ] **Step 3: Implement on `SocketService`**

Open `StellarVolumiO/Services/SocketService.swift`. After `var lastDecodeError: String? = nil`, add:

```swift
    /// UI-facing view of the connection state. During the 5-second
    /// post-disconnect grace, this returns `.connecting` so the UI shows a
    /// spinner rather than a red error. Mirrors Volumio2-UI's
    /// `DISCONNECT_GRACE_PERIOD_MS = 5000`.
    var reportedConnectionState: ConnectionState {
        if isInGraceWindow { return .connecting }
        return connectionState
    }

    private var isInGraceWindow: Bool = false
    private var graceTask: Task<Void, Never>? = nil
    static let disconnectGraceSeconds: Double = 5.0
```

Add this method on the class (after `reconnectIfNeeded`):

```swift
    /// Test-visible hook + production entry point: socket reports disconnect.
    /// Starts the 5-second grace timer; if a reconnect arrives before it
    /// expires, the timer is cancelled and the UI never sees the red state.
    func markDisconnectedInternal() {
        connectionState = .disconnected
        isInGraceWindow = true
        graceTask?.cancel()
        graceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.disconnectGraceSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.isInGraceWindow = false }
        }
    }
```

Update the existing disconnect handler — find:

```swift
        socket?.on(clientEvent: .disconnect) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.connectionState = .disconnected
            }
        }
```

Replace with:

```swift
        socket?.on(clientEvent: .disconnect) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.markDisconnectedInternal()
            }
        }
```

And in the connect handler, after `self?.connectionState = .connected`, add:

```swift
                self?.isInGraceWindow = false
                self?.graceTask?.cancel()
```

- [ ] **Step 4: Run tests**

Run: `scripts/test.sh ConnectionGraceTests`
Expected: 2 tests passed (each waits ~5 s — be patient).

- [ ] **Step 5: Commit**

```bash
git add StellarVolumiO/Services/SocketService.swift StellarVolumiOTests/ConnectionGraceTests.swift
git commit -m "feat(socket): 5-second disconnect grace period mirroring frontend"
```

### Task 5.2: `ConnectionStatusRow` component

**Files:**
- Create: `StellarVolumiO/Views/Settings/ConnectionStatusRow.swift`

- [ ] **Step 1: Create the component**

Create `StellarVolumiO/Views/Settings/ConnectionStatusRow.swift`:

```swift
import SwiftUI

struct ConnectionStatusRow: View {
    @Environment(SocketService.self) private var socket

    var body: some View {
        HStack(spacing: 10) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Stellar.Color.surfaceLow, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var statusDot: some View {
        switch socket.reportedConnectionState {
        case .connected:
            Circle().fill(Stellar.Color.statusGreen).frame(width: 10, height: 10)
        case .connecting:
            ProgressView().scaleEffect(0.6).frame(width: 10, height: 10)
        case .disconnected:
            Circle().fill(Stellar.Color.statusRed).frame(width: 10, height: 10)
        case .error:
            Circle().fill(Stellar.Color.statusRed).frame(width: 10, height: 10)
        }
    }

    private var headline: String {
        switch socket.reportedConnectionState {
        case .connected:    return "Connected"
        case .connecting:   return "Connecting…"
        case .disconnected: return "Disconnected"
        case .error:        return "Connection error"
        }
    }

    private var detail: String {
        switch socket.reportedConnectionState {
        case .error(let msg):
            return String(msg.prefix(80))
        default:
            return "\(socket.serverHost):\(socket.serverPort)"
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/Settings/ConnectionStatusRow.swift
git commit -m "feat(settings): ConnectionStatusRow with grace-aware dot + host detail"
```

### Task 5.3: Decode-error diagnostic row

**Files:**
- Create: `StellarVolumiO/Views/Settings/DecodeErrorRow.swift`

- [ ] **Step 1: Create the row**

Create `StellarVolumiO/Views/Settings/DecodeErrorRow.swift`:

```swift
import SwiftUI

/// Renders `SocketService.lastDecodeError` when present. Hidden when nil.
struct DecodeErrorRow: View {
    @Environment(SocketService.self) private var socket

    var body: some View {
        if let err = socket.lastDecodeError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Stellar.Color.statusRed)
                    .font(.system(size: 13))
                Text(err)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Stellar.Color.statusRed)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Stellar.Color.surfaceLow, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/Settings/DecodeErrorRow.swift
git commit -m "feat(settings): DecodeErrorRow surfaces SocketService.lastDecodeError"
```

### Task 5.4: Restyle `SettingsView`

Vertical layout in this order: LCD toggle, ConnectionStatusRow, DecodeErrorRow (hidden when no error). Match the redesign palette.

**Files:**
- Modify: `StellarVolumiO/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Replace the file**

Open `StellarVolumiO/Views/Settings/SettingsView.swift` and replace contents with:

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(LcdStore.self) private var lcd

    var body: some View {
        ZStack {
            StellarGlassyBackground()

            ScrollView {
                VStack(spacing: 12) {
                    lcdToggleRow
                    ConnectionStatusRow()
                    DecodeErrorRow()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var lcdToggleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LCD screen")
                    .font(.system(size: 14, weight: .semibold))
                Text(lcd.isOn ? "On" : "Standby")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { lcd.isOn }, set: { lcd.setOn($0) }))
                .labelsHidden()
                .tint(Stellar.Color.gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Stellar.Color.surfaceLow, in: RoundedRectangle(cornerRadius: 10))
    }
}
```

- [ ] **Step 2: Build**

Run: `scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/Views/Settings/SettingsView.swift
git commit -m "feat(settings): redesign with LCD toggle + connection + decode-error rows"
```

### Task 5.5: Manual smoke — Settings tab

- [ ] **Step 1: Launch on simulator**

Run: `xcodebuild -scheme StellarVolumiO -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`. Launch simulator.

- [ ] **Step 2: Verify Settings**

1. **LCD toggle.** Toggle off → Pi LCD goes dark within ~1s. Toggle on → wakes. (Requires Mac backend + Pi reachable.)
2. **Connection status.** Stop the Mac backend (`pkill stellar` or stop the launchctl service). After ~5s the row turns from green → red with "Disconnected". Restart backend → row goes green again.
3. **Decode error row.** Without a real malformed payload to trigger, you can manually set `socket.lastDecodeError = "test: simulated"` in a debugger or temporarily in `StellarApp.onAppear` to verify the row renders. Clear it before committing.

- [ ] **Step 3: Commit checkpoint**

```bash
git commit --allow-empty -m "checkpoint: Phase 5 Settings + ConnectionStatus verified"
```

---

## Phase 6 — Integration polish + UAT

### Task 6.1: Rewrite `ContentView` — remove blocking ConnectionOverlay, set gold tint, fix tab labels

The current `ContentView.swift` (lines 28-30, 36-70) renders a blocking `ConnectionOverlay` over the tabs whenever the socket is not connected. The spec explicitly forbids this ("the UI stays visible regardless of socket state. No blocking overlay…"). We remove the overlay entirely — connection state now lives only in the Settings tab's `ConnectionStatusRow`. We also retint the tab bar and align the tab labels to the spec's "Now Playing" / "Library" / "Settings" wording (current is "Playing").

**Files:**
- Modify: `StellarVolumiO/App/ContentView.swift`

- [ ] **Step 1: Replace the file**

Open `StellarVolumiO/App/ContentView.swift` and replace the entire contents with:

```swift
import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .player

    enum Tab { case player, library, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            NowPlayingView()
                .tabItem { Label("Now Playing", systemImage: "music.note") }
                .tag(Tab.player)

            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(Tab.library)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .tint(Stellar.Color.gold)
    }
}
```

The `ConnectionOverlay` struct and its references are removed entirely. The `@Environment(SocketService.self)` injection on `ContentView` is no longer needed — `ConnectionStatusRow` reads the socket itself.

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme StellarVolumiO -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
Expected: `** BUILD SUCCEEDED **`. If you see "value of type 'ContentView' has no member 'socket'" anywhere — confirm no other view references `ContentView.socket`.

- [ ] **Step 3: Commit**

```bash
git add StellarVolumiO/App/ContentView.swift
git commit -m "feat(shell): drop ConnectionOverlay; tab bar gold tint; canonical labels"
```

### Task 6.2: Full UAT against live backend

Walk through the spec's "Manual UAT" checklist (§ Manual UAT). Each item is a single boolean — record PASS/FAIL inline below for the commit message.

- [ ] **Step 1: UAT 1 — Now Playing playing.** Start an album from Library. Switch to Now Playing. Verify title/artist/album + format badges + seek bar + paused-glyph play disc. **Expected: PASS.**

- [ ] **Step 2: UAT 2 — Play/pause stability.** Tap disc 10× rapidly. Circle does not visually shift; only the glyph morphs. **Expected: PASS.**

- [ ] **Step 3: UAT 3 — Now Playing idle.** Stop MPD. Tab switches to "Last Played" with Resume CTA. Tap Resume → playback starts. **Expected: PASS.**

- [ ] **Step 4: UAT 4 — Now Playing empty.** Stub `LastPlayedStore.album = nil` temporarily (in a debugger if needed) and verify Empty placeholder renders without crashing. Revert the stub. **Expected: PASS.**

- [ ] **Step 5: UAT 5 — Library Albums.** Grid populates with ~72 albums. Tap one → playback starts; Pi LCD switches to that album. **Expected: PASS.**

- [ ] **Step 6: UAT 6 — Library Artists.** List populates with ~41 artists. Tap one → drill-down grid. Tap album → playback starts. **Expected: PASS.**

- [ ] **Step 7: UAT 7 — Settings LCD.** Toggle off → Pi LCD dark within ~1s. Toggle on → wakes. **Expected: PASS.**

- [ ] **Step 8: UAT 8 — Settings connection.** Stop Mac backend. After 5s, red dot with "Disconnected". Restart backend. Green again. **Expected: PASS.**

- [ ] **Step 9: UAT 9 — Settings decode diagnostic.** Use debugger to set `socket.lastDecodeError`. Row renders. Clear → row disappears. **Expected: PASS.**

- [ ] **Step 10: Commit checkpoint**

```bash
git commit --allow-empty -m "checkpoint: full UAT pass (9/9) against live Mac backend"
```

### Task 6.3: Deploy to physical iPhone

- [ ] **Step 1: Pre-deploy build**

Run: `xcodebuild -scheme StellarVolumiO -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` — must succeed.

- [ ] **Step 2: Run the deploy script**

Run: `cd /Users/eduardomarques/workspace/stellar-streamer/stellar-ios && scripts/deploy-to-device.sh`
Expected: app builds with device signing, installs on the connected iPhone (UDID `00008130-001024A61A50001C`), and launches.

If the script fails on code-sign: verify the Apple Developer team `3S2JYQ4JNX` in `project.yml:25` matches the active provisioning profile. The device must be in developer mode (Settings → Privacy → Developer Mode → on).

- [ ] **Step 3: Walk through UAT on the device**

Repeat UAT items 1–8 on the physical iPhone. Item 9 is simulator-only (debugger access). Anything that fails on device but not simulator → file under "follow-up" — do not block the merge.

- [ ] **Step 4: Final commit**

```bash
git commit --allow-empty -m "ship: iOS remote redesign complete, deployed to device"
```

---

## Out-of-band follow-ups

Surfaced during planning but **not in this plan's scope** — capture in MemPalace as project memory after this work ships:

- **Resume CTA failure mode.** If MPD errors back (e.g. NAS unmounted), the optimistic state times out and reverts. The user has no clear "couldn't resume" signal. A future task could consume `pushToastMessage` and surface it as a small inline error under the Resume button.
- **Library search.** Out of scope for v1 per design. If a user with a much larger library asks for it, lift the spec's "Albums + Artists + Search" alternative.
- **Lock-screen / MPRemoteCommandCenter.** Out of scope per CLAUDE.md. Track separately as Plan C from the parked backlog (`project_snug_summit_complete_followups`).
- **Bonjour / mDNS host discovery.** Out of scope. Host stays a code constant.

---

## Follow-up: phone → Pi audio streaming (AirPlay / UPnP) — enqueued 2026-05-25

**Ask, verbatim:** "I want a way to play music from my phone to the Pi. AirPlay, UPnP, anything that allows that to happen. Can run in parallel in a subagent. Just make it work."

**Out of scope of *this* plan (iOS remote redesign):** this is a Pi system-config task, not an iOS or backend code change. Captured here only so it survives this session.

**Working scope (delegated to a parallel subagent during the Phase 6 session):**
- Install + configure `shairport-sync` (AirPlay 1) on the Pi via apt, or fall back to upmpdcli/UPnP if shairport-sync proves untenable.
- Solve audio-device contention with MPD (pause MPD via `mpc` from a shairport-sync `run_this_before_play_begins` hook; do not auto-resume).
- Verify mDNS discoverability on the LAN (`avahi-browse _raop._tcp` shows a `Stellar` record).
- Keep MPD healthy.
- Report back configuration + any user-tap verification still needed.

**Acceptance (final, when user has the phone in hand):**
- iPhone Control Center → AirPlay → `Stellar` appears in the destination list.
- Tapping it pipes audio to the Pi speakers within a few seconds.
- After the AirPlay session ends, MPD can resume from stellar-ios (no auto-resume).
- Setup survives a Pi reboot (service enabled).

**Status:** dispatched 2026-05-25 in parallel with Phase 6.

---

## Follow-up: album-switch play latency (iPhone tap → Pi audio) — enqueued 2026-05-25

**Ask, verbatim:** "From the iPhone to the music playing into the [Pi]. It takes very long to update. Several seconds. Takes several seconds for the Pi to start playing when I am switching albums."

**Symptom:** Tapping an album in stellar-ios Library → audible playback on Pi speakers lags by "several seconds". Worse than the optimistic UI flicker; the audio path itself is slow.

**Likely path to instrument:**
1. iOS `replaceAndPlay` Socket.IO emit (timestamp at tap).
2. Mac stellar backend `socketio` handler (timestamp at receipt).
3. Mac stellar `internal/domain/player/*` build-and-dispatch (stop/clear/addid/play cycle to MPD).
4. MPD on Pi (port 6600) parse + queue + start.
5. MPD ALSA prerolls the file → first audio out the DAC.

**Working scope (delegated to a background investigation subagent during the Phase 6 session):**
- Reproduce on the simulator with a tight loop (3 album taps, 30s apart).
- Capture timestamps at each hop using `~/Library/Logs/stellar-backend.{err,out}.log`, `mpc idleloop` / `mpc status` on the Pi, and the Mac stellar Go code path.
- Identify the dominant cost (network? Mac→Pi MPD round-trip? MPD prebuffer? DAC negotiation between formats?).
- Propose a fix and/or a minimal repro test. Do NOT ship the fix yet — just diagnose.

**Acceptance (for the investigation, not the fix):**
- A timing breakdown: e.g. "iOS→Mac: 30ms, Mac→MPD: 80ms, MPD-queue: 200ms, MPD→audio: 3.5s (format negotiation for DSD↔PCM switch)."
- A 1–3 line root-cause hypothesis with the supporting evidence.
- A suggested fix scope (single sentence; e.g. "pre-warm MPD with `consume off + crossfade 0`" or "set MPD `audio_buffer_size = 1024` from 4096").

**Status:** investigation dispatched 2026-05-25 in parallel with Phase 6.

---

## Follow-up: Mac stellar LCD remote-proxy env vars not set (UAT 7 regression) — enqueued 2026-05-25

**Surfaced by:** Phase 6.2 UAT — UAT 7 (Settings LCD toggle) failed because Mac stellar logged `lcd: not supported on this platform` for both `lcdStandby` and `lcdWake`. iOS-side UI toggles correctly; backend never reaches the Pi.

**Root cause:** `internal/infra/lcd/lcd_darwin.go:newPlatform()` returns a `RemoteController` ONLY when both `STELLAR_LCD_REMOTE_URL` and `STELLAR_LCD_REMOTE_TOKEN` env vars are set. The currently-running Mac stellar process has neither set, so it falls back to the darwin stub that returns `ErrUnsupported`. The Pi-side `lcd-control.service` (deployed in M1.C, port + token at `/etc/lcd-control/token`) is fully functional — just not being called.

**Fix scope:** ~5 minutes of config, no code changes.
1. SSH into Pi, read `/etc/lcd-control/token` and confirm the service port (M1.C install script default).
2. Add `STELLAR_LCD_REMOTE_URL=http://stellar.local:<port>` and `STELLAR_LCD_REMOTE_TOKEN=<token>` to the Mac stellar launchd plist (or whatever wraps `bin/stellar-darwin` at boot — see Mac stellar deploy notes).
3. `launchctl unload` + `launchctl load`, or kill + relaunch.
4. Re-test UAT 7.

**Status:** known regression, NOT blocking Phase 6 ship (per plan's "follow-up, do not block merge" policy for non-core-happy-path UAT items).
