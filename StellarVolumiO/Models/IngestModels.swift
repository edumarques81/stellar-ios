import Foundation

/// Wire models for the drop-box ingest (`ingest:*` / `pushIngest*`).
///
/// These mirror `internal/domain/ingest/report.go` on the backend. Go marshals
/// a nil slice as `null` rather than `[]`, and a script that predates a field
/// omits it entirely, so every field decodes tolerantly — a missing `tagged`
/// array must not sink the whole report and leave the sheet blank.

private extension KeyedDecodingContainer {
    /// Decode, or fall back. Absent key, null, and wrong type all fall back.
    ///
    /// `try?` flattens the double optional (SE-0230), so `decodeIfPresent`
    /// returning nil (absent key or explicit null) and it throwing (type
    /// mismatch) both collapse into the same nil here.
    func lenient<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

/// One inbox folder's outcome.
struct IngestItem: Decodable, Identifiable, Equatable {
    /// The folder name is unique within a run, and a run is what we render.
    var id: String { name }

    let name: String
    /// `ingested` | `would-ingest` | `refused` | `skipped`
    let status: String
    let reason: String
    let target: String
    let audioFiles: Int
    let tagged: [String]
    let tagFailures: [String]
    let md5Mismatches: [String]
    let mbRelease: String
    let art: String
    let notes: [String]

    enum CodingKeys: String, CodingKey {
        case name, status, reason, target, audioFiles
        case tagged, tagFailures, md5Mismatches, mbRelease, art, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenient(.name, "")
        status = c.lenient(.status, "")
        reason = c.lenient(.reason, "")
        target = c.lenient(.target, "")
        audioFiles = c.lenient(.audioFiles, 0)
        tagged = c.lenient(.tagged, [])
        tagFailures = c.lenient(.tagFailures, [])
        md5Mismatches = c.lenient(.md5Mismatches, [])
        mbRelease = c.lenient(.mbRelease, "")
        art = c.lenient(.art, "")
        notes = c.lenient(.notes, [])
    }

    /// Memberwise init for tests and previews.
    init(name: String, status: String, reason: String = "", target: String = "",
         audioFiles: Int = 0, tagged: [String] = [], tagFailures: [String] = [],
         md5Mismatches: [String] = [], mbRelease: String = "", art: String = "",
         notes: [String] = []) {
        self.name = name
        self.status = status
        self.reason = reason
        self.target = target
        self.audioFiles = audioFiles
        self.tagged = tagged
        self.tagFailures = tagFailures
        self.md5Mismatches = md5Mismatches
        self.mbRelease = mbRelease
        self.art = art
        self.notes = notes
    }
}

/// Per-run tally.
struct IngestSummary: Decodable, Equatable {
    let total: Int
    let ingested: Int
    let wouldIngest: Int
    let refused: Int
    let skipped: Int
    let tagFailures: Int
    let audioAltered: Int

    enum CodingKeys: String, CodingKey {
        case total, ingested, wouldIngest, refused, skipped, tagFailures, audioAltered
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.lenient(.total, 0)
        ingested = c.lenient(.ingested, 0)
        wouldIngest = c.lenient(.wouldIngest, 0)
        refused = c.lenient(.refused, 0)
        skipped = c.lenient(.skipped, 0)
        tagFailures = c.lenient(.tagFailures, 0)
        audioAltered = c.lenient(.audioAltered, 0)
    }

    init(total: Int = 0, ingested: Int = 0, wouldIngest: Int = 0, refused: Int = 0,
         skipped: Int = 0, tagFailures: Int = 0, audioAltered: Int = 0) {
        self.total = total
        self.ingested = ingested
        self.wouldIngest = wouldIngest
        self.refused = refused
        self.skipped = skipped
        self.tagFailures = tagFailures
        self.audioAltered = audioAltered
    }
}

/// A whole dry-run or commit document.
struct IngestReport: Decodable, Equatable {
    let schema: Int
    let dryRun: Bool
    let error: String
    let exitCode: Int
    let items: [IngestItem]
    let summary: IngestSummary
    /// Present only on a preview; must be handed back to commit.
    let token: String?

    enum CodingKeys: String, CodingKey {
        case schema, dryRun, error, exitCode, items, summary, token
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = c.lenient(.schema, 0)
        dryRun = c.lenient(.dryRun, false)
        error = c.lenient(.error, "")
        exitCode = c.lenient(.exitCode, 0)
        items = c.lenient(.items, [])
        summary = c.lenient(.summary, IngestSummary())
        // An empty-string token is the same as none. The backend omits the key
        // on a commit result, but a hand-rolled payload might send "".
        let raw: String = c.lenient(.token, "")
        token = raw.isEmpty ? nil : raw
    }

    init(schema: Int = 1, dryRun: Bool = true, error: String = "", exitCode: Int = 0,
         items: [IngestItem] = [], summary: IngestSummary = IngestSummary(),
         token: String? = nil) {
        self.schema = schema
        self.dryRun = dryRun
        self.error = error
        self.exitCode = exitCode
        self.items = items
        self.summary = summary
        self.token = token
    }
}

/// The cheap "is there anything waiting?" answer.
struct IngestStatus: Decodable, Equatable {
    let items: [String]
    let count: Int
    let busy: Bool
    /// False when the script or the inbox is missing — the UI hides itself.
    let available: Bool
    let error: String

    enum CodingKeys: String, CodingKey {
        case items, count, busy, available, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lenient(.items, [])
        count = c.lenient(.count, 0)
        busy = c.lenient(.busy, false)
        available = c.lenient(.available, false)
        error = c.lenient(.error, "")
    }

    init(items: [String] = [], count: Int = 0, busy: Bool = false,
         available: Bool = false, error: String = "") {
        self.items = items
        self.count = count
        self.busy = busy
        self.available = available
        self.error = error
    }
}

/// Payload of `pushIngestError`. Sent only to the client that caused it.
struct IngestError: Decodable, Equatable {
    /// `status` | `preview` | `commit`
    let phase: String
    let error: String
    /// True when previewing again can clear it (stale plan, already busy).
    let retryable: Bool

    enum CodingKeys: String, CodingKey {
        case phase, error, retryable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = c.lenient(.phase, "")
        error = c.lenient(.error, "")
        retryable = c.lenient(.retryable, false)
    }

    init(phase: String, error: String, retryable: Bool) {
        self.phase = phase
        self.error = error
        self.retryable = retryable
    }
}
