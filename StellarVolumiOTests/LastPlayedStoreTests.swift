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
