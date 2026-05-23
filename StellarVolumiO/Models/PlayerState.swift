import Foundation

// MARK: - Player State
// Mirrors the Volumio/Stellar backend pushState payload

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

    // Convenience
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

enum PlaybackStatus: String, Codable, Equatable {
    case play
    case pause
    case stop
}

// MARK: - Audio Engine
struct AudioEngineState: Codable, Equatable {
    var active: AudioEngine
    var mpdRunning: Bool
    var audirvanaRunning: Bool

    static let `default` = AudioEngineState(
        active: .mpd,
        mpdRunning: true,
        audirvanaRunning: false
    )
}

enum AudioEngine: String, Codable, Equatable {
    case mpd
    case audirvana

    var displayName: String {
        switch self {
        case .mpd: return "MPD"
        case .audirvana: return "Audirvana"
        }
    }
}

// MARK: - Browse Items
struct BrowseItem: Codable, Identifiable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let albumart: String?
    let uri: String
    let service: String
    let type: String       // "album", "artist", "song", "folder" etc.

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, albumart, uri, service, type
    }
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
