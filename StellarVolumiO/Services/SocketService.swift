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

    var connectionState: ConnectionState = .disconnected {
        didSet {
            // Any transition back to .connected — whether from a socket
            // .connect event or a direct test assignment — cancels the
            // in-flight grace timer so the UI doesn't later flip red.
            if case .connected = connectionState {
                clearGraceWindow()
            }
        }
    }
    var serverHost: String = defaultHost
    var serverPort: Int = defaultPort

    /// One-line summary of the last failed decode, e.g. "pushState: dict cast
    /// failed". `nil` when the last incoming payload decoded cleanly.
    /// Surfaced in the Settings → ConnectionStatusRow diagnostic.
    var lastDecodeError: String? = nil

    /// UI-facing view of the connection state. During the 5-second
    /// post-disconnect grace, this returns `.connecting` so the UI shows a
    /// spinner rather than a red error. Mirrors Volumio2-UI's
    /// `DISCONNECT_GRACE_PERIOD_MS = 5000`.
    var reportedConnectionState: ConnectionState {
        if isInGraceWindow { return .connecting }
        return connectionState
    }

    private var isInGraceWindow: Bool = false
    private var graceTask: Task<Void, Never>? = nil
    static let disconnectGraceSeconds: Double = 5.0

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var eventHandlers: [String: [(Any) -> Void]] = [:]

    var isConnected: Bool { connectionState == .connected }

    // MARK: - Connect

    /// Create the underlying `SocketIOClient` + `SocketManager` (and wire its
    /// lifecycle handlers) if they don't exist yet. Calling this before
    /// `connect()` lets stores register `on(...)` subscriptions during
    /// `bind(to:)` — without this, those calls land on a nil socket and the
    /// handlers are silently dropped (the optional-chain `socket?.on(...)`
    /// becomes a no-op).
    private func ensureInitialised() {
        guard socket == nil else { return }  // already built at current host:port

        let url = URL(string: "http://\(serverHost):\(serverPort)")!

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
    }

    func connect(host: String? = nil, port: Int? = nil) {
        let newHost = host ?? serverHost
        let newPort = port ?? serverPort

        // If the endpoint changed since the socket was built, tear it down
        // and rebuild against the new host:port. Existing callers don't pass
        // host/port, so this path is defensive only.
        if socket != nil && (newHost != serverHost || newPort != serverPort) {
            socket?.disconnect()
            socket = nil
            manager = nil
        }
        serverHost = newHost
        serverPort = newPort

        ensureInitialised()
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

    /// Test-visible hook + production entry point: socket reports disconnect.
    /// Sets the raw `connectionState` to `.disconnected` so callers see truth,
    /// then starts the 5-second grace timer; `reportedConnectionState` will
    /// surface `.connecting` (spinner) during the window. If a reconnect
    /// arrives before it expires, the timer is cancelled and the UI never
    /// sees the red state.
    func markDisconnectedInternal() {
        // Defensive: don't start a second timer if one is already running.
        guard !isInGraceWindow else { return }

        isInGraceWindow = true
        connectionState = .disconnected
        graceTask?.cancel()
        graceTask = Task { @MainActor [weak self] in
            let ns = UInt64(Self.disconnectGraceSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            self?.isInGraceWindow = false
            self?.graceTask?.cancel()
        }
    }

    /// Cancel any pending grace timer and clear the grace flag — call on
    /// reconnect so the UI doesn't later flip to `.disconnected`.
    private func clearGraceWindow() {
        isInGraceWindow = false
        graceTask?.cancel()
        graceTask = nil
    }

    // MARK: - Emit
    func emit(_ event: String, data: [Any] = []) {
        ensureInitialised()
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
        ensureInitialised()
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
        ensureInitialised()
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
        ensureInitialised()
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
        ensureInitialised()
        socket?.on(event) { _, _ in
            DispatchQueue.main.async { handler() }
        }
    }

    /// Subscribe with raw `[Any]` payload — use when the wire shape isn't a flat Decodable.
    func onRaw(_ event: String, handler: @escaping ([Any]) -> Void) {
        ensureInitialised()
        socket?.on(event) { data, _ in
            DispatchQueue.main.async { handler(data) }
        }
    }

    // MARK: - Internal socket lifecycle
    private func setupHandlers() {
        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            DispatchQueue.main.async {
                // Reconnect during grace: cancel timer so the UI doesn't
                // later flip to .disconnected after the connection is back.
                self?.clearGraceWindow()
                self?.connectionState = .connected
                self?.socket?.emit("getState")
                self?.socket?.emit("getQueue")
                self?.socket?.emit("getLcdStatus")
            }
        }

        socket?.on(clientEvent: .disconnect) { [weak self] _, _ in
            DispatchQueue.main.async {
                // markDisconnectedInternal sets connectionState = .disconnected
                // AND starts the 5s grace window so reportedConnectionState
                // reads .connecting (spinner) during the grace period.
                self?.markDisconnectedInternal()
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
        ensureInitialised()
        // Note: emits while disconnected are buffered by SocketIO-Client-Swift
        // and flushed on reconnect. Do not pre-guard — the library handles it.
        socket?.emit(event, payload)
        #if DEBUG
        _recordEmittedObject(event: event, payload: payload)
        #endif
    }

    func lcdWake()     { emit("lcdWake") }
    func lcdStandby()  { emit("lcdStandby") }
    func getLcdStatus(){ emit("getLcdStatus") }

    /// Request the track list for a specific album. `album` is required;
    /// `albumArtist` and `uri` are optional but recommended — `uri` scopes to a
    /// specific folder when the same album exists in multiple quality versions.
    /// Backend reply event: `pushLibraryAlbumTracks` (see onLibraryAlbumTracks).
    func emitGetAlbumTracks(album: String, albumArtist: String?, uri: String?) {
        var payload: [String: Any] = ["album": album]
        if let albumArtist, !albumArtist.isEmpty { payload["albumArtist"] = albumArtist }
        if let uri, !uri.isEmpty { payload["uri"] = uri }
        emitObject("library:album:tracks", payload)
    }

    /// Subscribe to `pushLibraryAlbumTracks` payloads. Uses the tolerant
    /// rawDict parser so a missing optional field doesn't drop the whole envelope.
    func onLibraryAlbumTracks(_ handler: @escaping (PushLibraryAlbumTracks) -> Void) {
        onRawDict("pushLibraryAlbumTracks",
                  parser: PushLibraryAlbumTracks.init(rawDict:),
                  handler: handler)
    }
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

/// Test-only capture of the last `emitObject(_:_:)` call. Lets stores'
/// `load(...)` methods be verified for the wire payload they send without
/// needing a real Socket.IO connection. Production code never reads these.
extension SocketService {
    private static var captureStorage: [ObjectIdentifier: (event: String, payload: [String: Any])] = [:]

    var lastEmittedObjectEvent: String? {
        Self.captureStorage[ObjectIdentifier(self)]?.event
    }

    var lastEmittedObjectPayload: [String: Any]? {
        Self.captureStorage[ObjectIdentifier(self)]?.payload
    }

    func _recordEmittedObject(event: String, payload: [String: Any]) {
        Self.captureStorage[ObjectIdentifier(self)] = (event: event, payload: payload)
    }

    func resetEmittedObjectCapture() {
        Self.captureStorage.removeValue(forKey: ObjectIdentifier(self))
    }
}
#endif
