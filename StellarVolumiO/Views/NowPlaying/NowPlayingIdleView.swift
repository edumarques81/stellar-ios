import SwiftUI

struct NowPlayingIdleView: View {
    let album: LastPlayedAlbum

    @Environment(LastPlayedStore.self) private var lastPlayed
    @Environment(PlayerStore.self) private var player
    @Environment(SocketService.self) private var socket

    var body: some View {
        VStack(spacing: 0) {
            Text("Last Played")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            AlbumArtHero(url: artworkURL)
                .padding(.top, 8)
                .padding(.horizontal, 24)

            VStack(spacing: 4) {
                Text(album.album.isEmpty ? "—" : album.album)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(2)
                Text(album.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 18)

            FormatBadgeStrip(
                trackType: album.trackType,
                samplerate: album.sampleRate,
                bitdepth: album.bitDepth
            )
            .padding(.top, 10)

            Button {
                player.applyOptimistic(.play)
                lastPlayed.resume()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Resume")
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Stellar.Color.gold, in: Capsule())
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
        }
    }

    private var artworkURL: URL? {
        let s = album.albumArt
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        let path = s.hasPrefix("/") ? s : "/\(s)"
        return URL(string: "http://\(socket.serverHost):\(socket.serverPort)\(path)")
    }
}

private struct AlbumArtHero: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: { placeholder }
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
