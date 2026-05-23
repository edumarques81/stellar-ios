import Foundation
import Observation

@Observable
final class AudioEngineStore {
    var state: AudioEngineState = .default
    var isSwitching: Bool = false
    var switchError: String? = nil

    var activeEngine: AudioEngine { state.active }
    var isAudirvanaActive: Bool { state.active == .audirvana }

    func bind(to socket: SocketService) {
        // Listen for backend-reported actual engine state
        socket.on("pushAudioEngineState") { [weak self] (engineState: AudioEngineState) in
            self?.state = engineState
            self?.isSwitching = false
        }

        // If pushState comes in with audirvana service, auto-update engine
        socket.on("pushState") { [weak self] (playerState: PlayerState) in
            if playerState.service == "audirvana" && self?.state.active != .audirvana {
                self?.state.active = .audirvana
            } else if let svc = playerState.service, svc != "audirvana", self?.state.active == .audirvana {
                // Service changed away from audirvana — reset to mpd
                self?.state.active = .mpd
            }
        }

        // Audirvana service start/stop → reactively sync engine state
        // pushAudirvanaStatus carries { service: { running: Bool } }
        socket.onRaw("pushAudirvanaStatus") { [weak self] data in
            guard let self else { return }
            if let dict = data.first as? [String: Any],
               let svc = dict["service"] as? [String: Any],
               let running = svc["running"] as? Bool {
                if running && self.state.active != .audirvana && !self.isSwitching {
                    self.state.active = .audirvana
                } else if !running && self.state.active == .audirvana && !self.isSwitching {
                    self.state.active = .mpd
                }
            }
        }
    }

    func switchTo(_ engine: AudioEngine, via socket: SocketService) {
        guard !isSwitching else { return }
        isSwitching = true
        switchError = nil
        socket.switchEngine(to: engine)

        // Timeout guard — if no response in 10s, reset switching state
        Task {
            try? await Task.sleep(for: .seconds(10))
            await MainActor.run {
                if self.isSwitching {
                    self.isSwitching = false
                    self.switchError = "Engine switch timed out"
                }
            }
        }
    }
}
