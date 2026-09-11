import XCTest
@testable import StellarVolumiO

/// Mirrors the Svelte store suite (`Volumio2-UI/src/lib/stores/__tests__/ingest.test.ts`)
/// where the behaviour is shared: the two surfaces must agree about when
/// Import is offered and when a plan is dead.
///
/// `apply(status:)` / `apply(preview:)` / … are the store's real push-handling
/// methods — `bind(to:)` is a thin adapter over them — so these tests drive the
/// same code path the socket does without needing a live Pi.
@MainActor
final class IngestStoreTests: XCTestCase {

    /// A plan with one importable folder and a valid token.
    private func armedPreview(token: String? = "deadbeef") -> IngestReport {
        IngestReport(
            items: [IngestItem(name: "Holst The Planets", status: "would-ingest", audioFiles: 7)],
            summary: IngestSummary(total: 1, wouldIngest: 1),
            token: token
        )
    }

    // MARK: - Derived state

    func testHiddenUntilBackendReportsAvailable() {
        let store = IngestStore()
        XCTAssertFalse(store.isAvailable, "no status yet — the section must stay hidden")

        store.apply(status: IngestStatus(count: 2, available: false))
        XCTAssertFalse(store.isAvailable, "available=false means no ingest script on the Pi")

        store.apply(status: IngestStatus(count: 2, available: true))
        XCTAssertTrue(store.isAvailable)
        XCTAssertTrue(store.hasItems)
    }

    func testHasItemsIsFalseOnAnEmptyInbox() {
        let store = IngestStore()
        store.apply(status: IngestStatus(count: 0, available: true))
        XCTAssertTrue(store.isAvailable)
        XCTAssertFalse(store.hasItems)
    }

    func testBusyCoversARemoteRun() {
        let store = IngestStore()
        store.apply(status: IngestStatus(count: 1, available: true))
        XCTAssertFalse(store.isBusy)

        // A run started on the LCD.
        store.apply(status: IngestStatus(count: 1, busy: true, available: true))
        XCTAssertTrue(store.isBusy)
    }

    func testBusyCoversThisDevicesOwnRun() {
        let store = IngestStore()
        // Named local, not a temporary: the store holds the socket weakly, so
        // a `bind(to: SocketService())` would be deallocated before the tap and
        // every action would silently no-op.
        let socket = SocketService()
        store.bind(to: socket)
        store.apply(status: IngestStatus(count: 1, available: true))

        store.previewInbox()
        XCTAssertEqual(store.phase, .previewing)
        XCTAssertTrue(store.isBusy)
    }

    func testCanCommitRequiresATokenAndSomethingToDo() {
        let store = IngestStore()

        store.apply(preview: armedPreview())
        XCTAssertTrue(store.canCommit)

        // Everything refused — there is nothing to confirm.
        store.apply(preview: IngestReport(
            items: [IngestItem(name: "A", status: "refused", reason: "already in the library")],
            summary: IngestSummary(total: 1, refused: 1),
            token: "deadbeef"
        ))
        XCTAssertFalse(store.canCommit)

        // No token — the backend would refuse the commit anyway.
        store.apply(preview: armedPreview(token: nil))
        XCTAssertFalse(store.canCommit)
    }

    func testCanCommitIsFalseWhileCommitting() {
        let store = IngestStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.apply(preview: armedPreview())

        store.commit()
        XCTAssertEqual(store.phase, .committing)
        XCTAssertFalse(store.canCommit, "the Import button must not re-arm mid-run")
    }

    // MARK: - Actions

    func testActionsAreNoOpsWithoutASocket() {
        let store = IngestStore()

        store.previewInbox()
        XCTAssertEqual(store.phase, .idle, "no socket — must not enter a phase it can never leave")

        store.apply(preview: armedPreview())
        store.commit()
        XCTAssertEqual(store.phase, .idle)
    }

    func testCommitWithoutATokenIsANoOp() {
        let store = IngestStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.apply(preview: armedPreview(token: nil))

        store.commit()
        XCTAssertEqual(store.phase, .idle, "no token means nothing was emitted")
    }

    func testPreviewIsRefusedWhileACommitIsInFlight() {
        let store = IngestStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.apply(preview: armedPreview())
        store.commit()

        store.previewInbox()
        XCTAssertEqual(store.phase, .committing, "a second tap must not clobber the in-flight run")
    }

    func testPreviewClearsPriorResultAndError() {
        let store = IngestStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.apply(result: IngestReport(dryRun: false))
        store.apply(error: IngestError(phase: "commit", error: "boom", retryable: false))

        store.previewInbox()
        XCTAssertNil(store.result)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.phase, .previewing)
    }

    // MARK: - Broadcast handling

    func testResultSpendsThePlan() {
        let store = IngestStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.apply(preview: armedPreview())
        store.commit()

        store.apply(result: IngestReport(
            dryRun: false,
            items: [IngestItem(name: "Holst The Planets", status: "ingested", audioFiles: 7)],
            summary: IngestSummary(total: 1, ingested: 1)
        ))

        XCTAssertNil(store.preview, "the token is spent; the Import button must not re-offer it")
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(store.result?.summary.ingested, 1)
    }

    func testResultBroadcastFromAnotherSurfaceStillClearsThisPlan() {
        // The LCD committed while this screen was only showing the preview.
        let store = IngestStore()
        store.apply(preview: armedPreview())

        store.apply(result: IngestReport(dryRun: false, summary: IngestSummary(total: 1, ingested: 1)))

        XCTAssertNil(store.preview, "those files are gone from the inbox — stop offering them")
    }

    func testRetryableErrorDropsTheDeadPlan() {
        let store = IngestStore()
        store.apply(preview: armedPreview())

        store.apply(error: IngestError(phase: "commit", error: "plan is stale", retryable: true))

        XCTAssertNil(store.preview, "previewing again is the remedy, so clear the dead plan")
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(store.lastError?.error, "plan is stale")
    }

    func testNonRetryableErrorKeepsThePlanOnScreen() {
        let store = IngestStore()
        store.apply(preview: armedPreview())

        store.apply(error: IngestError(phase: "commit", error: "unauthorized", retryable: false))

        XCTAssertNotNil(store.preview, "an auth failure is not the plan's fault")
        XCTAssertEqual(store.phase, .idle)
    }

    // MARK: - Reconnect recovery
    //
    // `phase` latches on a reply this device is waiting for, and a reply can
    // only arrive on the connection that carried the request. A commit runs for
    // minutes, so a locked screen or a Wi-Fi blip during one loses
    // `pushIngestResult` for good — it is a one-shot broadcast to whoever was
    // connected, and the backend's connect-time replay only covers a plan still
    // awaiting confirmation, never a run that already finished. Observed
    // 2026-09-11: a four-minute commit left the iPad on "Importing…" for two and
    // a half hours. A fresh connection is proof the awaited reply can never
    // land, so it is the one moment the latch can be cleared safely.

    func testReconnectClearsAStrandedCommit() {
        let store = IngestStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.apply(preview: armedPreview())
        store.commit()
        XCTAssertEqual(store.phase, .committing)

        store.socketDidConnect()

        XCTAssertEqual(store.phase, .idle, "the result can never arrive on this connection")
        XCTAssertFalse(store.isBusy)
    }

    func testReconnectClearsAStrandedPreview() {
        let store = IngestStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.previewInbox()
        XCTAssertEqual(store.phase, .previewing)

        store.socketDidConnect()

        XCTAssertEqual(store.phase, .idle)
    }

    func testReconnectKeepsThePlanOnScreen() {
        // The backend replays a still-pending plan in its connect-time batch,
        // and that batch races this hook. Clearing the plan here would drop a
        // replay that had already landed, so the latch is all that is touched;
        // a plan whose token was spent is cleared by the retryable error the
        // next commit attempt returns.
        let store = IngestStore()
        let socket = SocketService()
        store.bind(to: socket)
        store.apply(status: IngestStatus(count: 1, available: true))
        store.apply(preview: armedPreview())

        store.socketDidConnect()

        XCTAssertNotNil(store.preview)
        XCTAssertTrue(store.canCommit)
        XCTAssertEqual(store.status?.count, 1, "status is re-requested, not invented")
    }

    func testReconnectWithoutASocketIsSafe() {
        let store = IngestStore()
        store.socketDidConnect()
        XCTAssertEqual(store.phase, .idle)
    }

    // MARK: - Dismissal

    func testCancelDropsThePlanButNotTheStatus() {
        let store = IngestStore()
        store.apply(status: IngestStatus(count: 3, available: true))
        store.apply(preview: armedPreview())

        store.cancel()
        XCTAssertNil(store.preview)
        XCTAssertEqual(store.status?.count, 3)
    }

    func testDismissClearsResultAndError() {
        let store = IngestStore()
        store.apply(result: IngestReport(dryRun: false))
        store.apply(error: IngestError(phase: "commit", error: "boom", retryable: false))

        store.dismiss()
        XCTAssertNil(store.result)
        XCTAssertNil(store.lastError)
    }

    // MARK: - Decode tolerance
    //
    // Go marshals a nil slice as `null`, so every collection must survive it.
    // A report that fails to decode leaves the sheet blank, which reads as
    // "nothing to import" — the worst possible failure for this feature.

    func testReportDecodesWithNullArraysAndMissingKeys() throws {
        let json: [String: Any] = [
            "schema": 1,
            "dryRun": true,
            "items": [
                [
                    "name": "Holst The Planets",
                    "status": "would-ingest",
                    "audioFiles": 7,
                    "tagged": NSNull(),
                    "tagFailures": NSNull(),
                    "md5Mismatches": NSNull(),
                ] as [String: Any]
            ],
            "summary": ["total": 1, "wouldIngest": 1],
            "token": "deadbeef",
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let report = try JSONDecoder().decode(IngestReport.self, from: data)

        XCTAssertEqual(report.token, "deadbeef")
        XCTAssertEqual(report.items.count, 1)
        XCTAssertEqual(report.items[0].audioFiles, 7)
        XCTAssertEqual(report.items[0].tagged, [])
        XCTAssertEqual(report.items[0].reason, "", "absent key falls back")
        XCTAssertEqual(report.summary.wouldIngest, 1)
        XCTAssertEqual(report.summary.refused, 0)
    }

    func testEmptyTokenDecodesAsNoToken() throws {
        let data = try JSONSerialization.data(withJSONObject: ["token": "", "dryRun": false])
        let report = try JSONDecoder().decode(IngestReport.self, from: data)
        XCTAssertNil(report.token, "an empty token must not arm the Import button")
    }

    func testStatusDecodesWithNullItems() throws {
        let data = try JSONSerialization.data(
            withJSONObject: ["items": NSNull(), "count": 0, "available": true]
        )
        let status = try JSONDecoder().decode(IngestStatus.self, from: data)
        XCTAssertEqual(status.items, [])
        XCTAssertTrue(status.available)
        XCTAssertFalse(status.busy)
    }

    // MARK: - Row ordering

    func testSortedPutsRefusalsFirstAndIsStableWithin() {
        let items = [
            IngestItem(name: "c", status: "ingested"),
            IngestItem(name: "a", status: "would-ingest"),
            IngestItem(name: "b", status: "refused"),
            IngestItem(name: "d", status: "would-ingest"),
        ]
        XCTAssertEqual(IngestSection.sorted(items).map(\.name), ["b", "a", "d", "c"])
    }
}
