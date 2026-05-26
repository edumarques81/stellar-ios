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
        socket.onRawDict("pushLibraryArtists",
                         parser: PushLibraryArtists.init(rawDict:)) { [weak self] (payload: PushLibraryArtists) in
            self?.artists = payload.artists
            self?.loading = false
        }
        socket.onRawDict("pushLibraryArtistAlbums",
                         parser: PushLibraryArtistAlbums.init(rawDict:)) { [weak self] (payload: PushLibraryArtistAlbums) in
            self?.artistAlbums = payload.albums
            self?.loadingArtistAlbums = false
        }
        // See AlbumPickerStore for the rationale on this listener.
        socket.on("library:cache:updated") { [weak self] in
            self?.handleLibraryCacheUpdated()
        }
    }

    /// Refetch whatever the user is currently looking at. Always emits the
    /// artist-list refresh if the user has visited Artists at least once;
    /// additionally re-pulls the drilled-in artist's album list when one is
    /// selected (the most-foreground view). Empty store → no-op; the next
    /// `.onAppear` handles fresh load.
    func handleLibraryCacheUpdated() {
        if !artists.isEmpty {
            load()
        }
        if let selectedArtist {
            // Re-emit the drill-in without resetting `selectedArtist` so the
            // view stays on the same artist's screen across the refresh.
            loadingArtistAlbums = true
            socket?.emitObject("library:artist:albums", ["artist": selectedArtist.name])
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
