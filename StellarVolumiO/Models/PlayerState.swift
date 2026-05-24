import Foundation

// MARK: - Player State
// Mirrors the Stellar backend pushState payload.

struct PlayerState: Codable, Equatable {
    var status: PlaybackStatus
    var title: String
    var artist: String
    var album: String
    var albumart: String
    var uri: String
    var service: String
    var duration: Int       // seconds
    var seek: Int           // milliseconds → divide by 1000
    var volume: Int         // 0–100
    var mute: Bool
    var shuffle: Bool
    var `repeat`: Bool
    var repeatSingle: Bool
    var trackType: String   // "flac", "mp3", "dsf" etc.
    var samplerate: String  // "96000"
    var bitdepth: String    // "24"
    var channels: Int

    var seekSeconds: Double { Double(seek) / 1000 }
    var durationSeconds: Double { Double(duration) }

    static let empty = PlayerState(
        status: .stop,
        title: "",
        artist: "",
        album: "",
        albumart: "",
        uri: "",
        service: "mpd",
        duration: 0,
        seek: 0,
        volume: 50,
        mute: false,
        shuffle: false,
        repeat: false,
        repeatSingle: false,
        trackType: "",
        samplerate: "",
        bitdepth: "",
        channels: 2
    )
}

extension PlayerState {
    /// Tolerant parser for the Stellar backend `pushState` payload. Accepts
    /// Int-or-numeric-String for numeric fields and null/missing for any
    /// optional. Unknown `status` falls back to `.stop`. Returns nil only
    /// when the input is not a dictionary.
    init?(rawDict d: [String: Any]) {
        let s = PlayerState.empty
        self.init(
            status:       Self.parseStatus(d["status"])    ?? s.status,
            title:        d["title"]      as? String       ?? s.title,
            artist:       d["artist"]     as? String       ?? s.artist,
            album:        d["album"]      as? String       ?? s.album,
            albumart:     d["albumart"]   as? String       ?? s.albumart,
            uri:          d["uri"]        as? String       ?? s.uri,
            service:      d["service"]    as? String       ?? s.service,
            duration:     Self.parseInt(d["duration"])     ?? s.duration,
            seek:         Self.parseInt(d["seek"])         ?? s.seek,
            volume:       Self.parseInt(d["volume"])       ?? s.volume,
            mute:         d["mute"]       as? Bool         ?? s.mute,
            shuffle:      d["shuffle"]    as? Bool         ?? s.shuffle,
            repeat:       d["repeat"]     as? Bool         ?? s.`repeat`,
            repeatSingle: d["repeatSingle"] as? Bool       ?? s.repeatSingle,
            trackType:    d["trackType"]  as? String       ?? s.trackType,
            samplerate:   d["samplerate"] as? String       ?? s.samplerate,
            bitdepth:     d["bitdepth"]   as? String       ?? s.bitdepth,
            channels:     Self.parseInt(d["channels"])     ?? s.channels
        )
    }

    private static func parseInt(_ any: Any?) -> Int? {
        if let v = any as? Int { return v }
        if let v = any as? Double { return Int(v) }
        if let v = any as? String, let n = Int(v) { return n }
        if let v = any as? String, let n = Double(v) { return Int(n) }
        return nil
    }

    private static func parseStatus(_ any: Any?) -> PlaybackStatus? {
        guard let s = any as? String else { return nil }
        return PlaybackStatus(rawValue: s.lowercased())
    }
}

enum PlaybackStatus: String, Codable, Equatable {
    case play
    case pause
    case stop
}

// MARK: - Queue Item
struct QueueItem: Codable, Identifiable {
    let id: Int
    let name: String
    let artist: String?
    let album: String?
    let albumart: String?
    let duration: Int
    let uri: String
    let service: String
    let trackType: String?

    var displayDuration: String {
        let mins = duration / 60
        let secs = duration % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
