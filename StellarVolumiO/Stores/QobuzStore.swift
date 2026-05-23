import Foundation
import Observation

@Observable
final class QobuzStore {
    var isLoggedIn: Bool = false
    var email: String? = nil
    var subscription: String? = nil
    var isLoading: Bool = false
    var error: String? = nil

    func bind(to socket: SocketService) {
        // Current Qobuz status
        socket.onRaw("pushQobuzStatus") { [weak self] data in
            guard let self else { return }
            guard let dict = data.first as? [String: Any] else { return }
            Task { @MainActor in
                self.isLoggedIn = dict["loggedIn"] as? Bool ?? false
                self.email = dict["email"] as? String
                self.subscription = dict["subscription"] as? String
                if let err = dict["error"] as? String { self.error = err }
            }
        }

        // Login result
        socket.onRaw("pushQobuzLoginResult") { [weak self] data in
            guard let self else { return }
            guard let dict = data.first as? [String: Any] else { return }
            Task { @MainActor in
                self.isLoading = false
                let success = dict["success"] as? Bool ?? false
                if success {
                    self.error = nil
                    if let status = dict["status"] as? [String: Any] {
                        self.isLoggedIn = status["loggedIn"] as? Bool ?? true
                        self.email = status["email"] as? String
                        self.subscription = status["subscription"] as? String
                    } else {
                        self.isLoggedIn = true
                    }
                } else {
                    self.error = dict["error"] as? String ?? "Login failed"
                }
            }
        }

        // Logout result
        socket.onRaw("pushQobuzLogoutResult") { [weak self] data in
            guard let self else { return }
            guard let dict = data.first as? [String: Any] else { return }
            Task { @MainActor in
                self.isLoading = false
                let success = dict["success"] as? Bool ?? false
                if success {
                    self.isLoggedIn = false
                    self.email = nil
                    self.subscription = nil
                    self.error = nil
                } else {
                    self.error = dict["error"] as? String ?? "Logout failed"
                }
            }
        }

        // Request initial status
        socket.emit("getQobuzStatus")
    }

    func login(email: String, password: String, via socket: SocketService) {
        isLoading = true
        error = nil
        socket.emit("qobuzLogin", data: [["email": email, "password": password]])
    }

    func logout(via socket: SocketService) {
        isLoading = true
        error = nil
        socket.emit("qobuzLogout")
    }
}
