import Foundation
import Observation

@Observable
final class LastPlayedStore {

    /// Latest last-played album from the backend. `nil` means MPD has never
    /// played anything in this backend's lifetime — show the empty state.
    var album: LastPlayedAlbum? = nil

    private weak var socket: SocketService?

    func bind(to socket: SocketService) {
        self.socket = socket
        socket.onRawDictNullable("pushLastPlayedAlbum",
                                  parser: LastPlayedAlbum.init(rawDict:)) { [weak self] album in
            self?.album = album
        }
    }

    /// Emit Volumio's `addPlay` to resume the saved track. Read-only state
    /// otherwise — this is the only mutator that triggers playback.
    func resume() {
        guard let socket, let a = album, !a.trackUri.isEmpty else { return }
        socket.emitObject("addPlay", [
            "service":  "mpd",
            "type":     "song",
            "uri":      a.trackUri,
            "title":    a.album,
            "artist":   a.artist,
            "albumart": a.albumArt
        ])
    }

    /// Explicit refresh (rarely needed — backend pushes proactively on connect).
    func refresh() {
        socket?.emit("library:lastPlayed:get")
    }
}
