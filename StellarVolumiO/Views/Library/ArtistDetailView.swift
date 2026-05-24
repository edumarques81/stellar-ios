import SwiftUI

struct ArtistDetailView: View {
    let artist: LibraryArtist

    @Environment(ArtistPickerStore.self) private var store
    @Environment(SocketService.self) private var socket

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.artistAlbums) { album in
                    AlbumTile(album: album) { store.play(album) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .background(StellarGlassyBackground())
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if store.selectedArtist != artist { store.select(artist) }
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
                        } placeholder: { EmptyView() }
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
