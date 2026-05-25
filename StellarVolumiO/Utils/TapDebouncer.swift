import Foundation

/// A tiny timestamp-based debouncer for user taps that fan out to a single
/// downstream side-effect (typically a Socket.IO emit).
///
/// Why this exists
/// ---------------
/// The Mac stellar backend was occasionally receiving two `replaceAndPlay`
/// events within ~3 seconds of each other when the user double-tapped the
/// "Play Album" CTA or a track row. The second `Clear()` empties the queue
/// while the first `Play(0)` is still in flight on the wire, and MPD answers
/// `Play(0)` with "Bad song index". The fix is server-friendly: drop the
/// duplicate before it leaves the device.
///
/// Why a struct, not a `DispatchQueue.asyncAfter` timer
/// ----------------------------------------------------
/// A timestamp comparison is the simplest correct primitive: zero cleanup,
/// no leaked work items, no thread-hop, and trivially testable with an
/// injected `now`. The "fire-after-delay" pattern would also coalesce, but
/// at the cost of a visible latency the user would feel on every tap.
///
/// Usage
/// -----
/// ```swift
/// @State private var debouncer = TapDebouncer(interval: 0.5)
///
/// Button("Play") {
///     if debouncer.attempt(at: .now) {
///         socket.emitObject("replaceAndPlay", payload)
///     }
/// }
/// ```
///
/// The debouncer is intentionally a value type — every view that needs its
/// own window owns its own instance via `@State`. Sharing one across views
/// is also fine (a single debouncer governing several tap surfaces in one
/// screen is the calling pattern in `AlbumTracksView`).
struct TapDebouncer {
    /// Minimum time that must elapse between accepted taps.
    let interval: TimeInterval

    /// Timestamp of the last accepted tap. `.distantPast` means "never fired",
    /// so the very first `attempt(at:)` always succeeds.
    private var lastAcceptedAt: Date = .distantPast

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Returns `true` if the tap should be accepted (and records `now` as the
    /// new "last accepted" timestamp). Returns `false` to indicate the caller
    /// should silently drop this tap.
    ///
    /// `now` is injected so tests can drive the clock without sleeping.
    mutating func attempt(at now: Date) -> Bool {
        guard now.timeIntervalSince(lastAcceptedAt) >= interval else {
            return false
        }
        lastAcceptedAt = now
        return true
    }
}
