import SwiftUI

struct ArtistPickerView: View {
    @Environment(ArtistPickerStore.self) private var store
    @Environment(SocketService.self) private var socket

    var body: some View {
        List {
            ForEach(store.artists) { artist in
                NavigationLink(value: artist) {
                    HStack(spacing: 12) {
                        artistAvatar(for: artist)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(artist.name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            if let n = artist.albumCount, n > 0 {
                                Text("\(n) album\(n == 1 ? "" : "s")")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.mdSurfaceContainerLow)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationDestination(for: LibraryArtist.self) { artist in
            ArtistDetailView(artist: artist)
        }
        .onAppear {
            if store.artists.isEmpty && !store.loading { store.load() }
        }
    }

    @ViewBuilder
    private func artistAvatar(for artist: LibraryArtist) -> some View {
        AsyncImage(url: artistImageURL(for: artist)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.mdOnSurfaceVariant)
        }
        .frame(width: 56, height: 56)
        .background(Color.mdSurfaceContainerHigh, in: Circle())
        .clipShape(Circle())
    }

    private func artistImageURL(for artist: LibraryArtist) -> URL? {
        guard !artist.name.isEmpty,
              let encoded = artist.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "http://\(socket.serverHost):\(socket.serverPort)/artistart?name=\(encoded)")
    }
}
