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
        // The server's position is authoritative: re-anchor unconditionally so
        // a discontinuity it just reported (restarted track, scrub from the
        // LCD) survives the next interpolation tick instead of being
        // overwritten by the stale projection.
        anchorSeek(newState.seek)
        optimisticStatus = nil
        optimisticTimeoutTask?.cancel()
        optimisticTimeoutTask = nil
    }

    // Deliberately no `albumArtURL` here. The backend sends `albumart` as a
    // host-relative `/albumart?path=…`, so resolving it needs the socket's
    // current host:port — which the store does not know. The views that show
    // art build the absolute URL themselves (`NowPlayingView.mpdAlbumArt`,
    // `NowPlayingIdleView.artworkURL`, and the Library views). An
    // `http`-prefix-only helper here looked usable and silently returned nil
    // for every URL the backend actually sends.

    /// Position (ms) last received from the server, and the monotonic instant
    /// at which it was current. `tick()` projects forward from this anchor.
    private(set) var seekAnchorMs: Int = 0
    private(set) var seekAnchor: ContinuousClock.Instant?

    /// Re-anchor the local seek clock on an authoritative position (ms).
    func anchorSeek(_ milliseconds: Int, at instant: ContinuousClock.Instant = .now) {
        seekAnchorMs = max(0, milliseconds)
        seekAnchor = instant
    }

    /// Project `state.seek` forward from the anchor while the server says
    /// `.play`.
    ///
    /// The Stellar backend does not broadcast a pushState per second — it
    /// re-broadcasts when something meaningful changes, and (since 2026-08-14)
    /// when the true position diverges from what clients are predicting. In
    /// between, we dead-reckon.
    ///
    /// That reckoning is anchored on a monotonic instant rather than
    /// accumulated `+1s` per tick. Accumulating absorbs every source of timer
    /// error — `Task.sleep` slips past its deadline under load, and the hop to
    /// the main actor costs more still — so the counter falls progressively
    /// behind real playback with no way to notice. Mirrors
    /// `startSeekInterpolation` in Volumio2-UI's `player.ts`.
    func tick(now: ContinuousClock.Instant = .now) {
        guard state.status == .play else { return }

        // Self-heal: `state` assigned without going through
        // receiveServerState leaves no anchor. Adopt the current position
        // rather than freezing the clock until the next broadcast.
        guard let anchor = seekAnchor else {
            anchorSeek(state.seek, at: now)
            return
        }

        let elapsedMs = Int(anchor.duration(to: now) / .milliseconds(1))
        let projected = seekAnchorMs + max(0, elapsedMs)

        let durationMs = state.duration * 1000
        let bounded = durationMs > 0 ? min(projected, durationMs) : projected

        // Quantise to whole seconds: the UI renders seconds, so publishing at
        // sub-second resolution would drive @Observable re-renders four times
        // a second for no visible gain.
        let quantised = (bounded / 1_000) * 1_000
        if state.seek != quantised {
            state.seek = quantised
        }
    }

    /// Start the seek interpolator. Sampled at 4 Hz so the displayed second
    /// flips within 250ms of the true boundary, while `tick()` only publishes
    /// when the whole second actually changes. Safe to call multiple times —
    /// only one task runs at a time. Stopped automatically on `deinit`.
    func startSeekTicker() {
        guard seekTickerTask == nil else { return }
        seekTickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
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
                // Identical payload — still re-anchor (the server just
                // confirmed this position is current) and clear optimistic so
                // a missed server transition doesn't hang the button.
                self.anchorSeek(newState.seek)
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
