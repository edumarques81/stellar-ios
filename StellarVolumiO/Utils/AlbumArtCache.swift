import Foundation

/// Persistent album-art cache built on top of `URLCache.shared`.
///
/// The backend serves `/albumart` responses with `Cache-Control: public,
/// max-age=86400` (see stellar backend `cmd/stellar/main.go:serveArtwork`),
/// so `URLCache.shared` will store them automatically — provided the shared
/// cache is configured with a real disk-backed store at app launch. That
/// configuration lives in `AlbumArtCache.configureSharedCache()` and is
/// invoked from `StellarApp.init()`.
///
/// Invalidation is driven by the album-library fingerprint maintained in
/// `AlbumPickerStore`: when the fingerprint changes (a `pushLibraryAlbums`
/// payload that differs from the previously-seen one), the store calls
/// `AlbumArtCache.invalidate()` to drop everything.
enum AlbumArtCache {

    /// Persistent disk-backed cache configuration applied to `URLCache.shared`.
    /// 50 MB memory + 500 MB disk under `Library/Caches/StellarCovers/`. Sized
    /// generously for typical local libraries (1k–5k albums × ~100 KB JPEG).
    static func configureSharedCache() {
        let memoryCapacity = 50 * 1024 * 1024
        let diskCapacity = 500 * 1024 * 1024
        let diskPath = "StellarCovers"
        let cache = URLCache(memoryCapacity: memoryCapacity,
                             diskCapacity: diskCapacity,
                             diskPath: diskPath)
        URLCache.shared = cache
    }

    /// Drop every cached response from `URLCache.shared`.
    ///
    /// We deliberately use the broad `removeAllCachedResponses()` rather than
    /// a per-URL targeted clear: the dominant cache content is album art, and
    /// any incidental non-art responses (none today — the app only fetches
    /// album covers via URLSession) will simply rebuild on next use. Keeping
    /// the implementation small avoids carrying a sidecar URL set.
    static func invalidate() {
        URLCache.shared.removeAllCachedResponses()
    }
}
