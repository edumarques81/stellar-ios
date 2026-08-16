import SwiftUI

/// Drop-in replacement for `AsyncImage(url:content:placeholder:)` that
/// reads from `URLCache.shared` aggressively. Built specifically for the
/// album-art use case: once an image lands in the cache, subsequent loads
/// short-circuit to disk (`.returnCacheDataElseLoad`) even when the
/// backend's `max-age` would otherwise expire the response.
///
/// Combined with the persistent disk cache configured in
/// `AlbumArtCache.configureSharedCache()` and the signal-based invalidation
/// in `AlbumPickerStore`, this means:
///
/// - First view of an album cover: fetch + cache.
/// - All subsequent views (this session OR future launches): served from
///   disk, even with the backend unreachable.
/// - Library list changes (new/removed albums): fingerprint shifts, store
///   calls `AlbumArtCache.invalidate()`, next view re-fetches.
///
/// Implementation note: we deliberately avoid `.task(id:)` here. `LazyVGrid`
/// in a scrolling container aggressively recycles tile views, which causes
/// `.task` to cancel mid-flight before the response lands in URLCache. Using
/// a plain `onAppear` + a `URLSession.shared.dataTask` (callback-based) keeps
/// the request alive long enough for the response to be persisted, while
/// still letting us drop the in-memory `UIImage` if the view goes away.
///
/// `onAppear` alone is not enough, though — it only covers the case where the
/// view is *created* with its URL. Two triggers are load-bearing for the Now
/// Playing hero, which is a single long-lived view whose `url` mutates in
/// place, and they are why this view also watches `url` and the foreground
/// transition. See `startLoad()`.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    /// Attempts per URL, including the first. Two retries is enough to ride
    /// out a waking Wi-Fi radio or a backend restart without hammering it.
    private static var maxAttempts: Int { 3 }

    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var loadedURL: URL?
    /// The URL a request is currently in flight for. The three load triggers
    /// can fire in any order for the same URL; this keeps them to one request.
    @State private var inFlightURL: URL?
    @State private var attempts = 0

    init(url: URL?,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        ZStack {
            // A zero-alpha Color.clear gives the ZStack a real layout footprint
            // even when the caller's `placeholder` is EmptyView(). Without
            // this, an EmptyView-only branch produces a layout-empty view and
            // SwiftUI may skip firing `.onAppear` on it — which is exactly
            // what blocks initial loads in a LazyVGrid full of empty tiles.
            Color.clear
            placeholder()
            if let img = loadedImage, loadedURL == url {
                content(Image(uiImage: img))
            }
        }
        .onAppear { startLoad() }
        // A track change does not rebuild the Now Playing hero — SwiftUI keeps
        // the same view identity and just hands it a new `url`. `onAppear`
        // never fires again, so the render gate below (`loadedURL == url`)
        // hid the previous cover and nothing ever fetched the new one: a blank
        // square for the rest of the session. Unlike `.task(id:)` this does
        // not cancel an in-flight request when a LazyVGrid recycles a tile.
        .onChange(of: url) { _, _ in
            attempts = 0
            startLoad()
        }
        // The other way this stranded: a request still in flight when the app
        // suspends comes back with no data, and a failure used to be terminal.
        // Re-arm on the way back to the foreground, but only if this view is
        // actually still showing nothing.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            guard loadedImage == nil || loadedURL != url else { return }
            attempts = 0
            startLoad()
        }
    }

    private func startLoad() {
        // Already loaded this URL — keep the cached UIImage.
        if loadedImage != nil && loadedURL == url { return }

        guard let url else { return }
        // Another trigger already asked for this exact URL.
        if inFlightURL == url { return }

        inFlightURL = url
        attempts += 1

        // Cache policy: prefer disk. If absent, fall through to the network
        // and let URLCache.shared store the response (the backend sets
        // Cache-Control: public, max-age=86400 on success).
        var request = URLRequest(url: url,
                                 cachePolicy: .returnCacheDataElseLoad,
                                 timeoutInterval: 10)
        request.httpShouldHandleCookies = false

        URLSession.shared.dataTask(with: request) { data, _, _ in
            let image = data.flatMap(UIImage.init(data:))
            DispatchQueue.main.async {
                // Drop the result if the view's URL has since changed (e.g.
                // the tile was recycled to a different album while in flight).
                guard url == self.url else {
                    if self.inFlightURL == url { self.inFlightURL = nil }
                    return
                }
                self.inFlightURL = nil

                if let image {
                    self.loadedImage = image
                    self.loadedURL = url
                    self.attempts = 0
                    return
                }

                // Transient failure — a waking radio, a restarting backend, a
                // request dropped by suspension. Returning silently here is
                // what used to leave the square blank until the view was
                // rebuilt, so back off and try again a couple of times.
                guard self.attempts < Self.maxAttempts else { return }
                let backoff = Double(self.attempts)
                DispatchQueue.main.asyncAfter(deadline: .now() + backoff) {
                    guard url == self.url else { return }
                    self.startLoad()
                }
            }
        }.resume()
    }
}
