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
