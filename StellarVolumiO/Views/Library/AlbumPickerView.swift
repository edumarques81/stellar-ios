import SwiftUI

struct AlbumPickerView: View {
    @Environment(AlbumPickerStore.self) private var store
    @Environment(SocketService.self) private var socket

    var body: some View {
        Group {
            if store.loading && store.albums.isEmpty {
                ProgressView("Loading albums…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.mdOnSurfaceVariant)
            } else if store.albums.isEmpty {
                emptyState
            } else {
                albumList
            }
        }
        .onAppear {
            if store.albums.isEmpty { store.load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(.mdOnSurfaceVariant.opacity(0.6))
            Text("No albums yet")
                .font(StellarFont.titleMedium)
                .foregroundStyle(.mdOnSurfaceVariant)
            Button {
                store.load()
            } label: {
                Text("Reload")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.mdPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var albumList: some View {
        List(store.albums) { album in
            Button {
                store.play(album)
            } label: {
                AlbumRow(album: album, socket: socket)
            }
            .listRowBackground(Color.mdSurfaceContainerLow)
            .listRowSeparatorTint(.mdOutlineVariant.opacity(0.3))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.mdBackground)
        .refreshable { store.load() }
    }
}

// MARK: - Album row

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
