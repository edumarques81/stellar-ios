import XCTest
@testable import StellarVolumiO

@MainActor
final class AlbumLibraryFingerprintTests: XCTestCase {

    private func album(uri: String, title: String = "T", artist: String = "A") -> LibraryAlbum {
        LibraryAlbum(id: uri.isEmpty ? "\(artist)|\(title)" : uri,
                     title: title,
                     artist: artist,
                     uri: uri,
                     albumart: "/albumart?path=\(uri)")
    }

    func testEmptyListHasStableFingerprint() {
        let a = AlbumPickerStore.computeFingerprint([])
        let b = AlbumPickerStore.computeFingerprint([])
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.isEmpty, "fingerprint should still be a real SHA256 digest, even for the empty input")
    }

    func testEqualListsHaveEqualFingerprints() {
        let list1 = [album(uri: "u1"), album(uri: "u2"), album(uri: "u3")]
        let list2 = [album(uri: "u1"), album(uri: "u2"), album(uri: "u3")]
        XCTAssertEqual(AlbumPickerStore.computeFingerprint(list1),
                       AlbumPickerStore.computeFingerprint(list2))
    }

    func testReorderingProducesSameFingerprint() {
        // Order-independence is the whole point of sorting before hashing.
        let original = [album(uri: "u1"), album(uri: "u2"), album(uri: "u3")]
        let shuffled = [album(uri: "u3"), album(uri: "u1"), album(uri: "u2")]
        XCTAssertEqual(AlbumPickerStore.computeFingerprint(original),
                       AlbumPickerStore.computeFingerprint(shuffled))
    }

    func testAddingAnAlbumChangesFingerprint() {
        let before = [album(uri: "u1"), album(uri: "u2")]
        let after  = [album(uri: "u1"), album(uri: "u2"), album(uri: "u3")]
        XCTAssertNotEqual(AlbumPickerStore.computeFingerprint(before),
                          AlbumPickerStore.computeFingerprint(after))
    }

    func testRemovingAnAlbumChangesFingerprint() {
        let before = [album(uri: "u1"), album(uri: "u2"), album(uri: "u3")]
        let after  = [album(uri: "u1"), album(uri: "u3")]
        XCTAssertNotEqual(AlbumPickerStore.computeFingerprint(before),
                          AlbumPickerStore.computeFingerprint(after))
    }

    func testUriIsPreferredOverArtistTitle() {
        // Two rows with identical artist+title but different URIs must hash
        // to different fingerprints — otherwise duplicate-album-name libraries
        // (live recordings, deluxe editions) would silently merge.
        let withUri    = [album(uri: "u1", title: "Live", artist: "X")]
        let withOtherUri = [album(uri: "u2", title: "Live", artist: "X")]
        XCTAssertNotEqual(AlbumPickerStore.computeFingerprint(withUri),
                          AlbumPickerStore.computeFingerprint(withOtherUri))
    }

    func testUriEmptyFallsBackToArtistTitle() {
        // Derived-from-tracks rows have no URI; identity is artist|title.
        let a = [album(uri: "", title: "T1", artist: "A")]
        let b = [album(uri: "", title: "T1", artist: "A")]
        let c = [album(uri: "", title: "T2", artist: "A")]
        XCTAssertEqual(AlbumPickerStore.computeFingerprint(a),
                       AlbumPickerStore.computeFingerprint(b))
        XCTAssertNotEqual(AlbumPickerStore.computeFingerprint(a),
                          AlbumPickerStore.computeFingerprint(c))
    }
}
