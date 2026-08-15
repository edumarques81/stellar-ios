import Foundation
import Observation

/// Drop-box ingest store — the phone's half of the `ingest:*` contract.
///
/// The flow is deliberately two-step: `preview()` runs the script with
/// `--dry-run` and the backend answers with a plan plus a token; `commit()`
/// hands that token back. Committing without a token is refused server-side,
/// so the confirmation step cannot be skipped even by accident, and a plan
/// that no longer matches the inbox is rejected rather than executed.
///
/// Preview and result arrive as BROADCASTS, not replies. A run started on the
/// LCD lands here too, which is the point — the phone must not keep offering a
/// plan for files the kiosk already ingested. Errors are the exception: the
/// backend sends those only to the client that caused them.
///
/// The gate matters on this surface specifically. The kiosk is loopback and is
/// always authorized; the phone is not, so an `unauthorized` error here means
/// `STELLAR_INGEST_TRUSTED_REMOTES` on the Pi does not cover this device.
@Observable
final class IngestStore {

    /// What *this* device is waiting for. Driven by the local tap, not by
    /// broadcasts: a commit the LCD started should not spin this screen's own
    /// Import button.
    enum Phase {
        case idle
        case previewing
        case committing
    }

    private(set) var status: IngestStatus?
    private(set) var preview: IngestReport?
    private(set) var result: IngestReport?
    private(set) var lastError: IngestError?
    private(set) var phase: Phase = .idle

    private weak var socket: SocketService?

    // MARK: - Derived

    /// False on a backend with no ingest script — the row stays hidden rather
    /// than offering a button that can only fail.
    var isAvailable: Bool { status?.available == true }

    /// Something is waiting in the inbox.
    var hasItems: Bool { (status?.count ?? 0) > 0 }

    /// A run is in flight — this device's or another's.
    var isBusy: Bool { status?.busy == true || phase != .idle }

    /// A plan is on screen and can be confirmed.
    var canCommit: Bool {
        phase == .idle && preview?.token != nil && (preview?.summary.wouldIngest ?? 0) > 0
    }

    // MARK: - Wiring

    func bind(to socket: SocketService) {
        self.socket = socket
        socket.on("pushIngestStatus") { [weak self] (s: IngestStatus) in self?.apply(status: s) }
        socket.on("pushIngestPreview") { [weak self] (r: IngestReport) in self?.apply(preview: r) }
        socket.on("pushIngestResult") { [weak self] (r: IngestReport) in self?.apply(result: r) }
        socket.on("pushIngestError") { [weak self] (e: IngestError) in self?.apply(error: e) }
    }

    // MARK: - Push application
    //
    // The four `apply` methods are the whole write surface: `bind(to:)` is a
    // thin adapter over them, so a test that calls these exercises the same
    // transitions the socket does, with no seam that only exists for tests.

    func apply(status: IngestStatus) {
        self.status = status
    }

    func apply(preview report: IngestReport) {
        preview = report
        phase = .idle
    }

    func apply(result report: IngestReport) {
        result = report
        // The plan has been spent; its token will never be accepted again.
        preview = nil
        phase = .idle
    }

    func apply(error err: IngestError) {
        lastError = err
        phase = .idle
        // A stale plan is the one error whose remedy is previewing again, so
        // drop the dead plan instead of leaving an Import button that cannot
        // work.
        if err.retryable {
            preview = nil
        }
    }

    // MARK: - Actions

    /// Ask what is sitting in the inbox. Cheap: a directory listing, no script.
    func requestStatus() {
        socket?.emit("ingest:status")
    }

    /// Run the dry run. The plan comes back as a broadcast, so every surface
    /// sees the same thing before anyone confirms.
    func previewInbox() {
        guard let socket, phase == .idle else { return }
        lastError = nil
        result = nil
        preview = nil
        phase = .previewing
        socket.emit("ingest:preview")
    }

    /// Confirm the plan currently on screen.
    func commit() {
        guard let socket, let token = preview?.token, phase == .idle else { return }
        lastError = nil
        phase = .committing
        socket.emitObject("ingest:commit", ["token": token])
    }

    /// Drop the plan without running it.
    func cancel() {
        preview = nil
        lastError = nil
    }

    /// Dismiss the result / error banner.
    func dismiss() {
        result = nil
        lastError = nil
    }
}
