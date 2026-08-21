import Foundation

/// A screen the Pi's LCD kiosk can show.
///
/// Raw values are the frontend's `ViewType` strings verbatim (Volumio2-UI
/// `src/lib/stores/navigation.ts`) — they travel over the wire unchanged.
enum LcdView: String, Decodable, Equatable {
    case player
    case library
    case queue
    case settings
    case vuMeter = "vu-meter"

    /// A view this build doesn't know about. Decoding must never throw here:
    /// a backend that grows a new screen would otherwise take the whole
    /// `pushLcdView` frame down and strand the toggle on a stale value.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LcdView(rawValue: raw) ?? .unknown
    }
}

/// `pushLcdView` payload.
///
/// `previousView` is the backend's memory of the screen the kiosk was on
/// before the current one. It is what lets this app flip the panel to the VU
/// meter and back without keeping any history of its own.
struct LcdViewStatus: Decodable, Equatable {
    let view: LcdView
    let previousView: LcdView

    init(view: LcdView, previousView: LcdView) {
        self.view = view
        self.previousView = previousView
    }

    enum CodingKeys: String, CodingKey {
        case view
        case previousView
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.view = try c.decodeIfPresent(LcdView.self, forKey: .view) ?? .unknown
        self.previousView = try c.decodeIfPresent(LcdView.self, forKey: .previousView) ?? .unknown
    }
}
