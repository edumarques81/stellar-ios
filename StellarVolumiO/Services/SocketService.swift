import Foundation
import SocketIO
import Observation

// MARK: - Connection State
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - Socket Service
// Manages the Socket.IO connection to the Stellar backend.
//
// The default host points at the current backend deployment. Edit this one
// line when the backend host moves (Mac → Win/Linux/Pi).
private let defaultHost = "192.168.86.221"
private let defaultPort = 3000

@Observable
final class SocketService {

    var connectionState: ConnectionState = .disconnected
    var serverHost: String = defaultHost
    var serverPort: Int = defaultPort

    /// One-line summary of the last failed decode, e.g. "pushState: dict cast
    /// failed". `nil` when the last incoming payload decoded cleanly.
    /// Surfaced in the Settings → ConnectionStatusRow diagnostic.
    var lastDecodeError: String? = nil

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var eventHandlers: [String: [(Any) -> Void]] = [:]

    var isConnected: Bool { connectionState == .connected }

    // MARK: - Connect
    func connect(host: String? = nil, port: Int? = nil) {
        let h = host ?? serverHost
        let p = port ?? serverPort

        let url = URL(string: "http://\(h):\(p)")!

        manager = SocketManager(
            socketURL: url,
            config: [
                .log(false),
                .compress,
                .reconnects(true),
                .reconnectWait(2),
                .reconnectWaitMax(10),
                .forcePolling(false),
                .version(.three)        // Stellar backend uses Socket.IO v3 / EIO3
            ]
        )

        socket = manager?.defaultSocket

        setupHandlers()
        connectionState = .connecting
        socket?.connect()
    }

    func disconnect() {
        socket?.disconnect()
        connectionState = .disconnected
    }

    func reconnectIfNeeded() {
        guard connectionState != .connected, connectionState != .connecting else { return }
        connect()
    }

    // MARK: - Emit
    func emit(_ event: String, data: [Any] = []) {
        // Note: emits while disconnected are buffered by SocketIO-Client-Swift
        // and flushed on reconnect. Do not pre-guard — the library handles it.
        if data.isEmpty {
            socket?.emit(event)
        } else {
            socket?.emit(event, data)
        }
    }

    // MARK: - Subscribe
    func on<T: Decodable>(_ event: String, handler: @escaping (T) -> Void) {
        let wrapper: (Any) -> Void = { [weak self] data in
            guard let arr = data as? [Any], let first = arr.first else { return }
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: first)
                let decoded = try JSONDecoder().decode(T.self, from: jsonData)
                DispatchQueue.main.async {
                    self?.lastDecodeError = nil
                    handler(decoded)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.lastDecodeError = "\(event): \(error.localizedDescription)"
                }
            }
        }
        eventHandlers[event, default: []].append(wrapper)
        socket?.on(event, callback: { data, _ in wrapper(data) })
    }

    /// Subscribe to a Socket.IO event where the wire payload is a
    /// `[String: Any]` dict (typical Volumio shape). Caller provides a
    /// tolerant parser; on `nil` we populate `lastDecodeError`.
    func onRawDict<T>(_ event: String, parser: @escaping ([String: Any]) -> T?, handler: @escaping (T) -> Void) {
        socket?.on(event) { [weak self] data, _ in
            guard let arr = data as? [Any], let first = arr.first else {
                DispatchQueue.main.async { self?.lastDecodeError = "\(event): empty payload" }
                return
            }
            guard let dict = first as? [String: Any] else {
                DispatchQueue.main.async { self?.lastDecodeError = "\(event): payload not a dict" }
                return
            }
            guard let parsed = parser(dict) else {
                DispatchQueue.main.async { self?.lastDecodeError = "\(event): parser rejected payload" }
                return
            }
            DispatchQueue.main.async {
                self?.lastDecodeError = nil
                handler(parsed)
            }
        }
    }

    /// Variant that allows the payload to be `NSNull` (e.g.
    /// pushLastPlayedAlbum on a fresh backend) — passes `nil` to the handler.
    func onRawDictNullable<T>(_ event: String, parser: @escaping ([String: Any]) -> T?, handler: @escaping (T?) -> Void) {
        socket?.on(event) { [weak self] data, _ in
            let first = (data as? [Any])?.first
            if first is NSNull || first == nil {
                DispatchQueue.main.async {
                    self?.lastDecodeError = nil
                    handler(nil)
                }
                return
            }
            guard let dict = first as? [String: Any] else {
                DispatchQueue.main.async { self?.lastDecodeError = "\(event): payload not a dict" }
                return
            }
            DispatchQueue.main.async {
                if let parsed = parser(dict) {
                    self?.lastDecodeError = nil
                    handler(parsed)
                } else {
                    self?.lastDecodeError = "\(event): parser rejected payload"
                }
            }
        }
    }

    func on(_ event: String, handler: @escaping () -> Void) {
        socket?.on(event) { _, _ in
            DispatchQueue.main.async { handler() }
        }
    }

    /// Subscribe with raw `[Any]` payload — use when the wire shape isn't a flat Decodable.
    func onRaw(_ event: String, handler: @escaping ([Any]) -> Void) {
        socket?.on(event) { data, _ in
            DispatchQueue.main.async { handler(data) }
        }
    }

    // MARK: - Internal socket lifecycle
    private func setupHandlers() {
        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.connectionState = .connected
                self?.socket?.emit("getState")
                self?.socket?.emit("getQueue")
                self?.socket?.emit("getLcdStatus")
            }
        }

        socket?.on(clientEvent: .disconnect) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.connectionState = .disconnected
            }
        }

        socket?.on(clientEvent: .error) { [weak self] data, _ in
            DispatchQueue.main.async {
                let message = (data.first as? String) ?? "Unknown error"
                self?.connectionState = .error(message)
            }
        }

        socket?.on(clientEvent: .reconnect) { [weak self] _, _ in
            DispatchQueue.main.async { self?.connectionState = .connecting }
        }

        socket?.on(clientEvent: .reconnectAttempt) { [weak self] _, _ in
            DispatchQueue.main.async { self?.connectionState = .connecting }
        }
    }
}

// MARK: - Transport Commands
extension SocketService {
    func play()     { emit("play") }
    func pause()    { emit("pause") }
    func playPause(){ emit("toggle") }
    func stop()     { emit("stop") }
    func prev()     { emit("prev") }
    func next()     { emit("next") }
    func seek(to seconds: Int)   { emit("seek", data: [seconds]) }
    func setVolume(_ volume: Int){ emit("volume", data: [volume]) }
    func toggleMute()            { emit("mute") }
}

// MARK: - Library + LCD Commands
extension SocketService {
    /// Emit a payload with a single dictionary argument (matches the Volumio2-UI
    /// `socketService.emit('event', payload)` shape).
    func emitObject(_ event: String, _ payload: [String: Any]) {
        // Note: emits while disconnected are buffered by SocketIO-Client-Swift
        // and flushed on reconnect. Do not pre-guard — the library handles it.
        socket?.emit(event, payload)
    }

    func lcdWake()     { emit("lcdWake") }
    func lcdStandby()  { emit("lcdStandby") }
    func getLcdStatus(){ emit("getLcdStatus") }
}

// MARK: - Test hooks
//
// Production callers of onRawDict / onRawDictNullable / on<T> populate
// lastDecodeError via the DispatchQueue.main.async paths. These two helpers
// give tests a synchronous, socket-less entry point with the same shape.

#if DEBUG
extension SocketService {
    func simulateDecodeFailure(event: String, reason: String) {
        lastDecodeError = "\(event): \(reason)"
    }

    func simulateDecodeSuccess() {
        lastDecodeError = nil
    }
}
#endif
