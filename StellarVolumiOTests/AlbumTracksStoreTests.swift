import XCTest
@testable import StellarVolumiO

/// Coverage for `AlbumTracksStore` — the store that backs the new Album Tracks
/// screen. The contract is:
///
/// 1. `load(album:albumArtist:uri:)` emits `library:album:tracks` with the
///    matching payload (uses the DEBUG `lastEmittedObjectPayload` hook on
///    SocketService — production code never reads it).
/// 2. When the bound handler fires with a payload, `tracks` updates, `loading`
///    flips false, `errorMessage` clears.
/// 3. When the payload carries `error`, `errorMessage` is set and `tracks` is
///    emptied (per the backend contract — error payloads are otherwise empty).
@MainActor
final class AlbumTracksStoreTests: XCTestCase {

    func testLoadEmitsRequestWithFullPayload() {
        let socket = SocketService()
        socket.resetEmittedObjectCapture()
        let store = AlbumTracksStore()
        store.bind(to: socket)

        store.load(album: "Kind of Blue",
                   albumArtist: "Miles Davis",
                   uri: "NAS/Miles Davis/Kind of Blue")

        XCTAssertEqual(socket.lastEmittedObjectEvent, "library:album:tracks",
                       "load() must emit the canonical library:album:tracks event")
        let payload = socket.lastEmittedObjectPayload ?? [:]
        XCTAssertEqual(payload["album"]       as? String, "Kind of Blue")
        XCTAssertEqual(payload["albumArtist"] as? String, "Miles Davis")
        XCTAssertEqual(payload["uri"]         as? String, "NAS/Miles Davis/Kind of Blue")
        XCTAssertTrue(store.loading, "load() must flip loading=true until the push lands")
    }

    func testLoadEmitsRequestOmitsEmptyOptionalKeys() {
        // albumArtist nil and uri nil must not appear in the payload at all —
        // the backend's `albumArtist` / `uri` lookups use presence-checks, so
        // empty strings would skew the album-name-only path.
        let socket = SocketService()
        socket.resetEmittedObjectCapture()
        let store = AlbumTracksStore()
        store.bind(to: socket)

        store.load(album: "Blue", albumArtist: nil, uri: nil)

        let payload = socket.lastEmittedObjectPayload ?? [:]
        XCTAssertEqual(payload["album"] as? String, "Blue")
        XCTAssertNil(payload["albumArtist"], "nil albumArtist must be absent, not empty-string")
        XCTAssertNil(payload["uri"], "nil uri must be absent, not empty-string")
    }

    func testApplyPopulatesTracks() {
        let socket = SocketService()
        let store = AlbumTracksStore()
        store.bind(to: socket)
        store.loading = true
        store.errorMessage = "stale"

        let payload = PushLibraryAlbumTracks(rawDict: [
            "album": "Kind of Blue",
            "albumArtist": "Miles Davis",
            "tracks": [
                ["title": "So What",      "artist": "Miles Davis", "album": "Kind of Blue",
                 "uri": "NAS/Miles Davis/Kind of Blue/01.flac",
                 "trackNumber": 1, "duration": 545,
                 "albumArt": "/albumart?path=NAS/Miles%20Davis/Kind%20of%20Blue",
                 "source": "mpd"],
                ["title": "Freddie Freeloader", "artist": "Miles Davis", "album": "Kind of Blue",
                 "uri": "NAS/Miles Davis/Kind of Blue/02.flac",
                 "trackNumber": 2, "duration": 583,
                 "source": "mpd"]
            ],
            "totalDuration": 1128
        ])!

        store.apply(payload)

        XCTAssertEqual(store.tracks.count, 2)
        XCTAssertEqual(store.tracks[0].title, "So What")
        XCTAssertEqual(store.tracks[0].trackNumber, 1)
        XCTAssertEqual(store.tracks[0].duration, 545)
        XCTAssertEqual(store.tracks[1].title, "Freddie Freeloader")
        XCTAssertFalse(store.loading, "loading must flip off after payload arrives")
        XCTAssertNil(store.errorMessage, "successful payload must clear any stale error")
        XCTAssertEqual(store.totalDuration, 1128)
    }

    func testApplyErrorClearsTracksAndSurfacesMessage() {
        let socket = SocketService()
        let store = AlbumTracksStore()
        store.bind(to: socket)
        // Pre-load a track so we can prove apply(error) wipes it.
        store.tracks = [
            Track(id: "x", title: "Old", artist: "X", album: "Y",
                  uri: "u", trackNumber: 1, duration: 60,
                  albumArt: "", source: "mpd")
        ]
        store.loading = true

        let payload = PushLibraryAlbumTracks(rawDict: [
            "album": "Kind of Blue",
            "albumArtist": "Miles Davis",
            "tracks": [],
            "totalDuration": 0,
            "error": "album not found"
        ])!

        store.apply(payload)

        XCTAssertTrue(store.tracks.isEmpty, "error payload must clear tracks")
        XCTAssertEqual(store.errorMessage, "album not found")
        XCTAssertFalse(store.loading, "loading must flip off even on error")
    }

    func testLoadWithoutSocketBoundIsNoOp() {
        // Defensive: load() called before bind(to:) must not crash and must not
        // flip loading (since nothing was actually emitted).
        let store = AlbumTracksStore()
        store.load(album: "Anything", albumArtist: nil, uri: nil)
        XCTAssertFalse(store.loading)
        XCTAssertTrue(store.tracks.isEmpty)
    }
}
