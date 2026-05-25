import Foundation
import Observation

/// Persistent, observable backend host/port/scheme configuration.
///
/// The Stellar app previously hardcoded its backend host in
/// `Services/SocketService.swift`. This store replaces that constant with a
/// three-tier fallback chain:
///
///   1. **Custom** — user-entered values in Settings (Manual entry).
///   2. **Discovered** — last successful Bonjour discovery result
///      (`BackendDiscoveryService.recordDiscovered(...)`).
///   3. **Default** — the original hardcoded `192.168.86.221:3000` over `http`.
///
/// This preserves the original out-of-the-box behaviour so users who never open
/// Settings still connect to the existing Mac stellar backend.
///
/// Persisted to `UserDefaults.standard` under the `backend.*` namespace.
@Observable
final class BackendConfigStore {

    // MARK: - UserDefaults keys (file-scoped namespace)

    enum Key {
        static let customHost       = "backend.customHost"
        static let customPort       = "backend.customPort"
        static let customScheme     = "backend.customScheme"
        static let discoveredHost   = "backend.lastDiscoveredHost"
        static let discoveredPort   = "backend.lastDiscoveredPort"
    }

    // MARK: - Defaults (last-resort fallback)
    //
    // Preserved from `SocketService.defaultHost` so a fresh install (no custom
    // config, no discovered server) keeps the existing connect-on-launch
    // behaviour without surprise.
    static let defaultHost: String   = "192.168.86.221"
    static let defaultPort: Int      = 3000
    static let defaultScheme: String = "http"

    // MARK: - Storage

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Trigger initial read so @Observable tracks the underlying storage.
        _ = self.host
    }

    // MARK: - Resolved values (read by SocketService + UI)

    /// Resolved host. Custom > discovered > default.
    var host: String {
        if let custom = trimmedCustomHost { return custom }
        if let discovered = discoveredHost { return discovered }
        return Self.defaultHost
    }

    /// Resolved port. Custom > discovered > default.
    var port: Int {
        if let custom = customPort { return custom }
        if let discovered = discoveredPort { return discovered }
        return Self.defaultPort
    }

    /// Resolved scheme. Custom > default (`http`). Discovered Bonjour does not
    /// carry a scheme today — backend mDNS always advertises plain HTTP.
    var scheme: String {
        if let custom = trimmedCustomScheme { return custom }
        return Self.defaultScheme
    }

    /// Human-readable URL string for "you are connected to X" UI.
    var currentURLString: String {
        "\(scheme)://\(host):\(port)"
    }

    /// True when the user has stored a custom host or port. Used by Settings
    /// to enable the "Reset to default" affordance.
    var hasCustomConfig: Bool {
        trimmedCustomHost != nil || customPort != nil || trimmedCustomScheme != nil
    }

    // MARK: - Raw custom accessors (visible to UI for the Manual entry form)

    /// The raw custom host as stored. `nil` if absent. Whitespace-trimmed and
    /// nil if empty after trimming.
    var customHost: String? { trimmedCustomHost }

    /// Validated custom port. `nil` if absent or out of `1...65535`.
    var customPort: Int? {
        guard defaults.object(forKey: Key.customPort) != nil else { return nil }
        let raw = defaults.integer(forKey: Key.customPort)
        return (1...65535).contains(raw) ? raw : nil
    }

    /// Validated custom scheme (`http` or `https`). `nil` if unset.
    var customScheme: String? { trimmedCustomScheme }

    // MARK: - Last-discovered (written by BackendDiscoveryService)

    var discoveredHost: String? {
        let raw = defaults.string(forKey: Key.discoveredHost)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    var discoveredPort: Int? {
        guard defaults.object(forKey: Key.discoveredPort) != nil else { return nil }
        let raw = defaults.integer(forKey: Key.discoveredPort)
        return (1...65535).contains(raw) ? raw : nil
    }

    // MARK: - Mutations

    /// Validation errors surfaced by the Manual entry form.
    enum ValidationError: Error, Equatable {
        case emptyHost
        case invalidPort
        case invalidScheme
    }

    /// Set a custom host/port/scheme triplet. Pass `nil` for any field to leave
    /// that slot at its previous custom value. Throws on validation failure
    /// and leaves storage untouched.
    func setCustom(host newHost: String?, port newPort: Int?, scheme newScheme: String?) throws {
        // Validate host: non-empty after trim.
        if let newHost {
            let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ValidationError.emptyHost }
        }
        // Validate port: 1...65535.
        if let newPort {
            guard (1...65535).contains(newPort) else { throw ValidationError.invalidPort }
        }
        // Validate scheme: http or https only.
        if let newScheme {
            let normalised = newScheme
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard normalised == "http" || normalised == "https" else {
                throw ValidationError.invalidScheme
            }
        }

        // Persist (we already validated all non-nil fields above).
        if let newHost {
            defaults.set(
                newHost.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Key.customHost
            )
        }
        if let newPort {
            defaults.set(newPort, forKey: Key.customPort)
        }
        if let newScheme {
            defaults.set(
                newScheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                forKey: Key.customScheme
            )
        }
        // Touch `host` to make @Observable readers (SocketService, Settings UI)
        // see a change tick.
        _ = host
    }

    /// Forget any custom host/port/scheme. The fallback chain falls back to
    /// the last-discovered server (if any) or the hardcoded default.
    func clearCustom() {
        defaults.removeObject(forKey: Key.customHost)
        defaults.removeObject(forKey: Key.customPort)
        defaults.removeObject(forKey: Key.customScheme)
        _ = host
    }

    /// Persist a successful Bonjour discovery result. Called by
    /// `BackendDiscoveryService` when the user picks a discovered server (or,
    /// in a future enhancement, when auto-select decides on one).
    ///
    /// Stored even when a custom config is present — discovered values are
    /// the second-tier fallback if the user later calls `clearCustom()`.
    func recordDiscovered(host: String, port: Int) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, (1...65535).contains(port) else { return }
        defaults.set(trimmed, forKey: Key.discoveredHost)
        defaults.set(port, forKey: Key.discoveredPort)
        _ = self.host
    }

    // MARK: - Private trimming helpers

    private var trimmedCustomHost: String? {
        let raw = defaults.string(forKey: Key.customHost)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    private var trimmedCustomScheme: String? {
        let raw = defaults.string(forKey: Key.customScheme)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let raw, !raw.isEmpty else { return nil }
        // Defensive: if storage somehow contains junk, ignore it.
        return (raw == "http" || raw == "https") ? raw : nil
    }
}
