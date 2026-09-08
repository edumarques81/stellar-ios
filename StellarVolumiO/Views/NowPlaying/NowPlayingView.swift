import SwiftUI

// MARK: - NowPlayingView
//
// Top-level Now Playing tab. Picks between three branches:
//
//   1. AirPlay session active (`airplayStore.state.isActive`) → render
//      `NowPlayingPlayingView` with the AirPlay-source adapter +
//      `airplayStore.*` transport callbacks.
//   2. MPD playing a track → render `NowPlayingPlayingView` with the
//      MPD-source adapter + `socket.*` transport callbacks.
//   3. Otherwise show the last-played teaser or the empty-state placeholder.
//
// AirPlay takes precedence over MPD when both are technically "active" —
// in practice the Pi-side pre-hook pauses MPD on AirPlay-begin so they
// don't overlap, but the precedence keeps us correct if that hook ever
// races or is bypassed.

struct NowPlayingView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(AirplayStore.self) private var airplay
    @Environment(SocketService.self) private var socket
    @Environment(LastPlayedStore.self) private var lastPlayed

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.stellarIdiom) private var idiom

    var body: some View {
        ZStack {
            StellarGlassyBackground()

            // Two trees, not one with a no-op branch. The roomy canvas needs a
            // `GeometryReader` to centre the column against the pane height;
            // the phone does not, and `GeometryReader` is not free — it sizes
            // greedily and places its child `.topLeading`, which is exactly
            // the kind of quiet difference REG-01 exists to prevent. The phone
            // gets the tree it shipped with.
            if centreVertically {
                GeometryReader { geo in
                    scroll(centringWithin: geo.size.height)
                }
            } else {
                scroll(centringWithin: nil)
            }
        }
        // Re-fetch the AirPlay snapshot whenever the tab becomes visible.
        // Covers the case where the user backgrounds the app, an AirPlay
        // session starts/ends/changes track, then they refocus — without
        // this the view stays on its stale prior state until shairport
        // happens to emit a new metadata frame.
        .onAppear {
            socket.requestAirplayState()
        }
    }

    /// The iPhone has always top-aligned and always fills its screen; leave it
    /// alone (REG-01) and only centre on the roomier canvas. Asked through
    /// `RootLayoutMode` rather than the size class alone, so the `idiom == .pad`
    /// guard covers this too — a size class on its own is regular for an iPhone
    /// Max in landscape.
    private var centreVertically: Bool {
        RootLayoutMode.isRoomy(horizontalSizeClass: horizontalSizeClass, idiom: idiom)
    }

    /// The scrolling column. `paneHeight` is non-nil only on the roomy canvas,
    /// where the column is centred against it; on a phone the column is laid
    /// out exactly as it always was.
    private func scroll(centringWithin paneHeight: CGFloat?) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                content
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                    // Cap the column, then centre it. The hero is
                    // `maxWidth: .infinity`, so without the cap it would grow
                    // to whatever the iPad hands it — a 1000 pt cover with the
                    // transport controls somewhere below the fold. No iPhone is
                    // this wide, so the phone is unaffected.
                    .frame(maxWidth: Stellar.Metric.contentMaxWidth)
                    .frame(maxWidth: .infinity)
            }
            // On a tall iPad pane the column would otherwise sit jammed against
            // the top with the bottom half empty. `minHeight` rather than
            // `height`: when the content is taller than the pane — an 11" in
            // landscape, say — it still lays out in full and scrolls.
            .frame(minHeight: paneHeight ?? 0, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 16, for: .scrollContent)
    }

    @ViewBuilder
    private var content: some View {
        if airplay.state.isActive {
            NowPlayingPlayingView(
                state: airplayDisplayState,
                callbacks: airplayCallbacks
            )
        } else if player.hasTrack && player.state.status != .stop {
            NowPlayingPlayingView(
                state: mpdDisplayState,
                callbacks: mpdCallbacks
            )
        } else if let last = lastPlayed.album {
            NowPlayingIdleView(album: last)
        } else {
            NowPlayingEmptyView()
        }
    }

    // MARK: - MPD adapter

    private var mpdDisplayState: NowPlayingDisplayState {
        NowPlayingDisplayState(
            title: player.state.title,
            artist: player.state.artist,
            album: player.state.album,
            trackType: player.state.trackType,
            samplerate: player.state.samplerate,
            bitdepth: player.state.bitdepth,
            seekSeconds: player.state.seekSeconds,
            durationSeconds: player.state.durationSeconds,
            isPlaying: player.isPlaying,
            canSeek: true,
            canControl: true,
            airplaySender: nil,
            albumArt: mpdAlbumArt
        )
    }

    private var mpdAlbumArt: AlbumArtSource {
        let s = player.state.albumart
        guard !s.isEmpty else { return .none }
        if s.hasPrefix("http") { return .url(URL(string: s)) }
        let path = s.hasPrefix("/") ? s : "/\(s)"
        return .url(URL(string: "http://\(socket.serverHost):\(socket.serverPort)\(path)"))
    }

    private var mpdCallbacks: NowPlayingTransportCallbacks {
        NowPlayingTransportCallbacks(
            onPrev:      { socket.prev() },
            onPlayPause: {
                player.applyOptimistic(player.isPlaying ? .pause : .play)
                socket.playPause()
            },
            onNext:      { socket.next() },
            onSeek:      { seconds in
                player.applyOptimisticSeek(seconds * 1_000)
                socket.seek(to: seconds)
            }
        )
    }

    // MARK: - AirPlay adapter

    private var airplayDisplayState: NowPlayingDisplayState {
        // Adapter logic lives in `NowPlayingDisplayState.from(airplay:)` so
        // it's unit-testable without standing up a SwiftUI host. See its
        // doc-comment for the isPlaying/canSeek/canControl wiring contract.
        .from(airplay: airplay.state)
    }

    private var airplayCallbacks: NowPlayingTransportCallbacks {
        NowPlayingTransportCallbacks(
            onPrev:      { airplay.prev() },
            onPlayPause: { airplay.playPause() },
            onNext:      { airplay.next() },
            onSeek:      { _ in /* AirPlay: seek disabled */ }
        )
    }
}
