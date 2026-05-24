import Foundation
import Observation

@Observable
final class PlayerStore {

    // MARK: - Published State
    var state: PlayerState = .empty
    var queue: [QueueItem] = []
    var currentQueueIndex: Int = 0

    /// Optimistic playback status set on tap. Server `pushState` clears it.
    /// Times out after 2 s so a missing push doesn't lie to the UI forever.
    var optimisticStatus: PlaybackStatus? = nil
    private var optimisticTimeoutTask: Task<Void, Never>? = nil

    /// Drives `tick()` once per second while the server reports `.play`.
    /// Started on bind, runs forever; the tick body short-circuits when
    /// `state.status != .play` so it costs nothing while paused/stopped.
    private var seekTickerTask: Task<Void, Never>? = nil

    // Derived
    var isPlaying: Bool {
        if let o = optimisticStatus { return o == .play }
        return state.status == .play
    }
    var hasTrack: Bool { !state.title.isEmpty }

    var currentTrackFormatBadges: [String] {
        var badges: [String] = []
        if !state.trackType.isEmpty { badges.append(state.trackType.uppercased()) }
        if let sr = Double(state.samplerate), sr > 0 {
            badges.append(String(format: "%.0fkHz", sr / 1000))
        }
        if !state.bitdepth.isEmpty && state.bitdepth != "0" {
            badges.append("\(state.bitdepth)bit")
        }
        return badges
    }

    /// Set optimistic state from a UI tap and start the 2 s reconciliation
    /// timeout. Subsequent server `pushState` will clear the optimistic value.
    func applyOptimistic(_ status: PlaybackStatus) {
        optimisticStatus = status
        optimisticTimeoutTask?.cancel()
        optimisticTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.optimisticStatus = nil }
        }
    }

    /// Apply server-truth state and clear any pending optimistic value.
    func receiveServerState(_ newState: PlayerState) {
        state = newState
        optimisticStatus = nil
        optimisticTimeoutTask?.cancel()
        optimisticTimeoutTask = nil
    }

    var albumArtURL: URL? {
        guard !state.albumart.isEmpty else { return nil }
        if state.albumart.hasPrefix("http") {
            return URL(string: state.albumart)
        }
        return nil
    }

    /// Advance `state.seek` by one second while the server says `.play`.
    /// The Stellar backend deliberately omits seek from its diff comparison
    /// (see `stateCompareKeys` in `server.go`) — clients are expected to
    /// interpolate locally between broadcasts. Mirrors `startSeekInterpolation`
    /// in Volumio2-UI's `player.ts`.
    func tick() {
        guard state.status == .play else { return }
        let durationMs = state.duration * 1000
        guard durationMs > 0 else {
            state.seek += 1_000
            return
        }
        state.seek = min(state.seek + 1_000, durationMs)
    }

    /// Start the 1 Hz seek interpolator. Safe to call multiple times — only
    /// one task runs at a time. Stopped automatically on `deinit`.
    func startSeekTicker() {
        guard seekTickerTask == nil else { return }
        seekTickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run { self?.tick() }
            }
        }
    }

    deinit {
        seekTickerTask?.cancel()
        optimisticTimeoutTask?.cancel()
    }

    // MARK: - Bind to socket
    func bind(to socket: SocketService) {
        socket.onRawDict("pushState",
                         parser: PlayerState.init(rawDict:)) { [weak self] (newState: PlayerState) in
            guard let self else { return }
            // Equatable check across the full PlayerState means a flip on
            // *any* field — including `status` alone, when an external client
            // (LCD / web) toggles transport without changing the track — gets
            // applied through `receiveServerState`. The old per-field || chain
            // omitted `albumart`, `trackType`, `samplerate`, `bitdepth`, `uri`,
            // `service`, and the boolean flags; equality covers them all.
            if self.state != newState {
                self.receiveServerState(newState)
            } else {
                // Identical payload — still clear optimistic so a missed
                // server transition doesn't hang the button.
                self.optimisticStatus = nil
                self.optimisticTimeoutTask?.cancel()
            }
        }

        socket.on("pushQueue") { [weak self] (items: [QueueItem]) in
            self?.queue = items
        }

        startSeekTicker()
    }
}
