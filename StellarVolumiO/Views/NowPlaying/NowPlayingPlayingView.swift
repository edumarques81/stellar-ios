import SwiftUI

// MARK: - NowPlayingDisplayState
//
// Source-neutral adapter consumed by `NowPlayingPlayingView`. Lets the same
// view render either MPD-source or AirPlay-source playback without forking
// the entire view tree.
//
// `albumArt` is an enum so the renderer can either fetch a URL (MPD path —
// `/albumart?path=...` on the backend host) or decode an inline `data:`
// URL straight from the AirPlay session (the data URL travels in the
// `pushAirplayState` envelope).

enum AlbumArtSource: Equatable {
    case url(URL?)
    case dataURL(String) // "data:image/jpeg;base64,..."
    case none
}

struct NowPlayingDisplayState {
    var title: String
    var artist: String
    var album: String
    var trackType: String
    var samplerate: String  // matches FormatBadgeStrip's String shape
    var bitdepth: String    // matches FormatBadgeStrip's String shape
    var seekSeconds: Double
    var durationSeconds: Double
    var isPlaying: Bool

    /// True when the SeekBar should accept drag → emit. False on AirPlay,
    /// where seek scrubbing isn't part of the DACP control surface.
    var canSeek: Bool

    /// Gates the transport buttons. AirPlay → false while the Active-Remote
    /// token is still resolving; MPD → always true.
    var canControl: Bool

    /// AirPlay source mode draws the "AIRPLAY · <sender>" badge above the
    /// title block. MPD source mode renders the FormatBadgeStrip below the
    /// title block. The two are mutually exclusive — `airplaySender` being
    /// non-nil also signals "this is the AirPlay branch".
    var airplaySender: String?

    var albumArt: AlbumArtSource

    var isAirplay: Bool { airplaySender != nil }
}

extension NowPlayingDisplayState {
    /// Build an AirPlay-source display state from the canonical
    /// `AirplayState`. Factored out so the adapter is unit-testable in
    /// isolation (no need to stand up a SwiftUI host).
    ///
    /// Wiring contract:
    /// - `isPlaying` reads `state.isPlaying` (NOT `state.isActive`) so the
    ///   play/pause glyph flips when the iPhone pauses Apple Music
    ///   mid-session. `isActive` only gates the branch selection in
    ///   NowPlayingView; once we're inside the AirPlay branch, `isPlaying`
    ///   alone owns the transport icon.
    /// - `canSeek` is always false — DACP has no seek surface.
    /// - `canControl` gates the transport buttons on the backend having
    ///   resolved the Active-Remote token.
    /// - `airplaySender` carrying the device name is what flags this as
    ///   the AirPlay branch to the renderer.
    static func from(airplay s: AirplayState) -> NowPlayingDisplayState {
        NowPlayingDisplayState(
            title: s.title,
            artist: s.artist,
            album: s.album,
            trackType: "",
            samplerate: "",
            bitdepth: "",
            seekSeconds: s.seekSecondsDouble,
            durationSeconds: s.durationSecondsDouble,
            isPlaying: s.isPlaying,
            canSeek: false,
            canControl: s.canControl,
            airplaySender: s.sender,
            albumArt: s.coverDataURL.isEmpty ? .none : .dataURL(s.coverDataURL)
        )
    }
}

// MARK: - Transport callbacks
//
// Source-neutral closures bundled together so the view stays oblivious to
// whether play/pause routes to MPD (`socket.play()`) or AirPlay
// (`airplayStore.play()`). The caller wires the right destination.

struct NowPlayingTransportCallbacks {
    var onPrev: () -> Void
    var onPlayPause: () -> Void
    var onNext: () -> Void
    var onSeek: (Int) -> Void
}

// MARK: - NowPlayingPlayingView (parameterised)

struct NowPlayingPlayingView: View {
    let state: NowPlayingDisplayState
    let callbacks: NowPlayingTransportCallbacks

    var body: some View {
        VStack(spacing: 0) {
            AlbumArtHero(source: state.albumArt)
                .padding(.top, 8)
                .padding(.horizontal, 24)

            // AirPlay badge slots ABOVE the title block — between the
            // cover and the text — matching the brief's UI spec.
            if let sender = state.airplaySender {
                AirplaySourceBadge(sender: sender)
                    .padding(.top, 14)
            }

            VStack(spacing: 4) {
                Text(state.title.isEmpty ? "—" : state.title)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(2)
                Text(state.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(state.album)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, state.airplaySender == nil ? 16 : 10)

            // MPD branch renders the format strip (FLAC/96kHz/24bit).
            // AirPlay branch suppresses it — the wire shape carries
            // sampleRate/bitDepth but in practice every AirPlay 1
            // stream is 44.1kHz/16-bit (CD-equivalent) which would just
            // be visual noise. Format detail is still in state for future
            // tooltip/details exposure but the strip stays hidden.
            if !state.isAirplay {
                FormatBadgeStrip(
                    trackType: state.trackType,
                    samplerate: state.samplerate,
                    bitdepth: state.bitdepth
                )
                .padding(.top, 10)
            }

            SeekBar(
                currentSeconds: state.seekSeconds,
                totalSeconds: state.durationSeconds,
                onSeek: state.canSeek ? callbacks.onSeek : { _ in }
            )
            .padding(.top, 18)
            .padding(.horizontal, 24)
            .opacity(state.canSeek ? 1.0 : 0.6)
            .allowsHitTesting(state.canSeek)

            HStack(spacing: 28) {
                TransportIconButton(icon: "backward.fill", enabled: state.canControl) {
                    callbacks.onPrev()
                }

                PlayPauseButton(isPlaying: state.isPlaying) {
                    callbacks.onPlayPause()
                }
                .opacity(state.canControl ? 1.0 : 0.5)
                .allowsHitTesting(state.canControl)

                TransportIconButton(icon: "forward.fill", enabled: state.canControl) {
                    callbacks.onNext()
                }
            }
            .padding(.top, 22)
            .overlay(alignment: .bottom) {
                if !state.canControl {
                    Text("Connecting…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .offset(y: 20)
                }
            }
        }
    }
}

// MARK: - Subcomponents

private struct AlbumArtHero: View {
    let source: AlbumArtSource

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ZStack {
                    placeholder
                    switch source {
                    case .url(let url):
                        if let url {
                            CachedAsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                EmptyView()
                            }
                        }
                    case .dataURL(let s):
                        if let img = Self.decodeDataURL(s) {
                            Image(uiImage: img).resizable().scaledToFill()
                        }
                    case .none:
                        EmptyView()
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Stellar.Metric.artCornerRadius))
            .shadow(color: .black.opacity(Stellar.Shadow.albumArt.opacity),
                    radius: Stellar.Shadow.albumArt.radius,
                    y: Stellar.Shadow.albumArt.y)
    }

    private var placeholder: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [SwiftUI.Color(red: 0x2a/255, green: 0x35/255, blue: 0x48/255),
                         SwiftUI.Color(red: 0x1a/255, green: 0x1f/255, blue: 0x2e/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
    }

    /// Decode a `data:image/...;base64,<payload>` URL into a UIImage.
    /// Returns nil on any malformed input — caller falls back to the
    /// gradient placeholder.
    private static func decodeDataURL(_ s: String) -> UIImage? {
        guard let comma = s.range(of: ",") else { return nil }
        let payload = String(s[comma.upperBound...])
        guard let data = Data(base64Encoded: payload) else { return nil }
        return UIImage(data: data)
    }
}

private struct TransportIconButton: View {
    let icon: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: Stellar.Metric.minTouchTarget,
                       height: Stellar.Metric.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1.0 : 0.5)
        .allowsHitTesting(enabled)
    }
}
