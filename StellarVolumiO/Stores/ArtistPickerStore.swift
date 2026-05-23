import Foundation
import Observation

@Observable
final class ArtistPickerStore {

    var artists: [LibraryArtist] = []
    var loading: Bool = false

    /// Albums for the currently-drilled-in artist, keyed by artist name.
    /// When `selectedArtist` is set, `artistAlbums` is fetched and populated.
    var selectedArtist: LibraryArtist? = nil
    var artistAlbums: [LibraryAlbum] = []
    var loadingArtistAlbums: Bool = false

    private weak var socket: SocketService?

    func bind(to socket: SocketService) {
        self.socket = socket
        socket.on("pushLibraryArtists") { [weak self] (payload: PushLibraryArtists) in
            self?.artists = payload.artists
            self?.loading = false
        }
        socket.on("pushLibraryArtistAlbums") { [weak self] (payload: PushLibraryArtistAlbums) in
            self?.artistAlbums = payload.albums
            self?.loadingArtistAlbums = false
        }
    }

    func load(scope: String = "all", sort: String = "alphabetical") {
        guard let socket else { return }
        loading = true
        let payload: [String: Any] = [
            "scope": scope,
            "sort":  sort,
            "limit": 500,
            "offset": 0
        ]
        socket.emitObject("library:artists:list", payload)
    }

    func select(_ artist: LibraryArtist) {
        guard let socket else { return }
        selectedArtist = artist
        artistAlbums = []
        loadingArtistAlbums = true
        socket.emitObject("library:artist:albums", ["artist": artist.name])
    }

    func clearSelection() {
        selectedArtist = nil
        artistAlbums = []
        loadingArtistAlbums = false
    }

    /// Convenience: play an album from the drilled-in artist's album list.
    /// Mirrors AlbumPickerStore.play() for shape consistency.
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
