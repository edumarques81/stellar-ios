import XCTest
@testable import StellarVolumiO

/// `ForEach` is only defined when identities are unique, and the library's
/// identities are not.
///
/// `LibraryAlbum.id` is the album's `uri` (or `artist|title` when the uri is
/// empty), and a uri is not unique in practice. The Pi's library holds three
/// duplicated ones; `USB/To Awaken the Sleeper- Works of Joel Thompson` is
/// **five** rows, because a classical release tags a different `album_artist`
/// per track and the backend groups on it. Handed duplicate IDs, SwiftUI
/// silently drops views — the grid came back with holes in it: a tile alone in
/// the left column with nothing beside it, then a screen of blank space, then a
/// tile stranded on the right further down.
///
/// So identity is repaired at the wire boundary. Uniquifying rather than
/// de-duplicating is deliberate: those five rows are genuinely different albums
/// (different personnel, different track counts), and dropping four of them
/// would hide real music.
final class LibraryIdentityTests: XCTestCase {

    private func album(_ title: String, _ artist: String, uri: String) -> LibraryAlbum {
        LibraryAlbum(id: uri.isEmpty ? "\(artist)|\(title)" : uri,
                     title: title, artist: artist, uri: uri, albumart: "")
    }

    /// The live shape: five distinct albums behind one uri.
    func testFiveAlbumsSharingAUriGetFiveDistinctIdentities() {
        let uri = "USB/To Awaken the Sleeper- Works of Joel Thompson"
        let input = [
            album("To Awaken the Sleeper", "EXIGENCE Vocal Ensemble", uri: uri),
            album("To Awaken the Sleeper", "Kansas City Symphony; Michael Stern", uri: uri),
            album("To Awaken the Sleeper", "Kansas City Symphony; EXIGENCE", uri: uri),
            album("To Awaken the Sleeper", "Kansas City Symphony; Joyce DiDonato", uri: uri),
            album("To Awaken the Sleeper", "Kansas City Symphony; Yo-Yo Ma", uri: uri),
        ]

        let out = input.withUniqueIDs()

        XCTAssertEqual(out.count, 5, "no album may be dropped — they are different records")
        XCTAssertEqual(Set(out.map(\.id)).count, 5, "ids still collide: \(out.map(\.id))")
        XCTAssertEqual(out.map(\.artist), input.map(\.artist), "order and content must be untouched")
        XCTAssertEqual(out.map(\.uri), input.map(\.uri), "the playable uri must survive — it is not the identity")
        XCTAssertEqual(out[0].id, uri, "the first occurrence keeps the natural id")
    }

    /// A list that was already fine must come back untouched, so identity — and
    /// therefore scroll position and image cache hits — stays stable across a
    /// refresh.
    func testAlreadyUniqueListIsUnchanged() {
        let input = [
            album("Dookie", "Green Day", uri: "USB/Dookie"),
            album("Tracker", "Mark Knopfler", uri: "USB/Tracker"),
        ]
        XCTAssertEqual(input.withUniqueIDs(), input)
    }

    /// The synthetic suffix must not collide with an id that really exists.
    func testSyntheticIdSteppedOverAnExistingCollision() {
        let input = [
            album("A", "x", uri: "u"),
            album("B", "y", uri: "u#2"),
            album("C", "z", uri: "u"),
        ]
        let out = input.withUniqueIDs()
        XCTAssertEqual(Set(out.map(\.id)).count, 3, "got \(out.map(\.id))")
        XCTAssertEqual(out[1].id, "u#2", "an album that owns its id keeps it")
        XCTAssertNotEqual(out[2].id, "u#2", "the synthetic id stole an id that was taken")
    }

    /// Artists and tracks are identified the same defensive way and get the
    /// same guarantee — a track id falls back to a uri, and a multi-disc album
    /// can repeat one.
    func testArtistsAndTracksAreUniquifiedToo() {
        let artists = [LibraryArtist(id: "a", name: "A"), LibraryArtist(id: "a", name: "A (2)")]
        XCTAssertEqual(Set(artists.withUniqueIDs().map(\.id)).count, 2)

        let t = { (n: String) in
            Track(id: "same", title: n, artist: "", album: "", uri: "same",
                  trackNumber: 0, duration: 0, albumArt: "", source: "")
        }
        XCTAssertEqual(Set([t("one"), t("two"), t("three")].withUniqueIDs().map(\.id)).count, 3)
    }

    func testEmptyListIsHandled() {
        XCTAssertTrue([LibraryAlbum]().withUniqueIDs().isEmpty)
    }
}

/// The parse boundary is where the repair is applied, so pin it there too — a
/// future refactor that adds another list must pass through the same door.
final class LibraryEnvelopeIdentityTests: XCTestCase {

    func testPushLibraryAlbumsUniquifiesTheLiveDuplicateUri() {
        let uri = "USB/To Awaken the Sleeper- Works of Joel Thompson"
        let rows: [[String: Any]] = (1...5).map {
            ["title": "To Awaken the Sleeper: Works of Joel Thompson",
             "artist": "Performer \($0)", "uri": uri, "albumart": ""]
        }
        let env = PushLibraryAlbums(rawDict: ["albums": rows, "total": 5])
        XCTAssertEqual(env?.albums.count, 5, "no row may be dropped")
        XCTAssertEqual(Set(env?.albums.map(\.id) ?? []).count, 5,
                       "the grid will punch holes: \(env?.albums.map(\.id) ?? [])")
        XCTAssertEqual(Set(env?.albums.map(\.uri) ?? []).count, 1,
                       "every row still plays the same folder — uri is not identity")
    }

    func testPushLibraryArtistAlbumsUniquifies() {
        let rows: [[String: Any]] = (1...3).map {
            ["title": "T", "artist": "A\($0)", "uri": "u", "albumart": ""]
        }
        let env = PushLibraryArtistAlbums(rawDict: ["artist": "A", "albums": rows])
        XCTAssertEqual(Set(env?.albums.map(\.id) ?? []).count, 3)
    }

    func testPushLibraryArtistsUniquifies() {
        let rows: [[String: Any]] = [["name": "A"], ["name": "A"]]
        let env = PushLibraryArtists(rawDict: ["artists": rows])
        XCTAssertEqual(Set(env?.artists.map(\.id) ?? []).count, 2)
    }

    func testPushLibraryAlbumTracksUniquifies() {
        let rows: [[String: Any]] = (1...3).map {
            ["title": "Movement \($0)", "uri": "same.flac"]
        }
        let env = PushLibraryAlbumTracks(rawDict: ["album": "A", "tracks": rows])
        XCTAssertEqual(env?.tracks.count, 3)
        XCTAssertEqual(Set(env?.tracks.map(\.id) ?? []).count, 3)
    }
}
