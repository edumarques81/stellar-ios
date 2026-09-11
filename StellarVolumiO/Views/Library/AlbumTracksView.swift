import SwiftUI

/// The Album Tracks screen. Reached by tapping an album tile from the
/// Albums grid or from an artist's album list. Shows:
///   - Big square cover at the top.
///   - Album title + artist below.
///   - Full-width gold "Play Album" CTA.
///   - List of tracks; tap any row to play that one track.
struct AlbumTracksView: View {
    let album: LibraryAlbum

    @Environment(AlbumTracksStore.self) private var store
    @Environment(SocketService.self) private var socket
    @Environment(PlayerStore.self) private var player

    // Defensive debounce across BOTH tap surfaces on this screen (Play Album
    // CTA + per-track rows). Drops any second tap that lands inside the 500 ms
    // window. The window is short enough to be imperceptible — silent reject
    // is correct; no spinner/disabled state. See TapDebouncer.swift for why
    // this isn't a DispatchQueue.asyncAfter trailing-edge timer.
    @State private var debouncer = TapDebouncer(interval: 0.5)

    var body: some View {
        ZStack {
            StellarGlassyBackground()

            ScrollView {
                VStack(spacing: 0) {
                    AlbumCoverHero(album: album, host: socket.serverHost, port: socket.serverPort)
                        .padding(.top, 12)
                        .padding(.horizontal, 24)

                    VStack(spacing: 4) {
                        Text(album.title.isEmpty ? "—" : album.title)
                            .accessibilityIdentifier("album-tracks-title")
                            .font(StellarFont.titleLarge)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .foregroundStyle(.white)
                        Text(album.artist)
                            .font(StellarFont.bodyMedium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    PlayAlbumButton {
                        playWholeAlbum()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                    TrackList(tracks: visibleTracks, loading: store.loading,
                              errorMessage: store.errorMessage,
                              discCount: album.discCount ?? 0) { track in
                        playTrack(track)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Re-fetch when the screen is entered for a new album, or if the
            // current cached list is empty / stale.
            if store.currentAlbum != album.title || store.tracks.isEmpty {
                store.load(album: album.title,
                           albumArtist: album.artist.isEmpty ? nil : album.artist,
                           uri: album.uri.isEmpty ? nil : album.uri)
            }
        }
    }

    // Defensive AppleDouble filter — Pi MPD sometimes returns `._*` ghost
    // files; the backend's `GetAlbumTracks` doesn't strip them today. Filter
    // location pinned here so a future server-side fix can drop this line.
    // See: reference_stellar_cache_rebuild_wipes_enrichment-adjacent notes.
    private var visibleTracks: [Track] {
        store.tracks.filter { !$0.uri.contains("/._") }
    }

    private func playWholeAlbum() {
        guard !album.uri.isEmpty else { return }
        guard debouncer.attempt(at: .now) else { return }
        player.applyOptimistic(.play)
        socket.emitObject("replaceAndPlay", [
            "service": "mpd",
            "type":    "folder",
            "title":   album.title,
            "artist":  album.artist,
            "albumart": album.albumart,
            "uri":     album.uri
        ])
    }

    private func playTrack(_ track: Track) {
        guard !track.uri.isEmpty else { return }
        guard debouncer.attempt(at: .now) else { return }
        player.applyOptimistic(.play)
        socket.emitObject("replaceAndPlay", [
            "service": "mpd",
            "type":    "song",
            "title":   track.title,
            "artist":  track.artist,
            "albumart": track.albumArt,
            "uri":     track.uri
        ])
    }
}

// MARK: - Cover hero

private struct AlbumCoverHero: View {
    let album: LibraryAlbum
    let host: String
    let port: Int

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.stellarIdiom) private var idiom

    /// `heroSideCompact` is the size the iPhone shipped with and the size a
    /// Slide Over pane still needs. A roomy canvas gets a larger cover; it is a
    /// step rather than a ratio because the surrounding track list is a
    /// fixed-width reading column, not a grid, so there is nothing for a
    /// continuous scale to stay in proportion with.
    ///
    /// It is a *ceiling*, applied with `maxWidth` plus a 1:1 aspect ratio
    /// rather than a fixed `width`. The step assumes the detail column is at
    /// least as wide as the step, and that assumption does not hold: the
    /// regular threshold is around 590 pt of window, and the sidebar takes
    /// ~320 pt of it, so a narrow Stage Manager window can leave under 280 pt
    /// of detail. A fixed frame would clip there; a ceiling shrinks.
    private var side: CGFloat {
        RootLayoutMode.isRoomy(horizontalSizeClass: horizontalSizeClass, idiom: idiom)
            ? Stellar.Metric.heroSideRegular
            : Stellar.Metric.heroSideCompact
    }

    var body: some View {
        // `side` is a ceiling on the width; the square follows from it. The
        // artwork itself is an overlay inside `AlbumArtworkSquare` precisely so
        // a non-square cover cannot push the hero past that ceiling.
        AlbumArtworkSquare(cornerRadius: Stellar.Metric.artCornerRadius) {
            AlbumArtworkImage(url: artworkURL)
        }
        .frame(maxWidth: side)
        .shadow(color: .black.opacity(Stellar.Shadow.albumArt.opacity),
                radius: Stellar.Shadow.albumArt.radius,
                y: Stellar.Shadow.albumArt.y)
        .frame(maxWidth: .infinity)
    }

    private var artworkURL: URL? {
        let s = album.albumart
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        let path = s.hasPrefix("/") ? s : "/\(s)"
        return URL(string: "http://\(host):\(port)\(path)")
    }
}

// MARK: - Play Album CTA

private struct PlayAlbumButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text("Play Album")
                    .fontWeight(.bold)
            }
            .font(StellarFont.titleMedium)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Stellar.Metric.minTouchTarget)
            .padding(.vertical, 12)
            .background(Stellar.Color.gold, in: Capsule())
            .foregroundStyle(.black)
        }
        .buttonStyle(StellarPlayPressStyle())
    }
}

// MARK: - Track list

// Non-private: reused by ArtistDetailView's loose-track fallback (ARTIST-04/
// BROWSE-04), which has no album/discCount context of its own — that call
// site always passes discCount: 0 for the flat, non-grouped rendering.
struct TrackList: View {
    let tracks: [Track]
    let loading: Bool
    let errorMessage: String?
    /// BROWSE-07: >1 groups `tracks` into "Disc N" sections. Tracks arrive
    /// pre-sorted by (disc, trackNumber, title) from the backend — grouping
    /// here only collects consecutive same-disc runs, it never re-sorts.
    var discCount: Int = 0
    let onTap: (Track) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                Text(errorMessage)
                    .font(StellarFont.bodyMedium)
                    .foregroundStyle(Stellar.Color.statusRed)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
            } else if tracks.isEmpty && loading {
                ProgressView()
                    .tint(Stellar.Color.gold)
                    .padding(.vertical, 32)
            } else if tracks.isEmpty {
                Text("No tracks")
                    .font(StellarFont.bodyMedium)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            } else if discCount > 1 && discGroups.count > 1 {
                ForEach(discGroups, id: \.disc) { group in
                    DiscHeader(disc: group.disc)
                    ForEach(group.tracks) { track in
                        TrackRow(track: track) { onTap(track) }
                        Divider()
                            .overlay(Stellar.Color.separator)
                            .padding(.leading, 24)
                    }
                }
            } else {
                ForEach(tracks) { track in
                    TrackRow(track: track) { onTap(track) }
                    Divider()
                        .overlay(Stellar.Color.separator)
                        .padding(.leading, 24)
                }
            }
        }
    }

    private var discGroups: [(disc: Int, tracks: [Track])] {
        Self.groupTracksByDisc(tracks)
    }

    /// Groups consecutive same-`disc` tracks in arrival order (already
    /// pre-sorted by the backend). The body's `.count > 1` check guards the
    /// case where `discCount` claims multi-disc but every track actually
    /// carries the same (or absent/0) disc value — falls back to the flat
    /// list rather than rendering a single spurious "Disc 0"/"Disc 1" header.
    ///
    /// `static` + `internal` (not `private`) so unit tests can exercise the
    /// pure grouping algorithm directly, per this project's SwiftUI-view
    /// testability convention (mirrors `AlbumPickerStore.computeFingerprint`)
    /// — `swift test` can't render views (@Observable + UIKit-backed SwiftUI).
    static func groupTracksByDisc(_ tracks: [Track]) -> [(disc: Int, tracks: [Track])] {
        var groups: [(disc: Int, tracks: [Track])] = []
        for track in tracks {
            if let last = groups.last, last.disc == track.disc {
                groups[groups.count - 1].tracks.append(track)
            } else {
                groups.append((disc: track.disc, tracks: [track]))
            }
        }
        return groups
    }
}

struct DiscHeader: View {
    let disc: Int

    var body: some View {
        Text(disc > 0 ? "Disc \(disc)" : "Disc")
            .font(StellarFont.labelLarge)
            .foregroundStyle(Stellar.Color.gold)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TrackRow: View {
    let track: Track
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(trackIndex)
                    .font(StellarFont.labelMedium)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)

                Text(track.title.isEmpty ? "—" : track.title)
                    .font(StellarFont.bodyLarge)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(formattedDuration)
                    .font(StellarFont.labelMedium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 24)
            .frame(minHeight: Stellar.Metric.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var trackIndex: String {
        track.trackNumber > 0 ? "\(track.trackNumber)" : "—"
    }

    private var formattedDuration: String {
        guard track.duration > 0 else { return "" }
        let m = track.duration / 60
        let s = track.duration % 60
        return String(format: "%d:%02d", m, s)
    }
}
