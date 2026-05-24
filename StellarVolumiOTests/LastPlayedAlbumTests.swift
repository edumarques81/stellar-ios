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
