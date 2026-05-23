import Foundation
import Observation

@Observable
final class LcdStore {

    /// Last known LCD power state from the backend. Defaults to `true` so the
    /// toggle isn't visually OFF before the first `pushLcdStatus` arrives.
    var isOn: Bool = true

    private weak var socket: SocketService?

    func bind(to socket: SocketService) {
        self.socket = socket
        socket.on("pushLcdStatus") { [weak self] (status: LcdStatus) in
            self?.isOn = status.isOn
        }
    }

    /// Optimistic toggle: flip local state immediately for UI responsiveness,
    /// emit the corresponding command, and let pushLcdStatus reconcile.
    func setOn(_ value: Bool) {
        guard let socket else { return }
        isOn = value
        if value {
            socket.lcdWake()
        } else {
            socket.lcdStandby()
        }
    }

    func refresh() { socket?.getLcdStatus() }
}
