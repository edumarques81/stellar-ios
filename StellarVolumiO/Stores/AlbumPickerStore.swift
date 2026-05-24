import Foundation
import CryptoKit
import Observation

@Observable
final class AlbumPickerStore {

    var albums: [LibraryAlbum] = []
    var loading: Bool = false
    var lastError: String? = nil

    /// UserDefaults key for the persisted album-library fingerprint. Versioned
    /// (`v1`) so the schema can evolve without colliding with old installs.
    static let fingerprintKey = "AlbumLibrary.fingerprint.v1"

    private weak var socket: SocketService?

    func bind(to socket: SocketService) {
        self.socket = socket
        socket.onRawDict("pushLibraryAlbums",
                         parser: PushLibraryAlbums.init(rawDict:)) { [weak self] (payload: PushLibraryAlbums) in
            self?.albums = payload.albums
            self?.loading = false
            self?.lastError = nil
            self?.updateFingerprintAndInvalidateIfChanged()
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

    /// Recompute the library fingerprint from the current `albums` and
    /// compare against the value persisted in UserDefaults. If different,
    /// clear the album-art cache so the next view re-fetches. On first run
    /// (no previous fingerprint) we just persist — there's nothing to clear.
    private func updateFingerprintAndInvalidateIfChanged() {
        let current = Self.computeFingerprint(albums)
        let previous = UserDefaults.standard.string(forKey: Self.fingerprintKey)
        if let previous, previous != current {
            AlbumArtCache.invalidate()
        }
        UserDefaults.standard.set(current, forKey: Self.fingerprintKey)
    }

    /// Stable, order-independent SHA256 fingerprint of an album list.
    ///
    /// Uses each row's `uri` as identity when present (the canonical playable
    /// URI), falling back to `artist|title` for derived-from-tracks rows
    /// without a URI. Entries are sorted before hashing so the same library
    /// shuffled in a different order produces the same fingerprint. The
    /// `\u{1F}` (unit separator) joiner sidesteps any pathological collision
    /// from album titles that contain the chosen delimiter.
    ///
    /// Internal access so the unit tests can exercise it directly.
    static func computeFingerprint(_ list: [LibraryAlbum]) -> String {
        let parts = list
            .map { album -> String in
                album.uri.isEmpty ? "\(album.artist)|\(album.title)" : album.uri
            }
            .sorted()
            .joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(parts.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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
