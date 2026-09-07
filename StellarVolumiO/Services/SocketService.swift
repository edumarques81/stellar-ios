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
// The backend host/port/scheme is read from the injected `BackendConfigStore`
// rather than a code constant. The fallback chain inside the store
// (custom → discovered → default) preserves the previous out-of-the-box
// behaviour of connecting to 192.168.86.221:3000.

@Observable
final class SocketService {

    /// Backend configuration source. Reads host/port/scheme on every
    /// `ensureInitialised()` so SettingsView edits + Bonjour-driven updates
    /// flow through transparently. The default value lets existing test
    /// code keep using `SocketService()` with no parameters.
    private let config: BackendConfigStore

    init(config: BackendConfigStore = BackendConfigStore()) {
        self.config = config
    }

    var connectionState: ConnectionState = .disconnected {
        didSet {
            // Any transition back to .connected — whether from a socket
            // .connect event or a direct test assignment — cancels the
            // in-flight grace timer so the UI doesn't later flip red.
            if case .connected = connectionState {
                clearGraceWindow()
                lastConnectionError = nil
            }
        }
    }

    /// Host the socket is currently configured against. Updated each time
    /// `ensureInitialised()` builds a manager.
    var serverHost: String = BackendConfigStore.defaultHost
    /// Port the socket is currently configured against. Updated each time
    /// `ensureInitialised()` builds a manager.
    var serverPort: Int = BackendConfigStore.defaultPort
    /// Scheme (http/https) the socket is currently configured against.
    var serverScheme: String = BackendConfigStore.defaultScheme

    /// Human-readable URL the UI can display (e.g. "Connected to
    /// http://192.168.86.221:3000"). Always reflects the resolved
    /// `BackendConfigStore` values.
    var currentBackendURL: String {
        "\(serverScheme)://\(serverHost):\(serverPort)"
    }

    /// One-line summary of the last failed decode, e.g. "pushState: dict cast
    /// failed". `nil` when the last incoming payload decoded cleanly.
    /// Surfaced in the Settings → ConnectionStatusRow diagnostic.
    var lastDecodeError: String? = nil

    /// One-line summary of the last connect/transport-level failure. Cleared
    /// on the next successful `.connected`. Surfaced in the ContentView
    /// "Can't reach backend" banner alongside the Retry / Server Settings
    /// buttons.
    var lastConnectionError: String? = nil

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
    /// Every store subscription registered through `on…`, in registration
    /// order, kept so it can be re-attached whenever the underlying socket is
    /// rebuilt. Before this existed the handlers lived only on the
    /// SocketIOClient instance, so an endpoint change silently discarded them:
    /// the app reconnected, reported itself connected, and received nothing.
    private var subscriptions: [(event: String, callback: (Any) -> Void)] = []

    /// Event names currently subscribed on the underlying socket. Read-only
    /// introspection used by the handler-survival regression test and usable as
    /// a Settings diagnostic — a live socket with an empty list means the app is
    /// connected but deaf.
    var subscribedEvents: [String] { socket?.handlers.map(\.event) ?? [] }

    /// True when `event` has at least one handler attached to the live socket.
    func hasSubscription(for event: String) -> Bool {
        subscribedEvents.contains(event)
    }


    var isConnected: Bool { connectionState == .connected }

    // MARK: - Connect

    /// Create the underlying `SocketIOClient` + `SocketManager` (and wire its
    /// lifecycle handlers) if they don't exist yet. Calling this before
    /// `connect()` lets stores register `on(...)` subscriptions during
    /// `bind(to:)` — without this, those calls land on a nil socket and the
    /// handlers are silently dropped (the optional-chain `socket?.on(...)`
    /// becomes a no-op).
    ///
    /// Reads the latest host/port/scheme from `config` and rebuilds the
    /// underlying SocketManager if the resolved endpoint changed since the
    /// last initialisation. That's what makes Settings → "Save" trigger an
    /// automatic reconnect against the new backend.
    private func ensureInitialised() {
        let resolvedHost = config.host
        let resolvedPort = config.port
        let resolvedScheme = config.scheme

        let endpointChanged =
            resolvedHost != serverHost ||
            resolvedPort != serverPort ||
            resolvedScheme != serverScheme

        if socket != nil && !endpointChanged { return }
        if socket != nil && endpointChanged {
            // Tear down the existing manager so we rebuild against the new
            // endpoint. Re-bind callers will re-register their `on(...)`
            // handlers via ensureInitialised() the next time they emit.
            socket?.disconnect()
            socket = nil
            manager = nil
            // `subscriptions` deliberately survives: the whole point is to
            // replay them onto the socket we are about to build.
        }
        guard socket == nil else { return }

        serverHost = resolvedHost
        serverPort = resolvedPort
        serverScheme = resolvedScheme

        // Defense-in-depth: NEVER force-unwrap the URL — a malformed host
        // (e.g. legacy persisted "host:3000" before the BackendConfigStore
        // splitting fix landed, or a future bug in the resolver chain) used
        // to crash the app on every launch. Fall back to the hardcoded
        // default if URL construction fails so the user can recover via
        // Settings instead of being stuck in a panic loop.
        let primary = "\(resolvedScheme)://\(resolvedHost):\(resolvedPort)"
        let url: URL = URL(string: primary) ?? {
            let fallback = "\(BackendConfigStore.defaultScheme)://\(BackendConfigStore.defaultHost):\(BackendConfigStore.defaultPort)"
            // String-form default is hand-crafted and known-good — but we
            // still nil-coalesce to a guaranteed valid URL as a last resort
            // so this expression cannot crash under any circumstance.
            return URL(string: fallback) ?? URL(string: "http://127.0.0.1:3000")!
        }()

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
        // Re-attach every subscription registered against the previous socket.
        // Without this an endpoint change leaves the app connected but deaf —
        // and because `seek` is the only field that changes within a track, the
        // visible symptom is a frozen progress bar rather than an obvious
        // disconnect. Covered by SocketHandlerSurvivalTests.
        for sub in subscriptions {
            attach(sub.event, sub.callback)
        }
    }

    /// Connect to the backend. The optional host/port arguments stay for
    /// backward compatibility — production callers pass nothing and let the
    /// injected `BackendConfigStore` drive the endpoint.
    func connect(host: String? = nil, port: Int? = nil) {
        // Custom host/port overrides land in the config store, then
        // ensureInitialised() picks them up uniformly with the discovered +
        // default fallbacks. This keeps "Save" in Settings and any direct
        // `connect(host:port:)` test call going through the same path.
        if let host {
            try? config.setCustom(host: host, port: port, scheme: nil)
        } else if let port {
            try? config.setCustom(host: nil, port: port, scheme: nil)
        }
        ensureInitialised()
        connectionState = .connecting
        socket?.connect()
    }

    /// Tear down the existing socket and reconnect against whatever
    /// `BackendConfigStore` now resolves to. Called by SettingsView after
    /// the user saves a new host/port or picks a discovered server.
    func reconnectWithCurrentConfig() {
        socket?.disconnect()
        socket = nil
        manager = nil
        connectionState = .connecting
        ensureInitialised()
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
        // Populate the user-facing error string so ContentView's banner
        // surfaces with a friendly message after the grace window expires.
        // We don't overwrite a more-specific message already set by the
        // .error handler.
        if lastConnectionError == nil {
            lastConnectionError = "Lost connection to backend"
        }
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

    /// Emit `event` with each element of `data` as its own argument.
    ///
    /// `data` is `[SocketData]`, not `[Any]`, and it goes out through
    /// `emit(_:with:)` rather than the variadic `emit(_:_:)`. That is
    /// load-bearing: `Array` itself conforms to `SocketData`, so passing an
    /// array into the variadic form compiles happily and sends the whole array
    /// as a *single* argument. `seek(to: 150)` went on the wire as `[[150]]`
    /// instead of `[150]`, and the backend's `args[0].(float64)` type assert
    /// failed and did nothing — no error client-side, no error server-side,
    /// the control just silently did not work. `emit(_:with:)` splats.
    func emit(_ event: String, data: [SocketData] = []) {
        ensureInitialised()
        // Note: emits while disconnected are buffered by SocketIO-Client-Swift
        // and flushed on reconnect. Do not pre-guard — the library handles it.
        if data.isEmpty {
            socket?.emit(event)
        } else {
            socket?.emit(event, with: data, completion: nil)
        }
        #if DEBUG
        _recordEmitted(event: event, data: data)
        #endif
    }

    // MARK: - Subscription registry

    /// Attach a payload callback to the *current* socket without recording it.
    /// Used both by `register` and by the replay loop in `ensureInitialised`.
    private func attach(_ event: String, _ callback: @escaping (Any) -> Void) {
        socket?.on(event) { data, _ in callback(data) }
    }

    /// Record a subscription so it survives a socket rebuild, then attach it.
    private func register(_ event: String, _ callback: @escaping (Any) -> Void) {
        subscriptions.append((event: event, callback: callback))
        attach(event, callback)
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
        register(event, wrapper)
    }

    /// Subscribe to a Socket.IO event where the wire payload is a
    /// `[String: Any]` dict (typical Volumio shape). Caller provides a
    /// tolerant parser; on `nil` we populate `lastDecodeError`.
    func onRawDict<T>(_ event: String, parser: @escaping ([String: Any]) -> T?, handler: @escaping (T) -> Void) {
        ensureInitialised()
        register(event) { [weak self] data in
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
        register(event) { [weak self] data in
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
        register(event) { _ in
            DispatchQueue.main.async { handler() }
        }
    }

    /// Subscribe with raw `[Any]` payload — use when the wire shape isn't a flat Decodable.
    func onRaw(_ event: String, handler: @escaping ([Any]) -> Void) {
        ensureInitialised()
        register(event) { data in
            DispatchQueue.main.async { handler(data as? [Any] ?? []) }
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
                self?.lastConnectionError = message
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

    /// Ask which screen the LCD kiosk is showing. Reply: `pushLcdView`.
    func getLcdView() { emit("getLcdView") }

    /// Drive the LCD kiosk to a screen.
    ///
    /// `wake` additionally powers the panel on if it is in standby. It is opt-in
    /// on the wire and defaults to false there, so we pass it explicitly: a view
    /// change nobody can see is not what the user asked for.
    ///
    /// Sent as an object rather than a bare string — the bare-string form is
    /// reserved for the kiosk reporting its own navigation, which carries no
    /// wake intent. See docs/SOCKET-CONTRACT.md.
    func lcdSetView(_ view: LcdView, wake: Bool) {
        emitObject("lcdSetView", ["view": view.rawValue, "wake": wake])
    }

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

// MARK: - AirPlay event surface
//
// Listen for the AirPlay session events emitted by the Mac backend when the
// Pi `shairport-sync` receiver is mid-stream. The wire shape is locked across
// iOS / Volumio2-UI / backend — see `Models/AirplayState.swift` for the
// canonical payload contract.
//
// Emit side: `airplay:command {cmd}` is the only outbound event. The backend
// resolves the iPhone's DACP host:port via Bonjour and proxies the play /
// pause / next / prev command back to the AirPlay sender.
extension SocketService {

    /// Subscribe to `pushAirplayState`. Uses the tolerant rawDict parser so a
    /// missing optional field doesn't drop the whole envelope.
    func onPushAirplayState(_ handler: @escaping (AirplayState) -> Void) {
        onRawDict("pushAirplayState",
                  parser: AirplayState.init(rawDict:),
                  handler: handler)
    }

    /// Subscribe to `pushAirplayEnded`. Sent when the AirPlay session ends
    /// (sender disconnects, heartbeat times out, etc.). Payload carries the
    /// terminating sessionID so a stale end can't clear a fresh session.
    func onPushAirplayEnded(_ handler: @escaping (AirplayEnded) -> Void) {
        onRawDict("pushAirplayEnded",
                  parser: AirplayEnded.init(rawDict:),
                  handler: handler)
    }

    /// Emit `airplay:command {cmd: "play"|"pause"|"toggle"|"next"|"prev"}`.
    /// Wraps the single-dictionary emit shape used elsewhere (see
    /// `emitObject`). The backend acks with `{ok: bool, error?: string}` —
    /// callers that want the ack should use the explicit `emitWithAck`
    /// helper rather than these convenience wrappers.
    func airplayPlay()       { emitObject("airplay:command", ["cmd": "play"]) }
    func airplayPause()      { emitObject("airplay:command", ["cmd": "pause"]) }
    func airplayPlayPause()  { emitObject("airplay:command", ["cmd": "toggle"]) }
    func airplayNext()       { emitObject("airplay:command", ["cmd": "next"]) }
    func airplayPrev()       { emitObject("airplay:command", ["cmd": "prev"]) }

    /// Ask the backend to re-push the current AirPlay session state to
    /// this client. The backend's handler replies with a targeted
    /// `pushAirplayState` (or no-op if no session is active).
    ///
    /// Use cases:
    ///   - App returns to foreground: the socket may still be connected,
    ///     so no reconnect-on-connect rehydration fires; without this
    ///     call the UI stays on its stale "before backgrounding" state.
    ///   - User navigates to the Now Playing tab and the previous fetch
    ///     was too long ago.
    func requestAirplayState() {
        ensureInitialised()
        socket?.emit("getAirplayState")
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

/// Test-only capture of the last `emit(_:data:)` call, recording the argument
/// list as it will be splatted onto the wire. This exists because the bug it
/// guards against was invisible from both ends: the app emitted, the backend
/// received an event, and the payload was simply the wrong shape.
extension SocketService {
    private static var argCaptureStorage: [ObjectIdentifier: (event: String, data: [SocketData])] = [:]

    var lastEmittedEvent: String? {
        Self.argCaptureStorage[ObjectIdentifier(self)]?.event
    }

    var lastEmittedData: [SocketData]? {
        Self.argCaptureStorage[ObjectIdentifier(self)]?.data
    }

    /// The first argument as the backend will see it, or nil if none was sent.
    /// A wrapped array shows up here as `[Int]` rather than `Int`, which is
    /// exactly the distinction the seek regression turned on.
    var lastEmittedFirstArgument: Any? {
        Self.argCaptureStorage[ObjectIdentifier(self)]?.data.first
    }

    func _recordEmitted(event: String, data: [SocketData]) {
        Self.argCaptureStorage[ObjectIdentifier(self)] = (event: event, data: data)
    }

    func resetEmittedCapture() {
        Self.argCaptureStorage.removeValue(forKey: ObjectIdentifier(self))
    }
}
#endif
