import XCTest
import SwiftUI
@testable import StellarVolumiO

/// The grid's one non-negotiable: a tile's size is decided by the grid, never
/// by the picture that lands in it.
///
/// The library legitimately holds non-square covers — at the time of writing
/// `Rachmaninoff Symphonic Dances` is 1526x2156 and `Stravinsky [Oue] (HRx)`
/// is 366x517, both roughly 0.71:1 portrait. The tile that shipped wrapped a
/// `ZStack` around `image.resizable().scaledToFill()` and applied
/// `.aspectRatio(1, contentMode: .fit)` to the *stack*. Inside a `LazyVGrid`
/// the height proposal is nil, so the aspect-ratio modifier has to fall back on
/// its child's ideal size — and a resizable image's ideal size is derived from
/// the picture. Those two covers therefore sized their own tiles, the rows they
/// sat in went ragged, and the grid broke. `.clipShape` did not save it:
/// clipping changes what is drawn, not what is laid out.
///
/// `AlbumArtworkSquare` exists so that cannot happen again — the square is
/// driven by a fully flexible `Color.clear`, and the artwork rides along as an
/// `.overlay`, which by construction is proposed the parent's size and can
/// never feed a size back up.
///
/// These measure with `sizeThatFits(in:)` at a definite width and an unbounded
/// height, which is exactly the proposal a `LazyVGrid` cell makes.
@MainActor
final class AlbumArtworkSquareTests: XCTestCase {

    /// Every aspect ratio the real library contains, plus the extremes.
    private static let aspects: [(name: String, size: CGSize)] = [
        ("square 600x600",              CGSize(width: 600,  height: 600)),
        ("portrait 1526x2156 (FR-768)", CGSize(width: 1526, height: 2156)),
        ("portrait 366x517 (HRx)",      CGSize(width: 366,  height: 517)),
        ("landscape 3000x1000",         CGSize(width: 3000, height: 1000)),
        ("extreme portrait 100x2000",   CGSize(width: 100,  height: 2000)),
    ]

    private static let tileWidths: [CGFloat] = [150, 180, 200, 240, 320]

    func testSquareIsSquareForEveryArtworkAspectRatio() {
        for aspect in Self.aspects {
            let art = Self.image(size: aspect.size)
            for width in Self.tileWidths {
                let measured = Self.measure(width: width) {
                    AlbumArtworkSquare {
                        Image(uiImage: art).resizable().scaledToFit()
                    }
                }
                XCTAssertEqual(measured.width, width, accuracy: 0.5,
                               "\(aspect.name) at \(width)pt took a width it was not offered")
                XCTAssertEqual(measured.height, measured.width, accuracy: 0.5,
                               "\(aspect.name) at \(width)pt rendered \(measured.width)x\(measured.height) — not square")
            }
        }
    }

    /// A `scaledToFill` caller must not break the invariant either. Fit is what
    /// the app uses (nothing gets cropped), but the component has to hold for
    /// fill too or the guarantee is really a convention.
    func testSquareIsSquareEvenWhenTheContentOverflowsIt() {
        for aspect in Self.aspects {
            let art = Self.image(size: aspect.size)
            let measured = Self.measure(width: 180) {
                AlbumArtworkSquare {
                    Image(uiImage: art).resizable().scaledToFill()
                }
            }
            XCTAssertEqual(measured.height, measured.width, accuracy: 0.5,
                           "\(aspect.name) filling the square rendered \(measured.width)x\(measured.height)")
        }
    }

    /// The whole tile, not just the artwork: a grid cell is the square plus its
    /// two text rows, and every cell in a row has to come out the same height
    /// or the grid staggers. Text height varies with Dynamic Type, not with the
    /// cover, so the check is that two different covers agree.
    func testTwoTilesWithDifferentCoversMeasureIdentically() {
        let square = Self.image(size: CGSize(width: 600, height: 600))
        let portrait = Self.image(size: CGSize(width: 1526, height: 2156))

        func tile(_ art: UIImage) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                AlbumArtworkSquare {
                    Image(uiImage: art).resizable().scaledToFit()
                }
                Text("Album title").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("Artist").font(.system(size: 10)).lineLimit(1)
            }
        }

        let a = Self.measure(width: 180) { tile(square) }
        let b = Self.measure(width: 180) { tile(portrait) }

        XCTAssertEqual(a.height, b.height, accuracy: 0.5,
                       "a portrait cover changed the tile height: \(a.height) vs \(b.height)")
    }

    /// No artwork at all still has to produce the same square, otherwise a
    /// library with missing covers staggers exactly the same way.
    func testEmptySquareStillMeasuresSquare() {
        let measured = Self.measure(width: 180) {
            AlbumArtworkSquare { EmptyView() }
        }
        XCTAssertEqual(measured.width, 180, accuracy: 0.5)
        XCTAssertEqual(measured.height, 180, accuracy: 0.5)
    }

    // MARK: - Helpers

    /// The proposal a `LazyVGrid` cell makes: a definite width, no height.
    private static func measure<V: View>(width: CGFloat,
                                         @ViewBuilder _ view: () -> V) -> CGSize {
        let host = UIHostingController(rootView: view())
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    /// A solid image at an exact pixel size — the aspect ratio is the only
    /// property under test.
    private static func image(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
