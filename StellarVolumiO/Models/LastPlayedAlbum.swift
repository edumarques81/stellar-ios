import Foundation

/// Resume-state payload pushed by the backend on connect + every album boundary.
/// Per `Volumio2-UI/CLAUDE.md` the payload may be JSON null on a fresh backend.
struct LastPlayedAlbum: Equatable {
    let artist: String
    let album: String
    let albumArt: String
    let trackUri: String
    let trackType: String
    let sampleRate: String
    let bitDepth: String

    init?(rawDict d: [String: Any]) {
        let artist = d["artist"] as? String ?? ""
        let album  = d["album"]  as? String ?? ""
        // Reject if both anchor fields are empty — the row is not playable.
        guard !(artist.isEmpty && album.isEmpty) else { return nil }
        self.artist     = artist
        self.album      = album
        self.albumArt   = d["albumArt"]   as? String ?? ""
        self.trackUri   = d["trackUri"]   as? String ?? ""
        self.trackType  = d["trackType"]  as? String ?? ""
        self.sampleRate = d["sampleRate"] as? String ?? ""
        self.bitDepth   = d["bitDepth"]   as? String ?? ""
    }
}
