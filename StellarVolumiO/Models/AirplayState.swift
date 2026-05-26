import Foundation

// MARK: - AirPlay State
//
// Mirrors the Stellar backend `pushAirplayState` payload — the AirPlay-source
// counterpart to `PlayerState` (the MPD-source contract). The two live as
// sibling models because their semantics are unrelated: an AirPlay session
// is opaque metadata pumped in from `shairport-sync` via the Pi daemon, with
// no MPD fields (queue position, repeat/shuffle flags, etc.) attached.
//
// Wire shape (locked, matches the backend + Volumio2-UI implementations):
//   {
//     "isActive":        Bool,
//     "title":           String,
//     "artist":          String,
//     "album":           String,
//     "sender":          String,    // e.g. "Eduardo's iPhone"
//     "coverDataURL":    String,    // "data:image/jpeg;base64,..."
//     "seekSeconds":     Int,
//     "durationSeconds": Int,
//     "canControl":      Bool,      // true once Active-Remote token is in hand
//     "sessionID":       String,    // stable across the session, drives pushAirplayEnded match
//     "sampleRate":      Int,       // 44100 / 48000 / ...
//     "bitDepth":        Int        // 16 / 24 / ...
//   }

struct AirplayState: Codable, Equatable {
    var isActive: Bool
    var title: String
    var artist: String
    var album: String
    var sender: String
    var coverDataURL: String
    var seekSeconds: Int
    var durationSeconds: Int
    var canControl: Bool
    var sessionID: String
    var sampleRate: Int
    var bitDepth: Int

    /// Display-friendly seek/duration (Double seconds) so SeekBar's
    /// `currentSeconds` / `totalSeconds` consume the same shape it gets
    /// from `PlayerState`.
    var seekSecondsDouble: Double { Double(seekSeconds) }
    var durationSecondsDouble: Double { Double(durationSeconds) }

    static let empty = AirplayState(
        isActive: false,
        title: "",
        artist: "",
        album: "",
        sender: "",
        coverDataURL: "",
        seekSeconds: 0,
        durationSeconds: 0,
        canControl: false,
        sessionID: "",
        sampleRate: 0,
        bitDepth: 0
    )
}

extension AirplayState {
    /// Tolerant parser for the Stellar backend `pushAirplayState` payload.
    /// Accepts Int-or-numeric-String for numeric fields and null/missing for
    /// any optional. Returns nil only when the input is not a dictionary.
    ///
    /// `coverDataURL` is passed through as an opaque string — we deliberately
    /// don't decode the base64 here. SwiftUI's image rendering layer in the
    /// view receives the raw data URL and decodes on render so a giant cover
    /// blob never blocks the socket-recv thread.
    init?(rawDict d: [String: Any]) {
        let s = AirplayState.empty
        self.init(
            isActive:        d["isActive"]      as? Bool       ?? s.isActive,
            title:           d["title"]         as? String     ?? s.title,
            artist:          d["artist"]        as? String     ?? s.artist,
            album:           d["album"]         as? String     ?? s.album,
            sender:          d["sender"]        as? String     ?? s.sender,
            coverDataURL:    d["coverDataURL"]  as? String     ?? s.coverDataURL,
            seekSeconds:     Self.parseInt(d["seekSeconds"])     ?? s.seekSeconds,
            durationSeconds: Self.parseInt(d["durationSeconds"]) ?? s.durationSeconds,
            canControl:      d["canControl"]    as? Bool       ?? s.canControl,
            sessionID:       d["sessionID"]     as? String     ?? s.sessionID,
            sampleRate:      Self.parseInt(d["sampleRate"])      ?? s.sampleRate,
            bitDepth:        Self.parseInt(d["bitDepth"])        ?? s.bitDepth
        )
    }

    private static func parseInt(_ any: Any?) -> Int? {
        if let v = any as? Int { return v }
        if let v = any as? Double { return Int(v) }
        if let v = any as? String, let n = Int(v) { return n }
        if let v = any as? String, let n = Double(v) { return Int(n) }
        return nil
    }
}

// MARK: - Ended payload
//
// `pushAirplayEnded` is the canonical end signal — we deliberately do NOT
// key end-of-session off `isActive: false` in the state payload. A stale
// "ended" event with a mismatched sessionID must never clear an already-
// active fresh session, so the iOS store filters on the embedded sessionID.

struct AirplayEnded: Codable, Equatable {
    var sessionID: String

    init?(rawDict d: [String: Any]) {
        guard let sid = d["sessionID"] as? String else { return nil }
        self.sessionID = sid
    }

    init(sessionID: String) {
        self.sessionID = sessionID
    }
}
