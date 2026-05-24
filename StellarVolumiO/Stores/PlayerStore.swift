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

    // MARK: - Bind to socket
    func bind(to socket: SocketService) {
        socket.onRawDict("pushState",
                         parser: PlayerState.init(rawDict:)) { [weak self] (newState: PlayerState) in
            guard let self else { return }
            if self.state.status != newState.status ||
               self.state.title  != newState.title  ||
               self.state.artist != newState.artist ||
               self.state.album  != newState.album  ||
               self.state.volume != newState.volume ||
               abs(self.state.seekSeconds - newState.seekSeconds) > 1.0 ||
               self.state.duration != newState.duration {
                self.receiveServerState(newState)
            } else {
                // Same payload — still clear optimistic so it doesn't hang.
                self.optimisticStatus = nil
                self.optimisticTimeoutTask?.cancel()
            }
        }

        socket.on("pushQueue") { [weak self] (items: [QueueItem]) in
            self?.queue = items
        }
    }
}
