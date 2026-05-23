import Foundation
import Observation

@Observable
final class PlayerStore {

    // MARK: - Published State
    var state: PlayerState = .empty
    var queue: [QueueItem] = []
    var currentQueueIndex: Int = 0

    // Derived
    var isPlaying: Bool { state.status == .play }
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

    var albumArtURL: URL? {
        guard !state.albumart.isEmpty else { return nil }
        if state.albumart.hasPrefix("http") {
            return URL(string: state.albumart)
        }
        return nil
    }

    // MARK: - Bind to socket
    func bind(to socket: SocketService) {
        socket.on("pushState") { [weak self] (newState: PlayerState) in
            guard let self else { return }
            // Only update if meaningful fields changed — avoid re-renders
            if self.state.status != newState.status ||
               self.state.title != newState.title ||
               self.state.artist != newState.artist ||
               self.state.album != newState.album ||
               self.state.volume != newState.volume ||
               abs(self.state.seekSeconds - newState.seekSeconds) > 1.0 {
                self.state = newState
            }
        }

        socket.on("pushQueue") { [weak self] (items: [QueueItem]) in
            self?.queue = items
        }
    }
}
