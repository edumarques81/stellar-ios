import SwiftUI

struct ArtistDetailView: View {
    let artist: LibraryArtist

    @Environment(ArtistPickerStore.self) private var store
    @Environment(SocketService.self) private var socket

    var body: some View {
        Group {
            if store.loadingArtistAlbums {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.mdOnSurfaceVariant)
            } else if store.artistAlbums.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 36))
                        .foregroundStyle(.mdOnSurfaceVariant.opacity(0.6))
                    Text("No albums for \(artist.name)")
                        .font(StellarFont.bodyMedium)
                        .foregroundStyle(.mdOnSurfaceVariant)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.artistAlbums) { album in
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
            }
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.mdBackground.ignoresSafeArea())
    }
}
