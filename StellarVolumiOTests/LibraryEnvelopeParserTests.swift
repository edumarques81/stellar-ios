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
