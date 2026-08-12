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

    /// ARTIST-04/BROWSE-04: populated when the drilled-in artist resolves to
    /// zero albums but has playable tracks outside any album. Only ever
    /// non-empty when `artistAlbums` is empty — the backend sends `looseTracks`
    /// only in that case, and this store mirrors that invariant on reset.
    var artistLooseTracks: [Track] = []

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
            self?.applyArtistAlbumsPayload(payload)
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

    /// Applies a `pushLibraryArtistAlbums` payload to store state. Extracted
    /// from the `bind(to:)` closure so unit tests can drive it directly
    /// (matching AlbumPickerStore.handleLibraryCacheUpdated's testability
    /// convention) without simulating a live socket event.
    func applyArtistAlbumsPayload(_ payload: PushLibraryArtistAlbums) {
        artistAlbums = payload.albums
        // Backend only ever sends looseTracks when albums is empty (ARTIST-04/
        // BROWSE-04), but guard defensively here too so stale/malformed
        // payloads can never show both a grid AND a loose-track fallback.
        artistLooseTracks = payload.albums.isEmpty ? (payload.looseTracks ?? []) : []
        loadingArtistAlbums = false
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
        artistLooseTracks = []
        loadingArtistAlbums = true
        socket.emitObject("library:artist:albums", ["artist": artist.name])
    }

    func clearSelection() {
        selectedArtist = nil
        artistAlbums = []
        artistLooseTracks = []
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
