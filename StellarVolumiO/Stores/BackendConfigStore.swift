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
    ///
    /// Sanitizes any colon-suffix at read time so a pre-existing dirty value
    /// (e.g. "Eduardos-Laptop.local:3000" stored by a build before the
    /// host:port splitting fix landed) can't propagate down to the URL
    /// builder. Regression: an already-crashed user must recover on next
    /// launch without an uninstall.
    var host: String {
        if let custom = trimmedCustomHost { return Self.stripAuthorityDecoration(custom).host }
        if let discovered = discoveredHost { return Self.stripAuthorityDecoration(discovered).host }
        return Self.defaultHost
    }

    /// Resolved port. Custom > discovered > default.
    ///
    /// Promotes a port embedded in a dirty custom host (e.g. "host:3000")
    /// when the explicit custom port slot is absent. Same recovery rationale
    /// as the `host` getter above.
    var port: Int {
        if let custom = customPort { return custom }
        if let trimmed = trimmedCustomHost,
           let embedded = Self.stripAuthorityDecoration(trimmed).port {
            return embedded
        }
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
    ///
    /// **host parsing**: accepts forms like `host`, `host:port`, and
    /// `scheme://host:port`. An embedded port is split into the port slot
    /// (unless the caller also passed an explicit `newPort`, which wins).
    /// An embedded scheme is split into the scheme slot (unless the caller
    /// also passed `newScheme`). This lets users paste a URL directly into
    /// the form's host field without triggering the previous "verbatim
    /// stored → URL builder gets `http://host:port:port` → force-unwrap
    /// nil → app panic on every launch" failure mode (regression
    /// 2026-05-27).
    func setCustom(host newHost: String?, port newPort: Int?, scheme newScheme: String?) throws {
        // Pre-split the host first so the rest of the validation sees the
        // canonical form.
        var splitHost: String? = nil
        var splitPort: Int? = nil
        var splitScheme: String? = nil
        if let newHost {
            let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ValidationError.emptyHost }
            let parts = Self.parseAuthority(trimmed)
            splitHost = parts.host
            // If the embedded port is non-numeric or out of range, surface
            // a hard error rather than silently dropping it — the user
            // intended to specify a port, we just couldn't parse it.
            if let raw = parts.rawPort {
                guard let n = Int(raw), (1...65535).contains(n) else {
                    throw ValidationError.invalidPort
                }
                splitPort = n
            }
            splitScheme = parts.scheme
            guard let h = splitHost, !h.isEmpty else { throw ValidationError.emptyHost }
        }

        // Validate port: 1...65535. The explicit argument beats whatever
        // was embedded in the host; that matches form-field intent.
        let effectivePort: Int?
        if let newPort {
            guard (1...65535).contains(newPort) else { throw ValidationError.invalidPort }
            effectivePort = newPort
        } else {
            effectivePort = splitPort
        }

        // Validate scheme: http or https only. Same precedence rule as port.
        let effectiveScheme: String?
        if let newScheme {
            let normalised = newScheme
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard normalised == "http" || normalised == "https" else {
                throw ValidationError.invalidScheme
            }
            effectiveScheme = normalised
        } else if let s = splitScheme {
            guard s == "http" || s == "https" else { throw ValidationError.invalidScheme }
            effectiveScheme = s
        } else {
            effectiveScheme = nil
        }

        // Persist (all non-nil fields validated above).
        if let h = splitHost {
            defaults.set(h, forKey: Key.customHost)
        }
        if let p = effectivePort {
            defaults.set(p, forKey: Key.customPort)
        }
        if let s = effectiveScheme {
            defaults.set(s, forKey: Key.customScheme)
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

    // MARK: - Authority parsing
    //
    // The host field of the Manual entry form gets typed by humans who may
    // paste a full URL ("http://foo.local:3000"), a host:port pair
    // ("foo.local:3000"), or just a hostname ("foo.local"). All three
    // shapes are normalised here so the rest of the code only ever sees
    // the canonical {scheme, host, port} triple. IPv6 literals (bracketed
    // `[::1]`) are out of scope — the backend has never used one.

    /// Parsed pieces of a host-field string. `rawPort` is kept as a String so
    /// the caller can surface a precise validation error if it's non-numeric
    /// or out of range; converting here would force a silent drop.
    struct AuthorityParts {
        var scheme: String?
        var host: String
        var rawPort: String?
    }

    /// Decompose a host-field string. Tolerates pasted URLs, `host:port`
    /// pairs, and bare hostnames. Returns `(scheme, host, port)`.
    static func parseAuthority(_ raw: String) -> AuthorityParts {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pull off a scheme prefix if present.
        var scheme: String? = nil
        if let schemeRange = s.range(of: "://") {
            let prefix = s[s.startIndex..<schemeRange.lowerBound].lowercased()
            scheme = prefix
            s = String(s[schemeRange.upperBound...])
        }

        // Drop anything after the first `/`, `?`, or `#` — that's a path,
        // not part of the authority.
        if let cut = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            s = String(s[s.startIndex..<cut])
        }

        // Split on the LAST `:` (handles IPv6-less inputs correctly).
        if let colon = s.lastIndex(of: ":") {
            let host = String(s[s.startIndex..<colon])
            let portPart = String(s[s.index(after: colon)...])
            return AuthorityParts(scheme: scheme, host: host, rawPort: portPart.isEmpty ? nil : portPart)
        }
        return AuthorityParts(scheme: scheme, host: s, rawPort: nil)
    }

    /// Read-time recovery helper used by the `host` / `port` getters.
    /// Returns the bare host plus a parsed port (when one was embedded and
    /// valid). Used to keep pre-existing dirty storage from crashing the
    /// URL builder on next launch — see `parseAuthority` for the regression
    /// it addresses.
    static func stripAuthorityDecoration(_ raw: String) -> (host: String, port: Int?) {
        let parts = parseAuthority(raw)
        let port: Int? = parts.rawPort.flatMap { Int($0) }.flatMap {
            (1...65535).contains($0) ? $0 : nil
        }
        return (parts.host, port)
    }
}
