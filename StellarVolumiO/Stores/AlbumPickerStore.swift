import Foundation
import Observation

@Observable
final class AlbumPickerStore {

    var albums: [LibraryAlbum] = []
    var loading: Bool = false
    var lastError: String? = nil

    private weak var socket: SocketService?

    func bind(to socket: SocketService) {
        self.socket = socket
        socket.onRawDict("pushLibraryAlbums",
                         parser: PushLibraryAlbums.init(rawDict:)) { [weak self] (payload: PushLibraryAlbums) in
            self?.albums = payload.albums
            self?.loading = false
            self?.lastError = nil
        }
    }

    func load(scope: String = "all", sort: String = "alphabetical", query: String = "") {
        guard let socket else { return }
        loading = true
        var payload: [String: Any] = [
            "scope": scope,
            "sort":  sort,
            "limit": 500,
            "offset": 0
        ]
        if !query.isEmpty { payload["query"] = query }
        socket.emitObject("library:albums:list", payload)
    }

    /// Trigger playback for an album by clearing the queue and starting it.
    /// Matches `Volumio2-UI/src/lib/stores/library.ts` `replaceAndPlay` shape.
    func play(_ album: LibraryAlbum) {
        guard let socket else { return }
        guard !album.uri.isEmpty else { return }
        socket.emitObject("replaceAndPlay", [
            "service": "mpd",
            "type":    "album",
            "title":   album.title,
            "artist":  album.artist,
            "albumart": album.albumart,
            "uri":     album.uri
        ])
    }
}
