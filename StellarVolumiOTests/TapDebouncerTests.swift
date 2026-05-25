import XCTest
@testable import StellarVolumiO

/// Coverage for `TapDebouncer` — the small helper that backs the defensive
/// debounce on the Album Tracks screen (Play Album CTA + per-track rows).
///
/// The behavioural contract:
///   1. The first tap is always accepted.
///   2. A tap inside the window after an accepted tap is rejected.
///   3. A tap outside the window is accepted, and resets the window.
///   4. A *rejected* tap does NOT advance the window (we measure from the
///      last *accepted* tap, not the last *attempted* one — otherwise a
///      sustained flurry of taps would keep the gate closed indefinitely).
///   5. Time is injected so tests stay synchronous.
final class TapDebouncerTests: XCTestCase {

    func testFirstTapAlwaysAccepted() {
        var debouncer = TapDebouncer(interval: 0.5)
        XCTAssertTrue(debouncer.attempt(at: Date(timeIntervalSinceReferenceDate: 0)),
                      "first tap on a fresh debouncer must always be accepted")
    }

    func testPlayAlbumDebouncedWithinInterval() {
        // Models the user mashing Play Album: two taps fired in immediate
        // succession (10 ms apart) — only the first should make it through.
        var debouncer = TapDebouncer(interval: 0.5)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertTrue(debouncer.attempt(at: t0))
        XCTAssertFalse(debouncer.attempt(at: t0.addingTimeInterval(0.01)),
                       "second tap inside the 500 ms window must be dropped")
    }

    func testPlayAlbumNotDebouncedAfterInterval() {
        // Models a deliberate re-tap after the window has expired.
        var debouncer = TapDebouncer(interval: 0.5)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertTrue(debouncer.attempt(at: t0))
        XCTAssertTrue(debouncer.attempt(at: t0.addingTimeInterval(0.6)),
                      "tap after the window must be accepted")
    }

    func testTapExactlyAtIntervalBoundaryIsAccepted() {
        // The boundary is inclusive (>= interval). A tap at exactly 500 ms
        // after an accepted tap should pass. Documents intent so a future
        // refactor doesn't accidentally flip it to strict-greater-than.
        var debouncer = TapDebouncer(interval: 0.5)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertTrue(debouncer.attempt(at: t0))
        XCTAssertTrue(debouncer.attempt(at: t0.addingTimeInterval(0.5)))
    }

    func testRejectedTapDoesNotAdvanceTheWindow() {
        // If a rejected tap reset the window, a sustained flurry of taps
        // would keep the gate closed forever. The window must measure from
        // the last *accepted* tap, not the last *attempted* one.
        var debouncer = TapDebouncer(interval: 0.5)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertTrue(debouncer.attempt(at: t0))
        XCTAssertFalse(debouncer.attempt(at: t0.addingTimeInterval(0.1)))
        XCTAssertFalse(debouncer.attempt(at: t0.addingTimeInterval(0.3)))
        // 0.55 s after the accepted tap, the gate opens again — even though
        // we attempted (and were rejected) at 0.1 s and 0.3 s in between.
        XCTAssertTrue(debouncer.attempt(at: t0.addingTimeInterval(0.55)))
    }

    func testSequenceOfMixedAcceptsAndRejects() {
        // End-to-end: model an album page being mashed-then-paced.
        var debouncer = TapDebouncer(interval: 0.5)
        var accepted = 0
        let base = Date(timeIntervalSinceReferenceDate: 5_000)
        let offsets: [TimeInterval] = [0.0, 0.05, 0.2, 0.51, 0.55, 1.1]
        // Expected accepts: t=0.0, t=0.51, t=1.1 → 3 emits out of 6 taps.
        for offset in offsets where debouncer.attempt(at: base.addingTimeInterval(offset)) {
            accepted += 1
        }
        XCTAssertEqual(accepted, 3,
                       "expected three accepts at offsets 0.0 / 0.51 / 1.1")
    }
}
