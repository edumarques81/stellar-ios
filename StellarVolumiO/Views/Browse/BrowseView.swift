import SwiftUI

// MARK: - Browse View (Phase 2)
// Placeholder — will implement full library browsing in Phase 2
// Supports: Local Music, NAS, Albums, Artists, Playlists, Web Radio, Qobuz

struct BrowseView: View {
    @Environment(SocketService.self) private var socket
    @Environment(ThemeStore.self) private var themeStore

    // Computed so `.mdPrimary` re-resolves on theme change
    var sources: [(title: String, subtitle: String, icon: String, uri: String, color: Color)] {[
        ("My Music",  "Local & Network",     "music.house.fill",                          "music-library", .orange),
        ("Albums",    "All albums",           "square.stack.fill",                         "albums",        .mdPrimary),
        ("Playlists", "Saved playlists",      "music.note.list",                           "playlists",     Color(hex: "#4A90D9")),
        ("Web Radio", "Internet stations",    "antenna.radiowaves.left.and.right",         "webradio",      Color(hex: "#E86A8A")),
        ("Qobuz",     "Hi-Res streaming",     "waveform",                                  "qobuz",         Color(hex: "#7B5EA7")),
    ]}

    var body: some View {
        let _ = themeStore.theme
        NavigationStack {
            ZStack {
                Color.mdBackground.ignoresSafeArea()

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(sources, id: \.title) { source in
                        SourceTile(
                            title: source.title,
                            subtitle: source.subtitle,
                            icon: source.icon,
                            color: source.color
                        ) {
                            // TODO Phase 2: navigate into source
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.mdSurfaceContainer, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct SourceTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: .mdShapeLarge)
                        .fill(color.opacity(0.2))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 26))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(StellarFont.titleSmall)
                        .foregroundStyle(.mdOnSurface)
                    Text(subtitle)
                        .font(StellarFont.labelSmall)
                        .foregroundStyle(.mdOnSurfaceVariant)
                }

                Spacer()
            }
            .padding(16)
            .frame(height: 140)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.mdSurfaceContainerHigh, in: RoundedRectangle(cornerRadius: .mdShapeLarge))
        }
        .buttonStyle(StellarTilePressStyle())
    }
}
