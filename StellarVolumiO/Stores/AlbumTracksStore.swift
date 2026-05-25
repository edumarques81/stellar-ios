import Foundation
import Observation

/// Backs the Album Tracks screen. Owns the list of tracks for the album the
/// user just drilled into, plus a loading + error flag.
///
/// Flow:
/// 1. View calls `load(album:albumArtist:uri:)` on appear.
/// 2. Store flips `loading=true`, emits `library:album:tracks` via SocketService.
/// 3. Backend pushes `pushLibraryAlbumTracks` — the binding registered in
///    `bind(to:)` calls `apply(_:)` which populates `tracks` / `totalDuration`
///    or surfaces `errorMessage` if the backend signalled failure.
///
/// Mirrors `AlbumPickerStore` + `ArtistPickerStore` for shape consistency
/// (private weak socket, bind(to:) wires the listener, load() emits).
@Observable
final class AlbumTracksStore {

    var tracks: [Track] = []
    var totalDuration: Int = 0
    var loading: Bool = false
    var errorMessage: String? = nil

    /// The album + artist this store is currently showing. Reset on each
    /// load() so the view can detect a stale push from a previous request.
    var currentAlbum: String = ""
    var currentAlbumArtist: String = ""

    private weak var socket: SocketService?

    func bind(to socket: SocketService) {
        self.socket = socket
        socket.onLibraryAlbumTracks { [weak self] payload in
            self?.apply(payload)
        }
    }

    /// Request tracks for a specific album. `album` is required; `albumArtist`
    /// and `uri` disambiguate when multiple copies of the same album exist
    /// (different quality, different folder). Empty strings are dropped server-
    /// side, but we drop them client-side too so the wire payload stays clean.
    func load(album: String, albumArtist: String?, uri: String?) {
        guard let socket else { return }
        currentAlbum       = album
        currentAlbumArtist = albumArtist ?? ""
        loading       = true
        errorMessage  = nil
        socket.emitGetAlbumTracks(album: album, albumArtist: albumArtist, uri: uri)
    }

    /// Apply a `pushLibraryAlbumTracks` payload. Public so tests can drive
    /// the store without spinning up a real Socket.IO connection — mirrors
    /// `PlayerStore.receiveServerState` pattern.
    func apply(_ payload: PushLibraryAlbumTracks) {
        loading = false
        if let err = payload.error, !err.isEmpty {
            tracks = []
            totalDuration = 0
            errorMessage = err
            return
        }
        tracks        = payload.tracks
        totalDuration = payload.totalDuration
        errorMessage  = nil
    }
}
