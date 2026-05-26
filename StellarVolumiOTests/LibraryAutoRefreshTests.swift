import XCTest
@testable import StellarVolumiO

/// Coverage for the auto-refresh behaviour the three library pickers must
/// honour when the backend broadcasts `library:cache:updated` (after a
/// `library:cache:rebuild` finishes — e.g. when the NAS comes back online
/// or the user manually triggers a rebuild from the LCD).
///
/// Contract under test:
///  1. `AlbumPickerStore.handleLibraryCacheUpdated()` re-emits
///     `library:albums:list` IF and only if `albums` is non-empty (the
///     view has already been visited at least once). Empty → no-op, since
///     the next `.onAppear` will load fresh data anyway.
///  2. `ArtistPickerStore.handleLibraryCacheUpdated()` re-emits
///     `library:artists:list` IF `artists` is non-empty AND, additionally,
///     `library:artist:albums` for the currently-drilled-in artist IF one
///     is selected.
///  3. `AlbumTracksStore.handleLibraryCacheUpdated()` re-emits
///     `library:album:tracks` IF an album has been loaded (so the user is
///     currently viewing tracks — refresh keeps that view live).
@MainActor
final class LibraryAutoRefreshTests: XCTestCase {

    // MARK: - AlbumPickerStore

    func testAlbumPickerRefetchesWhenCacheUpdatedAndAlbumsAreLoaded() {
        let socket = SocketService()
        let store = AlbumPickerStore()
        store.bind(to: socket)

        // Simulate a previous successful load so .onAppear was visited.
        store.albums = [
            LibraryAlbum(id: "NAS/Daft Punk/Discovery",
                         title: "Discovery", artist: "Daft Punk",
                         uri: "NAS/Daft Punk/Discovery",
                         albumart: "/albumart?path=Daft%20Punk/Discovery")
        ]

        socket.resetEmittedObjectCapture()
        store.handleLibraryCacheUpdated()

        XCTAssertEqual(socket.lastEmittedObjectEvent, "library:albums:list",
                       "cache:updated must trigger a fresh albums:list emit when the picker has data")
        let payload = socket.lastEmittedObjectPayload ?? [:]
        XCTAssertEqual(payload["scope"] as? String, "all",
                       "auto-refresh uses the same defaults as the AlbumPicker view's load() call")
        XCTAssertEqual(payload["sort"]  as? String, "alphabetical")
        XCTAssertTrue(store.loading,
                      "auto-refresh must flip loading=true so the UI can surface a refresh spinner")
    }

    func testAlbumPickerSilentWhenCacheUpdatedAndAlbumsAreEmpty() {
        // Empty state = the user hasn't visited Albums yet. The next .onAppear
        // will load fresh data; firing a load now is wasted work + could
        // produce a flicker on a never-shown view.
        let socket = SocketService()
        let store = AlbumPickerStore()
        store.bind(to: socket)
        XCTAssertTrue(store.albums.isEmpty)

        socket.resetEmittedObjectCapture()
        store.handleLibraryCacheUpdated()

        XCTAssertNil(socket.lastEmittedObjectEvent,
                     "empty picker must NOT refetch on cache:updated — the next .onAppear handles it")
        XCTAssertFalse(store.loading,
                       "loading stays false when we deliberately skip the refetch")
    }

    // MARK: - ArtistPickerStore

    func testArtistPickerRefetchesArtistsListWhenCacheUpdatedAndArtistsAreLoaded() {
        let socket = SocketService()
        let store = ArtistPickerStore()
        store.bind(to: socket)

        store.artists = [LibraryArtist(id: "Daft Punk", name: "Daft Punk", albumCount: 3)]
        socket.resetEmittedObjectCapture()

        store.handleLibraryCacheUpdated()

        XCTAssertEqual(socket.lastEmittedObjectEvent, "library:artists:list",
                       "cache:updated must trigger a fresh artists:list emit when the picker has data")
        XCTAssertTrue(store.loading,
                      "auto-refresh must flip loading=true so the UI can surface a refresh spinner")
    }

    func testArtistPickerSilentWhenCacheUpdatedAndEverythingEmpty() {
        let socket = SocketService()
        let store = ArtistPickerStore()
        store.bind(to: socket)
        XCTAssertTrue(store.artists.isEmpty)
        XCTAssertNil(store.selectedArtist)

        socket.resetEmittedObjectCapture()
        store.handleLibraryCacheUpdated()

        XCTAssertNil(socket.lastEmittedObjectEvent,
                     "empty picker + no drill-in must NOT refetch")
        XCTAssertFalse(store.loading)
        XCTAssertFalse(store.loadingArtistAlbums)
    }

    func testArtistPickerRefetchesArtistAlbumsWhenDrilledIn() {
        let socket = SocketService()
        let store = ArtistPickerStore()
        store.bind(to: socket)

        let daft = LibraryArtist(id: "Daft Punk", name: "Daft Punk", albumCount: 3)
        store.artists = [daft]
        store.selectedArtist = daft
        store.artistAlbums = [
            LibraryAlbum(id: "NAS/Daft Punk/Discovery",
                         title: "Discovery", artist: "Daft Punk",
                         uri: "NAS/Daft Punk/Discovery",
                         albumart: "/albumart?path=Daft%20Punk/Discovery")
        ]

        socket.resetEmittedObjectCapture()
        store.handleLibraryCacheUpdated()

        // Refresh must hit BOTH endpoints: artists list + artist albums drill-in.
        // We can only assert on the LAST emit captured; verify the drill-in is
        // the last call, since views display it on top of the picker.
        XCTAssertEqual(socket.lastEmittedObjectEvent, "library:artist:albums",
                       "drill-in refresh must be the final emit (the view in focus)")
        let payload = socket.lastEmittedObjectPayload ?? [:]
        XCTAssertEqual(payload["artist"] as? String, "Daft Punk",
                       "drill-in refresh must carry the currently-selected artist's name")
        XCTAssertTrue(store.loadingArtistAlbums,
                      "drill-in must flip loadingArtistAlbums=true while the refetch is in flight")
    }

    // MARK: - AlbumTracksStore

    func testAlbumTracksRefetchesWhenCacheUpdatedAndAlbumIsLoaded() {
        let socket = SocketService()
        let store = AlbumTracksStore()
        store.bind(to: socket)

        // Simulate a previous load that completed: tracks present + the
        // store remembered the request shape for refresh.
        store.load(album: "Kind of Blue",
                   albumArtist: "Miles Davis",
                   uri: "NAS/Miles Davis/Kind of Blue")
        // Pretend the response landed.
        store.tracks = [
            Track(id: "t1", title: "So What", artist: "Miles Davis",
                  album: "Kind of Blue",
                  uri: "NAS/Miles Davis/Kind of Blue/01.flac",
                  trackNumber: 1, duration: 545, albumArt: "", source: "mpd")
        ]
        store.loading = false

        socket.resetEmittedObjectCapture()
        store.handleLibraryCacheUpdated()

        XCTAssertEqual(socket.lastEmittedObjectEvent, "library:album:tracks",
                       "cache:updated must trigger a fresh tracks fetch using the remembered album")
        let payload = socket.lastEmittedObjectPayload ?? [:]
        XCTAssertEqual(payload["album"]       as? String, "Kind of Blue",
                       "refresh must use the remembered album name")
        XCTAssertEqual(payload["albumArtist"] as? String, "Miles Davis",
                       "refresh must preserve the remembered albumArtist for disambiguation")
        XCTAssertEqual(payload["uri"]         as? String, "NAS/Miles Davis/Kind of Blue",
                       "refresh must preserve the remembered URI for folder-scoped lookups")
        XCTAssertTrue(store.loading,
                      "auto-refresh must flip loading=true")
    }

    func testAlbumTracksSilentWhenCacheUpdatedAndNoAlbumLoaded() {
        let socket = SocketService()
        let store = AlbumTracksStore()
        store.bind(to: socket)
        XCTAssertTrue(store.tracks.isEmpty)

        socket.resetEmittedObjectCapture()
        store.handleLibraryCacheUpdated()

        XCTAssertNil(socket.lastEmittedObjectEvent,
                     "without an album loaded there's nothing to refresh — refetch must be a no-op")
        XCTAssertFalse(store.loading)
    }
}
