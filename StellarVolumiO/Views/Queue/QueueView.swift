import SwiftUI

struct QueueView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(SocketService.self) private var socket
    @Environment(ThemeStore.self) private var themeStore

    var body: some View {
        let _ = themeStore.theme
        NavigationStack {
            ZStack {
                Color.mdBackground.ignoresSafeArea()

                if player.queue.isEmpty {
                    ContentUnavailableView(
                        "Queue is empty",
                        systemImage: "list.bullet",
                        description: Text("Add tracks from your library to start a queue")
                    )
                    .foregroundStyle(.mdOnSurface)
                } else {
                    List(player.queue) { item in
                        QueueItemRow(item: item, isActive: item.id == player.currentQueueIndex)
                            .listRowBackground(Color.mdSurfaceContainerLow)
                            .listRowSeparatorTint(.mdOutlineVariant)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.mdSurfaceContainer, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct QueueItemRow: View {
    let item: QueueItem
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Album art
            AsyncImage(url: item.albumart.flatMap(URL.init)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.mdSurfaceContainerHigh
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: .mdShapeSmall))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(StellarFont.titleSmall)
                    .foregroundStyle(isActive ? .mdPrimary : .mdOnSurface)
                    .lineLimit(1)
                if let artist = item.artist {
                    Text(artist)
                        .font(StellarFont.bodySmall)
                        .foregroundStyle(.mdOnSurfaceVariant)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(item.displayDuration)
                .font(StellarFont.labelMedium)
                .foregroundStyle(.mdOnSurfaceVariant)
        }
        .padding(.vertical, 4)
    }
}
