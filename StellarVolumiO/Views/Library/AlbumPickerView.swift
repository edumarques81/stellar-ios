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
                    // Push the new Album Tracks screen; the outer
                    // LibraryView NavigationStack declares the destination.
                    NavigationLink(value: album) {
                        AlbumTile(album: album)
                    }
                    .buttonStyle(.plain)
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
                    } placeholder: {
                        EmptyView()
                    }
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

            Text(album.artist)
                .font(.system(size: 10))
                .lineLimit(1)
                .foregroundStyle(.secondary)
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

// MARK: - Duplicate disambiguation badge (BROWSE-02/BROWSE-03)
//
// Shared by both AlbumPickerView's and ArtistDetailView's near-duplicate
// `AlbumTile` structs (see 03-08a-PLAN.md — the two grids are deliberately
// not deduplicated, only the badge chip is factored out to avoid drifting
// styles between them). Renders arbitrary-length text (e.g. a quality
// string like "352.8kHz/24bit FLAC", or "Disc 2", or a source name) as a
// small overlay chip on the artwork square — never renders when `text` is
// empty, so the 61/66 unique albums in the live library show nothing.
struct AlbumDuplicateBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(Stellar.Color.gold)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Stellar.Color.goldFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Stellar.Color.gold.opacity(0.5), lineWidth: 0.75))
    }
}
