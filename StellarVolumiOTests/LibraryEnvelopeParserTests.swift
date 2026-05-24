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

    func testPushLibraryAlbumsNonArrayAlbumsKey() {
        // Backend-shape drift defence: if `albums` is a non-array (e.g. Int or
        // String), the envelope must still construct with zero rows rather
        // than crash or skip the envelope. Pins the `as? [[String: Any]] ?? []`
        // fallback in PushLibraryAlbums.init?(rawDict:).
        let env5 = PushLibraryAlbums(rawDict: ["albums": 5])
        XCTAssertNotNil(env5)
        XCTAssertEqual(env5?.albums.count, 0)

        let envStr = PushLibraryAlbums(rawDict: ["albums": "wrong"])
        XCTAssertNotNil(envStr)
        XCTAssertEqual(envStr?.albums.count, 0)
    }

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

    func testPushLibraryAlbumsRealBackendShape() {
        // Pins the 2026-05-24 Phase 1.11 fix-up: backend sends `albumArt`
        // (camelCase) and a `pagination` envelope instead of `total`. Albums
        // must populate AND their albumart field must be non-empty.
        let env = PushLibraryAlbums(rawDict: Fixtures.pushLibraryAlbumsRealBackend)
        XCTAssertNotNil(env)
        XCTAssertEqual(env?.albums.count, 2)
        XCTAssertEqual(env?.albums[0].title, "Time Out")
        XCTAssertEqual(env?.albums[0].albumart,
                       "/albumart?path=NAS/Dave%20Brubeck/Time%20Out",
                       "albumArt camelCase from backend must map onto LibraryAlbum.albumart")
        XCTAssertEqual(env?.albums[1].albumart,
                       "/albumart?path=NAS/John%20Coltrane/A%20Love%20Supreme")
        XCTAssertNil(env?.total, "real backend uses pagination object; top-level total is nil — pinned as known gap, fix TBD")
    }

    func testLibraryAlbumStillReadsLowercaseAlbumart() {
        // Backwards compat — older test fixtures (Fixtures.pushLibraryAlbumsCanonical)
        // use lowercase `albumart`. The fix must not break that fallback.
        let env = PushLibraryAlbums(rawDict: Fixtures.pushLibraryAlbumsCanonical)
        XCTAssertEqual(env?.albums[0].albumart,
                       "/albumart?path=NAS/Pink%20Floyd/Dark%20Side")
    }
}
