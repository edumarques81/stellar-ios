import SwiftUI

struct ArtistDetailView: View {
    let artist: LibraryArtist

    @Environment(ArtistPickerStore.self) private var store
    @Environment(SocketService.self) private var socket
    @Environment(PlayerStore.self) private var player

    // Mirrors AlbumTracksView's debounce guard on its track-row taps — this
    // screen's loose-track fallback (ARTIST-04/BROWSE-04) is the same kind
    // of tap-to-play surface, so it gets the same protection.
    @State private var debouncer = TapDebouncer(interval: 0.5)

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    var body: some View {
        Group {
            if !store.artistAlbums.isEmpty {
                albumGrid
            } else if !store.artistLooseTracks.isEmpty {
                // ARTIST-04/BROWSE-04: this artist resolves to zero proper
                // albums but has playable tracks. Reuse AlbumTracksView's
                // TrackList/TrackRow (made non-private in that file) rather
                // than duplicating row styling; discCount: 0 keeps it flat —
                // loose tracks have no disc grouping.
                ScrollView {
                    TrackList(tracks: store.artistLooseTracks,
                              loading: store.loadingArtistAlbums,
                              errorMessage: nil,
                              discCount: 0) { track in
                        playLooseTrack(track)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            } else if store.loadingArtistAlbums {
                ScrollView {
                    ProgressView()
                        .tint(Stellar.Color.gold)
                        .padding(.vertical, 32)
                }
                .scrollIndicators(.hidden)
            } else {
                // True zero-content case — not expected against the live
                // library (every artist has at least one album or loose
                // track), but must render a real message rather than a
                // blank screen if it ever occurs.
                VStack {
                    Spacer()
                    Text("No albums")
                        .font(StellarFont.bodyMedium)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .background(StellarGlassyBackground())
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if store.selectedArtist != artist { store.select(artist) }
        }
    }

    private var albumGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.artistAlbums) { album in
                    // Push the new Album Tracks screen; the destination is
                    // declared on the outer LibraryView NavigationStack so
                    // the same routing works from both Albums and Artists.
                    NavigationLink(value: album) {
                        AlbumTile(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("artist-album-grid")
    }

    // Same replaceAndPlay shape as AlbumTracksView.playTrack — a per-track
    // tap IS the playable interaction for loose tracks; no new "Play All"
    // affordance per this plan's iOS-vs-LCD scope note (workspace CLAUDE.md
    // six-feature boundary).
    private func playLooseTrack(_ track: Track) {
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

private struct AlbumTile: View {
    let album: LibraryAlbum

    @Environment(SocketService.self) private var socket

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [SwiftUI.Color(red: 0x2a/255, green: 0x35/255, blue: 0x48/255),
                                 SwiftUI.Color(red: 0x1a/255, green: 0x1f/255, blue: 0x2e/255)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                if let url = artworkURL {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { EmptyView() }
                }
                if let badge = album.badge, !badge.isEmpty {
                    AlbumDuplicateBadge(text: badge)
                        .padding(6)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(album.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
    }

    private var artworkURL: URL? {
        let s = album.albumart
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        let path = s.hasPrefix("/") ? s : "/\(s)"
        return URL(string: "http://\(socket.serverHost):\(socket.serverPort)\(path)")
    }
}
