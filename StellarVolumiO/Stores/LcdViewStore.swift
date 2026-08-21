import Foundation
import Observation

/// Tracks which screen the Pi's LCD kiosk is showing, and drives it.
///
/// Distinct from `LcdStore`, which owns panel *power*. The two are independent
/// on the wire: `lcdStandby`/`lcdWake` decide whether the panel is lit,
/// `lcdSetView` decides what is drawn on it.
@Observable
final class LcdViewStore {

    /// The screen the kiosk is currently showing. Defaults to `.player`, which
    /// is what the kiosk boots into, so the tab item renders sensibly before
    /// the first `pushLcdView` arrives.
    var view: LcdView = .player

    /// The screen the kiosk was on before `view`. Supplied by the backend so
    /// "back" doesn't require this app to keep its own history.
    private(set) var previousView: LcdView = .player

    /// True when the panel is showing the VU meter.
    var isShowingVuMeter: Bool { view == .vuMeter }

    private weak var socket: SocketService?

    func bind(to socket: SocketService) {
        self.socket = socket
        socket.on("pushLcdView") { [weak self] (status: LcdViewStatus) in
            guard let self else { return }
            // Never adopt a view this build can't name — it would make the
            // toggle's "back" target meaningless.
            if status.view != .unknown { self.view = status.view }
            if status.previousView != .unknown { self.previousView = status.previousView }
        }
    }

    /// Flip the kiosk to the VU meter, or back to whatever it was showing
    /// before. Optimistic: local state moves immediately for UI
    /// responsiveness, and `pushLcdView` reconciles.
    ///
    /// `wake: true` — hitting this means the user wants to *see* the change,
    /// so a panel in standby is powered on as part of the same action.
    func toggleVuMeter() {
        guard let socket else { return }

        let target = isShowingVuMeter ? returnTarget : .vuMeter
        previousView = view
        view = target
        socket.lcdSetView(target, wake: true)
    }

    /// Where "back" goes when leaving the VU meter.
    ///
    /// Falls back to `.player` when the remembered view is unusable — unknown
    /// to this build, or the VU meter itself (which would make the toggle a
    /// no-op and leave the user stuck on it).
    private var returnTarget: LcdView {
        switch previousView {
        case .vuMeter, .unknown: return .player
        default: return previousView
        }
    }

    func refresh() { socket?.getLcdView() }

    #if DEBUG
    /// Seed the state a `pushLcdView` frame would have produced, without
    /// standing up a socket. Tests only.
    func applyForTesting(view: LcdView, previousView: LcdView) {
        self.view = view
        self.previousView = previousView
    }
    #endif
}
