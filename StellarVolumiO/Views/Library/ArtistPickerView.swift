import SwiftUI

struct ArtistPickerView: View {
    @Environment(ArtistPickerStore.self) private var store
    @Environment(SocketService.self) private var socket

    var body: some View {
        Group {
            if store.loading && store.artists.isEmpty {
                ProgressView("Loading artists…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.mdOnSurfaceVariant)
            } else if store.artists.isEmpty {
                emptyState
            } else {
                artistList
            }
        }
        .onAppear {
            if store.artists.isEmpty { store.load() }
        }
        .navigationDestination(item: Binding(
            get: { store.selectedArtist },
            set: { newValue in if newValue == nil { store.clearSelection() } }
        )) { artist in
            ArtistAlbumsView(artist: artist)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 40))
                .foregroundStyle(.mdOnSurfaceVariant.opacity(0.6))
            Text("No artists yet")
                .font(StellarFont.titleMedium)
                .foregroundStyle(.mdOnSurfaceVariant)
            Button { store.load() } label: {
                Text("Reload")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.mdPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var artistList: some View {
        List(store.artists) { artist in
            Button { store.select(artist) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.mdOnSurfaceVariant)
                        .frame(width: 56, height: 56)
                        .background(Color.mdSurfaceContainerHigh, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(artist.name)
                            .font(StellarFont.titleSmall)
                            .foregroundStyle(.mdOnSurface)
                            .lineLimit(1)
                        if let count = artist.albumCount, count > 0 {
                            Text("\(count) album\(count == 1 ? "" : "s")")
                                .font(StellarFont.bodySmall)
                                .foregroundStyle(.mdOnSurfaceVariant)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.mdOnSurfaceVariant)
                }
                .padding(.vertical, 4)
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

// MARK: - Drill-down: albums for selected artist

struct ArtistAlbumsView: View {
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
