import SwiftUI

/// A square artwork frame whose size never depends on the artwork.
///
/// The library holds covers that are not square — `Rachmaninoff Symphonic
/// Dances` is 1526x2156, `Stravinsky [Oue] (HRx)` is 366x517 — and that is
/// fine as an *input*. What is not fine is letting one of them size the tile
/// it sits in.
///
/// The obvious composition does exactly that:
///
/// ```swift
/// ZStack { backdrop; image.resizable().scaledToFill() }
///     .aspectRatio(1, contentMode: .fit)      // <- too late
/// ```
///
/// Inside a `LazyVGrid` the height proposal is nil, so `.aspectRatio` has to
/// resolve it from its child's ideal size, and a resizable image's ideal size
/// is the picture's own. At a 180pt column the FR-768 cover measured
/// 180x254 — 74pt taller than every other tile in its row, which is what put
/// the grid out of alignment. `.clipShape` does not help: clipping changes
/// what is drawn, never what is laid out.
///
/// So the square is driven by a fully flexible `Color.clear`, and the artwork
/// is attached as an `.overlay`. An overlay is proposed its parent's size and
/// cannot report a size back up, which makes the guarantee structural rather
/// than a convention every call site has to remember.
///
/// Pinned by `AlbumArtworkSquareTests`.
struct AlbumArtworkSquare<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: Content

    init(cornerRadius: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { AlbumArtworkBackdrop() }
            .overlay { content }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// Album art loaded from the backend, scaled to sit inside its square.
///
/// `scaledToFit`, not `scaledToFill`: a 0.71:1 portrait cover centre-cropped to
/// a square loses ~29% off the top and the bottom, which on a classical release
/// is usually the title and the performer. Letterboxing it onto the backdrop
/// keeps the whole cover and still leaves every tile identical — square covers,
/// which are all but two of the library, look exactly as they always did.
struct AlbumArtworkImage: View {
    let url: URL?

    var body: some View {
        if let url {
            CachedAsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                EmptyView()
            }
        }
    }
}

/// The gradient a cover sits on: the empty-artwork placeholder, and the
/// letterbox bars either side of a non-square one.
struct AlbumArtworkBackdrop: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [SwiftUI.Color(red: 0x2a/255, green: 0x35/255, blue: 0x48/255),
                         SwiftUI.Color(red: 0x1a/255, green: 0x1f/255, blue: 0x2e/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
    }
}
