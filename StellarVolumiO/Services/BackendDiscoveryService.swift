import Foundation
import Network
import Observation

/// One Stellar backend instance discovered on the local network.
struct DiscoveredServer: Identifiable, Equatable, Hashable {
    let id: String         // Bonjour-name based stable id.
    let name: String       // Service instance name (advertised by the server).
    let host: String       // Resolved hostname or IP literal.
    let port: Int          // Advertised port.
    let txt: [String: String]  // Parsed TXT record (e.g. path=/socket.io).
}

/// Wraps `NWBrowser` against `_stellar._tcp` and surfaces a debounced list of
/// resolved endpoints. Owned at app launch by `StellarApp`, injected into views
/// via `@Environment`.
///
/// **Discovery flow**
///
///   1. `startDiscovery()` creates an `NWBrowser` and begins receiving result
///      changes.
///   2. For each new `.added`, a short-lived `NWConnection` resolves the
///      service endpoint to a concrete host/port. The connection is cancelled
///      as soon as the path's `remoteEndpoint` is observed — we don't actually
///      talk to the server here.
///   3. Adds + removes are coalesced through a small `debounceWindow`
///      (default 750 ms) so a flapping device on the LAN doesn't churn the UI.
///
/// **Threading**
///
/// Internal state (the browser, pending timers, in-flight resolvers) lives on
/// a private serial dispatch queue. Final mutations of the observable
/// `discoveredServers` / `isBrowsing` are hopped to the main actor so SwiftUI
/// observers see them on the main run loop.
@Observable
final class BackendDiscoveryService {

    // MARK: - Public state (read on the main actor)

    /// Currently-visible servers. Updated on the main actor; safe to read from
    /// SwiftUI views.
    @MainActor var discoveredServers: [DiscoveredServer] = []

    /// True between `startDiscovery()` and `stopDiscovery()`. Surfaced in the
    /// Settings UI for a "Scanning…" affordance.
    @MainActor var isBrowsing: Bool = false

    /// Absolute deadline at which the auto-stop timer will fire and tear the
    /// browser down. `nil` whenever the service is not actively browsing.
    /// Read-only externally; tests / a diagnostic UI may sample this to show
    /// "auto-stops in N:NN" countdown copy.
    @MainActor private(set) var discoveryDeadline: Date?

    // MARK: - Configuration

    static let serviceType = "_stellar._tcp"

    /// Hard cap on how long `NWBrowser` may stay running without an explicit
    /// extension. Tunable here rather than scattered through callers. Default
    /// 1 minute keeps the local-network permission ping + battery cost
    /// bounded — the user only needs scanning active long enough to see and
    /// tap their backend in the Discover sheet, and re-opening the sheet
    /// re-arms the timer.
    static let maxDiscoveryDuration: TimeInterval = 60

    private let browserQueue = DispatchQueue(label: "fit.stellar.discovery", qos: .userInitiated)

    /// How long an add/remove must persist before we publish it. Guards
    /// against the brief disappear-then-reappear that `NWBrowser` produces
    /// when the underlying mDNS record is renewed.
    private let debounceWindow: TimeInterval

    /// Override for the auto-stop window. Production callers leave it at the
    /// `maxDiscoveryDuration` default; tests pass a much smaller value so
    /// the timer fires inside the test runtime budget.
    private let autoStopAfter: TimeInterval

    init(
        debounceWindow: TimeInterval = 0.75,
        autoStopAfter: TimeInterval = BackendDiscoveryService.maxDiscoveryDuration
    ) {
        self.debounceWindow = debounceWindow
        self.autoStopAfter = autoStopAfter
    }

    deinit {
        // browser?.cancel() is thread-safe; tearing it down here prevents
        // dangling NWBrowser callbacks after the service goes out of scope.
        browser?.cancel()
    }

    // MARK: - Browser state (browserQueue-isolated)

    /// Storage for the underlying `NWBrowser`. Access only on `browserQueue`
    /// from network callbacks; the `start/stop` entry points hop here too.
    private var browser: NWBrowser?

    /// Pending state changes that haven't yet cleared the debounce window.
    /// Keyed by the same id we use in `DiscoveredServer.id`.
    private var pendingAdds: [String: DispatchWorkItem] = [:]
    private var pendingRemoves: [String: DispatchWorkItem] = [:]

    /// In-flight endpoint resolutions, keyed by stable service id, so a stale
    /// callback for a service that has since been removed can be cancelled.
    private var resolvers: [String: NWConnection] = [:]

    /// Auto-stop timer. Lives on the main actor; cancelled + replaced on every
    /// `startDiscovery()` so re-triggers reset the deadline rather than
    /// stacking multiple expirations.
    @MainActor private var autoStopTask: Task<Void, Never>?

    // MARK: - Browser lifecycle

    /// Start scanning for `_stellar._tcp` services on the local network. Safe
    /// to call multiple times — repeat calls reset the 1-minute auto-stop
    /// deadline (so re-opening the Discover sheet keeps NWBrowser alive for
    /// another full window).
    @MainActor
    func startDiscovery() {
        // Optimistic flag flip on the main actor so the UI's "Scanning…"
        // affordance reacts immediately, even before the browser opens.
        isBrowsing = true
        // Reset the auto-stop deadline. Always cancel-then-arm so the
        // contract is "deadline = now + autoStopAfter, never stacked."
        armAutoStopTimer()
        browserQueue.async { [weak self] in
            self?._startOnQueue()
        }
    }

    /// Stop browsing and tear down any in-flight resolvers. Safe to call
    /// when not browsing.
    @MainActor
    func stopDiscovery() {
        isBrowsing = false
        cancelAutoStopTimer()
        browserQueue.async { [weak self] in
            self?._stopOnQueue()
        }
    }

    // MARK: - Auto-stop

    /// Cancel any in-flight auto-stop timer and arm a fresh one. Called from
    /// `startDiscovery()` on every invocation — the deadline always reflects
    /// "the most recent start, plus the configured window."
    @MainActor
    private func armAutoStopTimer() {
        autoStopTask?.cancel()
        let deadline = Date().addingTimeInterval(autoStopAfter)
        discoveryDeadline = deadline
        let nanos = UInt64(max(0, autoStopAfter) * 1_000_000_000)
        autoStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            // Re-check cancellation after the sleep — a manual stopDiscovery()
            // or a competing armAutoStopTimer() will have flipped this Task
            // into the cancelled state.
            guard let self, !Task.isCancelled else { return }
            // Idempotent stop — `stopDiscovery()` clears both the timer and
            // the deadline, so a no-op call here is harmless if the user
            // has already torn things down.
            self.stopDiscovery()
        }
    }

    /// Clear the deadline + cancel any pending auto-stop fire. Called both
    /// from manual `stopDiscovery()` and (transitively) when the auto-stop
    /// task fires its own `stopDiscovery()`.
    @MainActor
    private func cancelAutoStopTimer() {
        autoStopTask?.cancel()
        autoStopTask = nil
        discoveryDeadline = nil
    }

    private func _startOnQueue() {
        guard browser == nil else { return }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: Self.serviceType,
            domain: nil
        )
        let newBrowser = NWBrowser(for: descriptor, using: parameters)
        browser = newBrowser

        newBrowser.stateUpdateHandler = { [weak self] state in
            // NWBrowser exposes `.failed` when the local-network entitlement
            // hasn't been granted yet, or when there's no usable network. We
            // don't surface it to the user today — the manual entry path is
            // always available — but we do clear isBrowsing so the UI stops
            // showing a spinner.
            switch state {
            case .failed, .cancelled:
                Task { @MainActor in self?.isBrowsing = false }
            default:
                break
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] _, changes in
            // Stays on browserQueue — handler dispatches to it via NWBrowser.start(queue:).
            self?.handle(changes: changes)
        }

        newBrowser.start(queue: browserQueue)
    }

    private func _stopOnQueue() {
        browser?.cancel()
        browser = nil

        for (_, work) in pendingAdds { work.cancel() }
        for (_, work) in pendingRemoves { work.cancel() }
        pendingAdds.removeAll()
        pendingRemoves.removeAll()
        for (_, conn) in resolvers { conn.cancel() }
        resolvers.removeAll()
    }

    // MARK: - Change handling (browserQueue)

    private func handle(changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                scheduleAdd(for: result)
            case .removed(let result):
                scheduleRemove(for: result)
            case .changed(let old, let new, _):
                // Treat as remove + add — TXT or endpoint may have changed.
                scheduleRemove(for: old)
                scheduleAdd(for: new)
            default:
                break
            }
        }
    }

    private func scheduleAdd(for result: NWBrowser.Result) {
        let serviceId = Self.stableId(for: result)

        // If a remove is pending for this id, cancel it — the server is
        // back before the debounce expired.
        if let pendingRemove = pendingRemoves.removeValue(forKey: serviceId) {
            pendingRemove.cancel()
        }
        // Replace any pending add for this id.
        pendingAdds.removeValue(forKey: serviceId)?.cancel()

        // Resolve the endpoint to a concrete host:port via NWConnection.
        resolveEndpoint(for: result) { [weak self] resolved in
            guard let self else { return }
            // Resolution failure → drop silently. The UI just shows what we
            // managed to resolve.
            guard let server = resolved else { return }

            // Debounce the publication step: only commit after the window
            // has passed without a competing remove/add for this id.
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingAdds.removeValue(forKey: server.id)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let idx = self.discoveredServers.firstIndex(where: { $0.id == server.id }) {
                        self.discoveredServers[idx] = server
                    } else {
                        self.discoveredServers.append(server)
                    }
                }
            }
            self.pendingAdds[server.id] = workItem
            self.browserQueue.asyncAfter(deadline: .now() + self.debounceWindow, execute: workItem)
        }
    }

    private func scheduleRemove(for result: NWBrowser.Result) {
        let serviceId = Self.stableId(for: result)

        // Cancel any pending add — the server vanished before we got to publish it.
        pendingAdds.removeValue(forKey: serviceId)?.cancel()
        // Cancel any in-flight resolver.
        resolvers.removeValue(forKey: serviceId)?.cancel()
        // Replace any pending remove for this id.
        pendingRemoves.removeValue(forKey: serviceId)?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRemoves.removeValue(forKey: serviceId)
            Task { @MainActor [weak self] in
                self?.discoveredServers.removeAll(where: { $0.id == serviceId })
            }
        }
        pendingRemoves[serviceId] = workItem
        browserQueue.asyncAfter(deadline: .now() + debounceWindow, execute: workItem)
    }

    // MARK: - Endpoint resolution (browserQueue)
    //
    // NWBrowser hands us `NWEndpoint.service(...)` for Bonjour records, which
    // are not directly usable to open a Socket.IO connection. The standard
    // dance (per Apple's `NetService → NWConnection` sample code) is to open
    // a short-lived TCP connection to the service endpoint and observe its
    // `pathUpdateHandler` — `currentPath?.remoteEndpoint` resolves to a
    // concrete `hostPort` we can render.

    /// Attempt to resolve a discovered service to a `DiscoveredServer`. Calls
    /// `completion` exactly once on the browser queue. Times out after 4s.
    private func resolveEndpoint(
        for result: NWBrowser.Result,
        completion: @escaping (DiscoveredServer?) -> Void
    ) {
        let serviceId = Self.stableId(for: result)
        let displayName = Self.serviceName(for: result) ?? serviceId
        let txt = Self.txtRecord(for: result)

        let connection = NWConnection(to: result.endpoint, using: .tcp)
        var didComplete = false
        let finish: (DiscoveredServer?) -> Void = { [weak self] resolved in
            guard !didComplete else { return }
            didComplete = true
            connection.cancel()
            self?.resolvers.removeValue(forKey: serviceId)
            completion(resolved)
        }

        connection.pathUpdateHandler = { path in
            guard let endpoint = path.remoteEndpoint else { return }
            switch endpoint {
            case let .hostPort(host, port):
                let hostString = Self.string(from: host)
                finish(DiscoveredServer(
                    id: serviceId,
                    name: displayName,
                    host: hostString,
                    port: Int(port.rawValue),
                    txt: txt
                ))
            default:
                break
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                finish(nil)
            default:
                break
            }
        }

        resolvers[serviceId] = connection
        connection.start(queue: browserQueue)

        // Defensive timeout — if NWConnection never reports a remoteEndpoint
        // within 4s, drop the result rather than leaving a dangling resolver.
        browserQueue.asyncAfter(deadline: .now() + 4) {
            finish(nil)
        }
    }

    // MARK: - Helpers (pure, nonisolated)

    /// Stable identity for a browser result. Uses the Bonjour instance name
    /// when available, which survives across path-update churn for the same
    /// service.
    private static func stableId(for result: NWBrowser.Result) -> String {
        if let name = serviceName(for: result) {
            return "\(name).\(BackendDiscoveryService.serviceType)"
        }
        return String(describing: result.endpoint)
    }

    private static func serviceName(for result: NWBrowser.Result) -> String? {
        if case let .service(name, _, _, _) = result.endpoint {
            return name
        }
        return nil
    }

    /// Parse the TXT record into a `[String: String]` dictionary.
    private static func txtRecord(for result: NWBrowser.Result) -> [String: String] {
        if case let .bonjour(record) = result.metadata {
            return record.dictionary
        }
        return [:]
    }

    /// Convert an `NWEndpoint.Host` to a printable string (IP literal or hostname).
    private static func string(from host: NWEndpoint.Host) -> String {
        switch host {
        case let .ipv4(addr):    return "\(addr)"
        case let .ipv6(addr):    return "\(addr)"
        case let .name(name, _): return name
        @unknown default:        return ""
        }
    }
}

#if DEBUG
// MARK: - Test-only shims
//
// These let `BackendDiscoveryServiceTests` exercise the published state
// without an actual NWBrowser firing real Bonjour traffic.
extension BackendDiscoveryService {

    /// Insert a server directly (post-debounce). Tests use this to verify
    /// that `discoveredServers` is published on the main actor.
    @MainActor
    func _testInsert(_ server: DiscoveredServer) {
        if let idx = discoveredServers.firstIndex(where: { $0.id == server.id }) {
            discoveredServers[idx] = server
        } else {
            discoveredServers.append(server)
        }
    }

    /// Remove a server by id (post-debounce).
    @MainActor
    func _testRemove(id: String) {
        discoveredServers.removeAll(where: { $0.id == id })
    }
}
#endif
