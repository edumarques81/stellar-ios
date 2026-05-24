import SwiftUI

struct AlbumPickerView: View {
    @Environment(AlbumPickerStore.self) private var store
    @Environment(SocketService.self) private var socket

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.albums) { album in
                    AlbumTile(album: album) { store.play(album) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if store.albums.isEmpty && !store.loading { store.load() }
        }
    }
}

private struct AlbumTile: View {
    let album: LibraryAlbum
    let onTap: () -> Void

    @Environment(SocketService.self) private var socket

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [SwiftUI.Color(red: 0x2a/255, green: 0x35/255, blue: 0x48/255),
                                     SwiftUI.Color(red: 0x1a/255, green: 0x1f/255, blue: 0x2e/255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    if let url = artworkURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            EmptyView()
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(album.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(album.artist)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var artworkURL: URL? {
        let s = album.albumart
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        let path = s.hasPrefix("/") ? s : "/\(s)"
        return URL(string: "http://\(socket.serverHost):\(socket.serverPort)\(path)")
    }
}

// MARK: - Album row
// Preserved for ArtistDetailView (Task 4.1 still uses AlbumRow; Task 4.5 will
// migrate that callsite to its own tile and orphan this).

struct AlbumRow: View {
    let album: LibraryAlbum
    let socket: SocketService

    var body: some View {
        HStack(spacing: 12) {
            artworkThumb
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: .mdShapeSmall))

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(StellarFont.titleSmall)
                    .foregroundStyle(.mdOnSurface)
                    .lineLimit(1)
                Text(album.artist)
                    .font(StellarFont.bodySmall)
                    .foregroundStyle(.mdOnSurfaceVariant)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.mdPrimary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var artworkThumb: some View {
        if let url = artworkURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.mdSurfaceContainerHigh
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.mdOnSurfaceVariant)
                        )
                }
            }
        } else {
            Color.mdSurfaceContainerHigh
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundStyle(.mdOnSurfaceVariant)
                )
        }
    }

    /// Resolve a relative `albumart` field (`/albumart?path=...`) against the
    /// backend host. Absolute URLs pass through unchanged.
    private var artworkURL: URL? {
        guard !album.albumart.isEmpty else { return nil }
        if album.albumart.hasPrefix("http") {
            return URL(string: album.albumart)
        }
        let path = album.albumart.hasPrefix("/") ? album.albumart : "/\(album.albumart)"
        return URL(string: "http://\(socket.serverHost):\(socket.serverPort)\(path)")
    }
}
