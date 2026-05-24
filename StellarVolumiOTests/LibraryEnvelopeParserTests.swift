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
}
