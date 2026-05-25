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
                              errorMessage: store.errorMessage) { track in
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

    var body: some View {
        Group {
            if let url = artworkURL {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 240, height: 240)
        .clipShape(RoundedRectangle(cornerRadius: Stellar.Metric.artCornerRadius))
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

    private var placeholder: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [SwiftUI.Color(red: 0x2a/255, green: 0x35/255, blue: 0x48/255),
                         SwiftUI.Color(red: 0x1a/255, green: 0x1f/255, blue: 0x2e/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
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

private struct TrackList: View {
    let tracks: [Track]
    let loading: Bool
    let errorMessage: String?
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
}

private struct TrackRow: View {
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
