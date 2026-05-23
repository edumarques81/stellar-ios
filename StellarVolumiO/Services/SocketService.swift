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
// Manages the Socket.IO connection to the Stellar/Volumio backend
// Default host: stellar.local:3000

@Observable
final class SocketService {

    // MARK: - State
    var connectionState: ConnectionState = .disconnected
    var serverHost: String = "stellar.local"
    var serverPort: Int = 3000

    // MARK: - Private
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
                .version(.three)        // Volumio uses Socket.IO v3 / EIO3
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
        guard isConnected else { return }
        if data.isEmpty {
            socket?.emit(event)
        } else {
            socket?.emit(event, data)
        }
    }

    // MARK: - Subscribe
    func on<T: Decodable>(_ event: String, handler: @escaping (T) -> Void) {
        let wrapper: (Any) -> Void = { data in
            guard let arr = data as? [Any], let first = arr.first else { return }
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: first)
                let decoded = try JSONDecoder().decode(T.self, from: jsonData)
                DispatchQueue.main.async { handler(decoded) }
            } catch {
                // Silently ignore decode errors — backend shape may vary
            }
        }
        eventHandlers[event, default: []].append(wrapper)
        socket?.on(event, callback: { data, _ in wrapper(data) })
    }

    func on(_ event: String, handler: @escaping () -> Void) {
        socket?.on(event) { _, _ in
            DispatchQueue.main.async { handler() }
        }
    }

    /// Subscribe to a socket event with raw `[Any]` data — use when the payload isn't
    /// a flat Decodable (e.g. nested dicts like `pushAudirvanaStatus`).
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
                // Ask backend for current state on connect
                self?.socket?.emit("getState")
                self?.socket?.emit("getQueue")
                self?.socket?.emit("getAudioEngineState")
                self?.socket?.emit("getAudirvanaStatus")
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
            DispatchQueue.main.async {
                self?.connectionState = .connecting
            }
        }

        socket?.on(clientEvent: .reconnectAttempt) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.connectionState = .connecting
            }
        }
    }
}

// MARK: - Player Commands
extension SocketService {
    func play() { emit("play") }
    func pause() { emit("pause") }
    func playPause() { emit("toggle") }
    func stop() { emit("stop") }
    func prev() { emit("prev") }
    func next() { emit("next") }
    func seek(to seconds: Int) { emit("seek", data: [seconds]) }
    func setVolume(_ volume: Int) { emit("volume", data: [volume]) }
    func toggleMute() { emit("mute") }
    func toggleShuffle(_ on: Bool) { emit("setRandom", data: [["value": on]]) }
    func toggleRepeat(_ on: Bool) { emit("setRepeat", data: [["value": on]]) }

    func switchEngine(to engine: AudioEngine) {
        emit("switchAudioEngine", data: [["engine": engine.rawValue]])
    }
}
