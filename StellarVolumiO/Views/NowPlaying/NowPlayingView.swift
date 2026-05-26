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

    var body: some View {
        ZStack {
            StellarGlassyBackground()

            ScrollView {
                VStack(spacing: 0) {
                    content
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, 16, for: .scrollContent)
        }
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
            onSeek:      { socket.seek(to: $0) }
        )
    }

    // MARK: - AirPlay adapter

    private var airplayDisplayState: NowPlayingDisplayState {
        // AirPlay treats the session as "playing" whenever it's active —
        // shairport-sync's metadata pipe doesn't expose a paused-but-still-
        // tuned distinction. The DACP-side pause command flips isActive
        // only on stream-end. UI-side, isPlaying mirrors isActive.
        NowPlayingDisplayState(
            title: airplay.state.title,
            artist: airplay.state.artist,
            album: airplay.state.album,
            trackType: "",
            samplerate: "",
            bitdepth: "",
            seekSeconds: airplay.state.seekSecondsDouble,
            durationSeconds: airplay.state.durationSecondsDouble,
            isPlaying: airplay.state.isActive,
            canSeek: false,                          // DACP doesn't expose seek
            canControl: airplay.state.canControl,    // gates on Active-Remote token
            airplaySender: airplay.state.sender,
            albumArt: airplay.state.coverDataURL.isEmpty
                ? .none
                : .dataURL(airplay.state.coverDataURL)
        )
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
