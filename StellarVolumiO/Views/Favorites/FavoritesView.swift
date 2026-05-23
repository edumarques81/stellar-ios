import SwiftUI

struct FavoritesView: View {
    @Environment(SocketService.self) private var socket
    @Environment(ThemeStore.self)    private var themeStore
    @State private var store = FavoritesStore()

    var body: some View {
        let _ = themeStore.theme

        NavigationStack {
            ZStack {
                Color.mdBackground.ignoresSafeArea()
                content
            }
            .navigationTitle("Favourites")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.mdSurfaceContainer, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if !store.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            store.playAll(using: socket)
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                        }
                        .tint(.mdPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.fetch(using: socket)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(.mdOnSurfaceVariant)
                }
            }
        }
        .onAppear {
            store.bind(to: socket)
            store.fetch(using: socket)
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            loadingSkeleton
        } else if let err = store.error {
            errorState(err)
        } else if store.items.isEmpty {
            emptyState
        } else {
            favoritesList
        }
    }

    // MARK: - List

    private var favoritesList: some View {
        List {
            ForEach(store.items) { item in
                FavoriteRow(item: item) {
                    store.play(item, using: socket)
                } onQueue: {
                    store.addToQueue(item, using: socket)
                } onRemove: {
                    withAnimation { store.removeFavorite(item, using: socket) }
                }
                .listRowBackground(Color.mdSurfaceContainer)
                .listRowSeparatorTint(.mdOutlineVariant)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.mdOnSurfaceVariant)
            Text("No favourites yet")
                .font(StellarFont.titleMedium)
                .foregroundStyle(.mdOnSurface)
            Text("Long-press any track and choose "Add to Favourites"")
                .font(StellarFont.bodyMedium)
                .foregroundStyle(.mdOnSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.mdError)
            Text(msg)
                .font(StellarFont.bodyMedium)
                .foregroundStyle(.mdOnSurfaceVariant)
            Button("Retry") { store.fetch(using: socket) }
                .buttonStyle(.borderedProminent)
                .tint(.mdPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.mdSurfaceContainerHigh)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.mdSurfaceContainerHigh)
                            .frame(width: 180, height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.mdSurfaceContainerHigh)
                            .frame(width: 110, height: 11)
                    }
                }
                .listRowBackground(Color.mdSurfaceContainer)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .redacted(reason: .placeholder)
        .shimmering()
    }
}

// MARK: - Favorite Row

private struct FavoriteRow: View {
    let item: BrowseItem
    let onPlay: () -> Void
    let onQueue: () -> Void
    let onRemove: () -> Void

    @State private var showActions = false

    var body: some View {
        HStack(spacing: 14) {
            // Album art
            AlbumArtThumbnail(url: item.albumart)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(StellarFont.bodyLarge)
                    .foregroundStyle(.mdOnSurface)
                    .lineLimit(1)

                if let artist = item.artist {
                    Text([artist, item.album].compactMap { $0 }.joined(separator: " · "))
                        .font(StellarFont.bodySmall)
                        .foregroundStyle(.mdOnSurfaceVariant)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 4) {
                IconButton(systemName: "text.badge.plus", tint: .mdOnSurfaceVariant, action: onQueue)
                IconButton(systemName: "play.fill", tint: .mdPrimary, action: onPlay)
                IconButton(systemName: "heart.fill", tint: .mdPrimary, action: onRemove)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
    }
}

// MARK: - Album Art Thumbnail

private struct AlbumArtThumbnail: View {
    let url: String?

    var body: some View {
        Group {
            if let urlStr = url, let u = URL(string: urlStr) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        ZStack {
            Color.mdSurfaceContainerHigh
            Image(systemName: "music.note")
                .foregroundStyle(.mdOnSurfaceVariant)
        }
    }
}

// MARK: - Icon Button

private struct IconButton: View {
    let systemName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(StellarIconPressStyle())
    }
}

// MARK: - Shimmering modifier (simple opacity pulse)

private struct ShimmeringModifier: ViewModifier {
    @State private var opacity: Double = 0.4
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: opacity)
            .onAppear { opacity = 0.9 }
    }
}

private extension View {
    func shimmering() -> some View { modifier(ShimmeringModifier()) }
}
