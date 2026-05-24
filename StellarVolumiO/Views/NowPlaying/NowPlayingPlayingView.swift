import SwiftUI

struct NowPlayingPlayingView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(SocketService.self) private var socket

    var body: some View {
        VStack(spacing: 0) {
            AlbumArtHero(url: artworkURL)
                .padding(.top, 8)
                .padding(.horizontal, 24)

            VStack(spacing: 4) {
                Text(player.state.title.isEmpty ? "—" : player.state.title)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(2)
                Text(player.state.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(player.state.album)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            FormatBadgeStrip(
                trackType: player.state.trackType,
                samplerate: player.state.samplerate,
                bitdepth: player.state.bitdepth
            )
            .padding(.top, 10)

            SeekBar(
                currentSeconds: player.state.seekSeconds,
                totalSeconds: player.state.durationSeconds,
                onSeek: { socket.seek(to: $0) }
            )
            .padding(.top, 18)
            .padding(.horizontal, 24)

            HStack(spacing: 28) {
                TransportIconButton(icon: "backward.fill") { socket.prev() }

                PlayPauseButton(isPlaying: player.isPlaying) {
                    player.applyOptimistic(player.isPlaying ? .pause : .play)
                    socket.playPause()
                }

                TransportIconButton(icon: "forward.fill") { socket.next() }
            }
            .padding(.top, 22)
        }
    }

    private var artworkURL: URL? {
        let s = player.state.albumart
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        let path = s.hasPrefix("/") ? s : "/\(s)"
        return URL(string: "http://\(socket.serverHost):\(socket.serverPort)\(path)")
    }
}

// MARK: - Subcomponents (kept private to this view for now)

private struct AlbumArtHero: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Stellar.Metric.artCornerRadius))
        .shadow(color: .black.opacity(Stellar.Shadow.albumArt.opacity),
                radius: Stellar.Shadow.albumArt.radius,
                y: Stellar.Shadow.albumArt.y)
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

private struct TransportIconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: Stellar.Metric.minTouchTarget,
                       height: Stellar.Metric.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
