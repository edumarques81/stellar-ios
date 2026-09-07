import XCTest
@testable import StellarVolumiO

/// Coverage for the argument shape `emit(_:data:)` puts on the wire.
///
/// The regression these exist for: the seek slider and the volume control did
/// nothing at all, with no error at either end. `emit` held its payload as
/// `[Any]` and passed it to SocketIO-Client-Swift's *variadic*
/// `emit(_:_:)`. `Array` conforms to `SocketData`, so that compiles and sends
/// the array as a single argument — `seek(to: 150)` went out as `[[150]]`
/// rather than `[150]`. The backend reads `args[0].(float64)`, which fails on
/// an array and silently does nothing.
///
/// So the assertion that matters is not "did it emit" but "is the first
/// argument a bare number rather than an array wrapping one".
@MainActor
final class SocketEmitArgumentShapeTests: XCTestCase {

    private func makeSocket() -> SocketService {
        let socket = SocketService()
        socket.resetEmittedCapture()
        return socket
    }

    func testSeekSendsABareIntegerNotAWrappedArray() {
        let socket = makeSocket()
        socket.seek(to: 150)

        XCTAssertEqual(socket.lastEmittedEvent, "seek")
        XCTAssertEqual(socket.lastEmittedData?.count, 1,
                       "seek must send exactly one argument")
        XCTAssertEqual(socket.lastEmittedFirstArgument as? Int, 150,
                       "the backend reads args[0] as a number; an array here is the bug")
        XCTAssertNil(socket.lastEmittedFirstArgument as? [Any],
                     "first argument must not be an array wrapping the value")
    }

    func testVolumeSendsABareIntegerNotAWrappedArray() {
        let socket = makeSocket()
        socket.setVolume(42)

        XCTAssertEqual(socket.lastEmittedEvent, "volume")
        XCTAssertEqual(socket.lastEmittedData?.count, 1)
        XCTAssertEqual(socket.lastEmittedFirstArgument as? Int, 42)
        XCTAssertNil(socket.lastEmittedFirstArgument as? [Any])
    }

    func testSeekToZeroStillSendsAnArgument() {
        // Dragging the scrubber to the very start is the exact gesture that
        // reported the bug, and 0 is the value most likely to be dropped by a
        // truthiness check somewhere along the way.
        let socket = makeSocket()
        socket.seek(to: 0)

        XCTAssertEqual(socket.lastEmittedData?.count, 1)
        XCTAssertEqual(socket.lastEmittedFirstArgument as? Int, 0)
    }

    func testPayloadLessCommandsSendNoArguments() {
        let socket = makeSocket()
        socket.playPause()

        XCTAssertEqual(socket.lastEmittedEvent, "toggle")
        XCTAssertEqual(socket.lastEmittedData?.count, 0,
                       "transport commands take no payload; sending one would change the shape")
        XCTAssertNil(socket.lastEmittedFirstArgument)
    }
}
