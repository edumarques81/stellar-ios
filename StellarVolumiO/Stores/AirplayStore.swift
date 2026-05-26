import Foundation
import Observation

// MARK: - AirplayStore
//
// Sibling of `PlayerStore` that holds the AirPlay session view of the world.
// `NowPlayingView` reads `airplayStore.state.isActive` to decide which UI
// branch (AirPlay-source vs. MPD-source) to render — the two stores never
// touch each other.
//
// Lifecycle:
//   - `pushAirplayState` arrives → replace `state` if it differs.
//   - `pushAirplayEnded` arrives → clear `state` ONLY IF the embedded
//     sessionID matches the current state's sessionID. A stale end with
//     a mismatched sessionID is ignored so a delayed "ended" event can't
//     wipe out a fresh session that started immediately after.
//
// Seek ticking:
//   The backend emits state updates on metadata change (title/cover/etc.)
//   but not at sub-second cadence — see `PlayerStore.tick()` for the same
//   pattern. While `isActive` and `seekSeconds < durationSeconds`, advance
//   `seekSeconds` by 1 once per second so the SeekBar animates between
//   broadcasts.

@Observable
final class AirplayStore {

    /// Current AirPlay session state. `.empty` while no session is active.
    var state: AirplayState = .empty

    /// 1Hz seek interpolator handle. Started in `bind(to:)`, runs forever;
    /// the tick body short-circuits when `isActive` is false so it costs
    /// nothing while no AirPlay session exists.
    private var seekTickerTask: Task<Void, Never>? = nil

    // MARK: - Server-state intake

    /// Apply a server-truth state push. Replaces `state` unconditionally
    /// (the Equatable check inside `bind(to:)` already filters identical
    /// payloads — by the time we get here, something differs).
    func receiveServerState(_ newState: AirplayState) {
        state = newState
    }

    /// Apply a `pushAirplayEnded`. Only clears `state` if the ended
    /// sessionID matches the current sessionID — guards against a stale
    /// "ended" event clearing a fresh session.
    ///
    /// Edge case: if the current state has no sessionID yet (e.g. the
    /// "ended" arrived before any "state"), drop the ended event on the
    /// floor — there's nothing to clear and matching empty-string would
    /// be a logic error.
    func receiveEnded(_ ended: AirplayEnded) {
        guard !state.sessionID.isEmpty else { return }
        guard state.sessionID == ended.sessionID else { return }
        state = .empty
    }

    // MARK: - Seek ticker

    /// Advance `seekSeconds` by 1 while the session is active AND playing.
    /// The Stellar backend deliberately omits seek from its diff comparison
    /// — clients interpolate locally between broadcasts. Mirrors
    /// `PlayerStore.tick()`.
    ///
    /// Gating on `isPlaying` (in addition to `isActive`) means a session
    /// paused from the iPhone freezes the elapsed counter — without this,
    /// the seek bar would keep ticking past where the audio actually is.
    func tick() {
        guard state.isActive, state.isPlaying else { return }
        guard state.durationSeconds > 0 else {
            state.seekSeconds += 1
            return
        }
        state.seekSeconds = min(state.seekSeconds + 1, state.durationSeconds)
    }

    /// Start the 1Hz seek interpolator. Safe to call multiple times — only
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
    }

    // MARK: - Bind to socket

    private weak var socket: SocketService?

    func bind(to socket: SocketService) {
        self.socket = socket

        socket.onPushAirplayState { [weak self] newState in
            guard let self else { return }
            if self.state != newState {
                self.receiveServerState(newState)
            }
        }

        socket.onPushAirplayEnded { [weak self] ended in
            self?.receiveEnded(ended)
        }

        startSeekTicker()
    }

    // MARK: - Transport command emitters
    //
    // Thin pass-throughs over the SocketService AirPlay emitters. Wrapping
    // them here mirrors the PlayerStore tap-then-emit pattern: any future
    // optimism (e.g. spinner while DACP resolves) lives in the store, not
    // sprinkled in views.

    func play()      { socket?.airplayPlay() }
    func pause()     { socket?.airplayPause() }
    func playPause() { socket?.airplayPlayPause() }
    func next()      { socket?.airplayNext() }
    func prev()      { socket?.airplayPrev() }

    // MARK: - DEBUG fixture injection
    //
    // Lets the visual verification path drop a sample state into the store
    // without touching the socket layer. Used by SmokeTest + by a debug
    // toggle if/when we add one.

    #if DEBUG
    func _debugInject(_ s: AirplayState) {
        state = s
    }
    #endif
}
