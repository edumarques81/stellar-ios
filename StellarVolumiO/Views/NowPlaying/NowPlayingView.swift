import SwiftUI

struct NowPlayingView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(SocketService.self) private var socket
    @Environment(AudioEngineStore.self) private var audioEngine
    @Environment(ThemeStore.self) private var themeStore

    @State private var seekDragging = false
    @State private var seekDragValue: Double = 0

    var body: some View {
        let _ = themeStore.theme

        ZStack {
            // Background — blurred album art
            backgroundLayer

            // Content
            ScrollView {
                VStack(spacing: 0) {
                    // Album art — no topbar, starts clean at the top
                    albumArt
                        .padding(.top, 32)

                    // Track info
                    trackInfo
                        .padding(.top, 24)
                        .padding(.horizontal, 24)

                    // Format badges
                    formatBadges
                        .padding(.top, 12)

                    // Seek bar
                    seekBar
                        .padding(.top, 20)
                        .padding(.horizontal, 24)

                    // Controls card
                    controlsCard
                        .padding(.top, 20)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            // Ensure content never hides behind tab bar
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
        }
        .background(Color.mdBackground)
    }

    // MARK: - Background
    private var backgroundLayer: some View {
        ZStack {
            Color.mdBackground

            if let url = player.albumArtURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.mdSurfaceContainerLow
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: 60)
                .opacity(0.35)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Album Art
    private var albumArt: some View {
        Group {
            if audioEngine.isAudirvanaActive {
                audirvanaArt
            } else if let url = player.albumArtURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderArt
                }
            } else {
                placeholderArt
            }
        }
        .frame(width: 280, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: .mdShapeExtraLarge))
        .shadow(
            color: audioEngine.isAudirvanaActive
                ? Color(red: 0.42, green: 0.31, blue: 0.63).opacity(0.5)
                : .black.opacity(0.4),
            radius: audioEngine.isAudirvanaActive ? 32 : 24,
            y: 8
        )
    }

    /// Audirvana branded artwork — purple gradient + stylised "A"
    private var audirvanaArt: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.31, blue: 0.63),
                    Color(red: 0.24, green: 0.16, blue: 0.44)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Stylised "A" letterform
            AudirvanaLetterMark()
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(white: 0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 160, height: 160)
                .shadow(color: Color(red: 0.42, green: 0.31, blue: 0.63).opacity(0.8), radius: 20)
        }
    }

    /// When nothing is playing — Stellar app logo (Italian Greyhound, tribute to Talco 🤍)
    private var placeholderArt: some View {
        StellarLogoView()
    }

    // MARK: - Track Info
    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            if player.hasTrack {
                Text(player.state.title)
                    .font(StellarFont.titleLarge)
                    .foregroundStyle(.mdOnSurface)
                    .lineLimit(2)

                Text(player.state.artist)
                    .font(StellarFont.bodyLarge)
                    .foregroundStyle(.mdOnSurfaceVariant)
                    .lineLimit(1)

                if !player.state.album.isEmpty {
                    Text(player.state.album)
                        .font(StellarFont.bodyMedium)
                        .foregroundStyle(.mdOnSurfaceVariant.opacity(0.7))
                        .lineLimit(1)
                }
            } else {
                Text(audioEngine.isAudirvanaActive ? "Audirvana Active" : "Not playing")
                    .font(StellarFont.titleLarge)
                    .foregroundStyle(.mdOnSurfaceVariant)
                Text(audioEngine.isAudirvanaActive ? "No track info available" : "Start playback from your library")
                    .font(StellarFont.bodyMedium)
                    .foregroundStyle(.mdOnSurfaceVariant.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Format Badges
    private var formatBadges: some View {
        HStack(spacing: 8) {
            ForEach(player.currentTrackFormatBadges, id: \.self) { badge in
                Text(badge)
                    .font(StellarFont.labelSmall)
                    .foregroundStyle(.mdOnTertiaryContainer)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.mdTertiaryContainer, in: Capsule())
            }
        }
    }

    // MARK: - Seek Bar
    private var seekBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { seekDragging ? seekDragValue : player.state.seekSeconds },
                    set: { seekDragValue = $0 }
                ),
                in: 0...max(1, player.state.durationSeconds),
                onEditingChanged: { editing in
                    seekDragging = editing
                    if !editing {
                        socket.seek(to: Int(seekDragValue))
                    }
                }
            )
            .tint(.mdPrimary)

            HStack {
                Text(formatTime(seekDragging ? seekDragValue : player.state.seekSeconds))
                Spacer()
                Text(formatTime(player.state.durationSeconds))
            }
            .font(StellarFont.labelMedium)
            .foregroundStyle(.mdOnSurfaceVariant)
        }
    }

    // MARK: - Controls Card
    private var controlsCard: some View {
        VStack(spacing: 20) {
            // Secondary controls (shuffle / repeat)
            HStack {
                IconButton(
                    icon: player.state.shuffle ? "shuffle" : "shuffle",
                    isActive: player.state.shuffle
                ) { socket.toggleShuffle(!player.state.shuffle) }

                Spacer()

                IconButton(
                    icon: player.state.repeat ? "repeat" : "repeat",
                    isActive: player.state.repeat
                ) { socket.toggleRepeat(!player.state.repeat) }
            }
            .padding(.horizontal, 16)

            // Main controls
            HStack(spacing: 32) {
                Spacer()

                IconButton(icon: "backward.fill", size: 28) { socket.prev() }

                // Play / Pause — primary button
                Button {
                    socket.playPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.mdOnPrimary)
                        .frame(width: 72, height: 72)
                        .background(.mdPrimary, in: Circle())
                }
                .buttonStyle(StellarPlayPressStyle())
                .contentShape(Circle())

                IconButton(icon: "forward.fill", size: 28) { socket.next() }

                Spacer()
            }

            // Volume
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.mdOnSurfaceVariant)
                    .font(.system(size: 14))

                Slider(
                    value: Binding(
                        get: { Double(player.state.volume) },
                        set: { socket.setVolume(Int($0)) }
                    ),
                    in: 0...100
                )
                .tint(.mdPrimary)

                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.mdOnSurfaceVariant)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 20)
        .background(.mdSurfaceContainer, in: RoundedRectangle(cornerRadius: .mdShapeExtraLarge))
    }

    // MARK: - Helpers
    private func formatTime(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Icon Button
struct IconButton: View {
    let icon: String
    var size: CGFloat = 24
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isActive ? .mdPrimary : .mdOnSurfaceVariant)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(StellarIconPressStyle())
    }
}
