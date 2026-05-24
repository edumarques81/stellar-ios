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
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var loadedURL: URL?

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
    }

    private func startLoad() {
        // Already loaded this URL — keep the cached UIImage.
        if loadedImage != nil && loadedURL == url { return }

        guard let url else { return }

        // Cache policy: prefer disk. If absent, fall through to the network
        // and let URLCache.shared store the response (the backend sets
        // Cache-Control: public, max-age=86400 on success).
        var request = URLRequest(url: url,
                                 cachePolicy: .returnCacheDataElseLoad,
                                 timeoutInterval: 10)
        request.httpShouldHandleCookies = false

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                // Drop the result if the view's URL has since changed (e.g.
                // the tile was recycled to a different album while in flight).
                guard url == self.url else { return }
                self.loadedImage = img
                self.loadedURL = url
            }
        }.resume()
    }
}
