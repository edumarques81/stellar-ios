import XCTest
@testable import StellarVolumiO

/// Coverage for `AirplayState.init?(rawDict:)` — the tolerant parser that
/// consumes the backend `pushAirplayState` envelope. Mirrors the pattern in
/// `PlayerStateParserTests`: canonical → loose → minimal → completely empty.
///
/// The wire contract is locked across iOS / Volumio2-UI / backend. Any drift
/// here means a contract violation, not a parser bug — fix the wire side.
final class AirplayStateTests: XCTestCase {

    // MARK: - Canonical decode

    func testCanonicalDecode() {
        let dict: [String: Any] = [
            "isActive":        true,
            "title":           "Time",
            "artist":          "Pink Floyd",
            "album":           "The Dark Side of the Moon",
            "sender":          "Eduardo's iPhone",
            "coverDataURL":    "data:image/jpeg;base64,/9j/4AAQSkZJRg==",
            "seekSeconds":     42,
            "durationSeconds": 245,
            "canControl":      true,
            "sessionID":       "session-abc-123",
            "sampleRate":      44100,
            "bitDepth":        16
        ]
        let s = AirplayState(rawDict: dict)
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.isActive, true)
        XCTAssertEqual(s?.title, "Time")
        XCTAssertEqual(s?.artist, "Pink Floyd")
        XCTAssertEqual(s?.album, "The Dark Side of the Moon")
        XCTAssertEqual(s?.sender, "Eduardo's iPhone")
        XCTAssertEqual(s?.coverDataURL, "data:image/jpeg;base64,/9j/4AAQSkZJRg==")
        XCTAssertEqual(s?.seekSeconds, 42)
        XCTAssertEqual(s?.durationSeconds, 245)
        XCTAssertEqual(s?.canControl, true)
        XCTAssertEqual(s?.sessionID, "session-abc-123")
        XCTAssertEqual(s?.sampleRate, 44100)
        XCTAssertEqual(s?.bitDepth, 16)
    }

    // MARK: - Tolerance: string-numeric coercion + missing fields

    func testStringNumericSeekAndDurationCoerce() {
        let dict: [String: Any] = [
            "isActive":        true,
            "sessionID":       "s1",
            "seekSeconds":     "42",
            "durationSeconds": "245",
            "sampleRate":      "48000",
            "bitDepth":        "24"
        ]
        let s = AirplayState(rawDict: dict)
        XCTAssertEqual(s?.seekSeconds, 42,
                       "string-shaped seekSeconds must coerce to Int")
        XCTAssertEqual(s?.durationSeconds, 245,
                       "string-shaped durationSeconds must coerce to Int")
        XCTAssertEqual(s?.sampleRate, 48000)
        XCTAssertEqual(s?.bitDepth, 24)
    }

    func testMissingStringFieldsFallBackToEmpty() {
        let dict: [String: Any] = ["isActive": true, "sessionID": "s1"]
        let s = AirplayState(rawDict: dict)
        XCTAssertEqual(s?.title, "")
        XCTAssertEqual(s?.artist, "")
        XCTAssertEqual(s?.album, "")
        XCTAssertEqual(s?.sender, "")
        XCTAssertEqual(s?.coverDataURL, "")
    }

    func testMissingNumericFieldsFallBackToZero() {
        let dict: [String: Any] = ["isActive": true, "sessionID": "s1"]
        let s = AirplayState(rawDict: dict)
        XCTAssertEqual(s?.seekSeconds, 0)
        XCTAssertEqual(s?.durationSeconds, 0)
        XCTAssertEqual(s?.sampleRate, 0)
        XCTAssertEqual(s?.bitDepth, 0)
    }

    func testMissingBoolFieldsFallBackToFalse() {
        // No isActive, no canControl — both must default to false rather
        // than reject the whole payload.
        let dict: [String: Any] = ["sessionID": "s1", "title": "X"]
        let s = AirplayState(rawDict: dict)
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.isActive, false)
        XCTAssertEqual(s?.canControl, false)
    }

    func testCompletelyEmptyDictDecodesToEmpty() {
        let s = AirplayState(rawDict: [:])
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.isActive, false)
        XCTAssertEqual(s?.sessionID, "")
    }

    // MARK: - Cover data URL passthrough

    func testCoverDataURLIsOpaqueString() {
        // The parser must not try to decode base64 — the data URL stays as
        // an opaque string until SwiftUI's image renderer consumes it.
        let url = "data:image/jpeg;base64,/9j/4AAQSkZJRg==INVALID_BASE64==="
        let s = AirplayState(rawDict: ["sessionID": "s1", "coverDataURL": url])
        XCTAssertEqual(s?.coverDataURL, url,
                       "parser must pass the data URL through verbatim")
    }

    // MARK: - Empty default

    func testEmptyDefaultIsInactive() {
        XCTAssertEqual(AirplayState.empty.isActive, false)
        XCTAssertEqual(AirplayState.empty.sessionID, "")
        XCTAssertEqual(AirplayState.empty.title, "")
    }

    // MARK: - Equatable diff-skip

    func testEquatableMatchesIdenticalPayloads() {
        let a = AirplayState(rawDict: [
            "isActive": true, "sessionID": "s1", "title": "X",
            "seekSeconds": 10, "durationSeconds": 100
        ])
        let b = AirplayState(rawDict: [
            "isActive": true, "sessionID": "s1", "title": "X",
            "seekSeconds": 10, "durationSeconds": 100
        ])
        XCTAssertEqual(a, b, "identical payloads must be ==")
    }

    func testEquatableDistinguishesSessionID() {
        let a = AirplayState(rawDict: ["isActive": true, "sessionID": "s1"])
        let b = AirplayState(rawDict: ["isActive": true, "sessionID": "s2"])
        XCTAssertNotEqual(a, b, "different sessionIDs must be !=")
    }

    // MARK: - isPlaying (mid-flight contract amendment)
    //
    // `isPlaying` is a separate top-level bool from `isActive`:
    //   isActive  = "AirPlay session is alive" (true while sender connected)
    //   isPlaying = "currently playing vs. paused" (iPhone-side transport)
    //
    // The play/pause glyph reads isPlaying so the user sees the correct icon
    // when they pause Apple Music mid-session. Default-true-when-missing
    // covers the "freshly started, no explicit isPlaying yet" case.

    func testIsPlayingDecodesExplicitTrue() {
        let dict: [String: Any] = [
            "isActive": true, "isPlaying": true, "sessionID": "s1"
        ]
        let s = AirplayState(rawDict: dict)
        XCTAssertEqual(s?.isPlaying, true)
    }

    func testIsPlayingDecodesExplicitFalse() {
        let dict: [String: Any] = [
            "isActive": true, "isPlaying": false, "sessionID": "s1"
        ]
        let s = AirplayState(rawDict: dict)
        XCTAssertEqual(s?.isPlaying, false,
                       "explicit isPlaying:false must decode as false (user paused)")
    }

    func testIsPlayingDefaultsToTrueWhenMissing() {
        // A freshly-started session emits its first state event without an
        // explicit `isPlaying` field on older backends. "AirPlay just
        // started" implies playing, not paused.
        let dict: [String: Any] = ["isActive": true, "sessionID": "s1"]
        let s = AirplayState(rawDict: dict)
        XCTAssertEqual(s?.isPlaying, true,
                       "missing isPlaying must default to true (just-started session)")
    }

    func testEmptyDefaultIsPlayingIsTrue() {
        XCTAssertEqual(AirplayState.empty.isPlaying, true)
    }

    // MARK: - Ended payload

    func testEndedDecodesSessionID() {
        let e = AirplayEnded(rawDict: ["sessionID": "session-abc-123"])
        XCTAssertEqual(e?.sessionID, "session-abc-123")
    }

    func testEndedRejectsMissingSessionID() {
        let e = AirplayEnded(rawDict: [:])
        XCTAssertNil(e, "pushAirplayEnded without sessionID is malformed and must reject")
    }
}
