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
