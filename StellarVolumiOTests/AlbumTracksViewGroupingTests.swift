import XCTest
@testable import StellarVolumiO

/// Coverage for `TrackList.groupTracksByDisc(_:)` — the pure grouping
/// algorithm behind BROWSE-07's multi-disc "Disc N" section headers on the
/// Album Tracks screen. Extracted as a static function specifically so it's
/// testable without rendering SwiftUI (this project's `swift test` can't
/// exercise @Observable + UIKit-backed views — see AlbumPickerStore's
/// `computeFingerprint` for the established precedent).
final class AlbumTracksViewGroupingTests: XCTestCase {

    private func track(_ title: String, disc: Int) -> Track {
        Track(id: title, title: title, artist: "Gustav Mahler", album: "Symphony No. 2",
              uri: "NAS/Mahler/\(title).flac", trackNumber: 1, duration: 300,
              albumArt: "", source: "mpd", disc: disc)
    }

    func testGroupsConsecutiveSameDiscTracks() {
        let tracks = [
            track("D1T1", disc: 1),
            track("D1T2", disc: 1),
            track("D2T1", disc: 2),
            track("D2T2", disc: 2),
        ]

        let groups = TrackList.groupTracksByDisc(tracks)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].disc, 1)
        XCTAssertEqual(groups[0].tracks.map(\.title), ["D1T1", "D1T2"])
        XCTAssertEqual(groups[1].disc, 2)
        XCTAssertEqual(groups[1].tracks.map(\.title), ["D2T1", "D2T2"])
    }

    func testSingleDiscTrackListProducesExactlyOneGroup() {
        // Mirrors the 61/66-album default case: discCount absent/<=1. The
        // view's body only takes the grouped branch when discGroups.count>1,
        // so this single-group result is what triggers the flat-list fallback.
        let tracks = [track("A", disc: 0), track("B", disc: 0), track("C", disc: 0)]

        let groups = TrackList.groupTracksByDisc(tracks)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].disc, 0)
        XCTAssertEqual(groups[0].tracks.count, 3)
    }

    func testEmptyTrackListProducesNoGroups() {
        XCTAssertEqual(TrackList.groupTracksByDisc([]).count, 0)
    }

    func testPreservesPreSortedOrderWithinEachDiscGroup() {
        // Tracks arrive pre-sorted by (disc, trackNumber, title) per the
        // locked contract — grouping must never re-sort.
        let tracks = [
            track("Zebra", disc: 1),
            track("Apple", disc: 1),
            track("Mango", disc: 2),
        ]

        let groups = TrackList.groupTracksByDisc(tracks)

        XCTAssertEqual(groups[0].tracks.map(\.title), ["Zebra", "Apple"],
                       "grouping must preserve arrival order, not alphabetize")
    }

    func testElevenDiscBoxSetGroupsCorrectly() {
        // Pins the real 66-album-library case named in the plan: Mahler
        // discCount=11.
        var tracks: [Track] = []
        for disc in 1...11 {
            tracks.append(track("Disc\(disc)Track", disc: disc))
        }

        let groups = TrackList.groupTracksByDisc(tracks)

        XCTAssertEqual(groups.count, 11)
        XCTAssertEqual(groups.map(\.disc), Array(1...11))
    }
}
