import SwiftUI

// MARK: - AirplaySourceBadge
//
// Gold capsule that mirrors `FormatBadgeStrip` styling (9pt bold, tracking
// 0.6, gold-on-goldFill capsule) but with a leading SF Symbol AirPlay glyph
// + the sender device name. Reads "AIRPLAY · <sender>" — when `sender` is
// empty the centre dot is omitted.
//
// Truncation: the sender device name is bounded at one line with
// tail-ellipsis so a long device name ("Eduardo's Apple Watch Ultra 2",
// etc.) doesn't push the badge past the view width.

struct AirplaySourceBadge: View {
    let sender: String

    private var hasSender: Bool {
        !sender.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "airplayaudio")
                .font(.system(size: 10, weight: .bold))

            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(Stellar.Color.gold)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Stellar.Color.goldFill, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasSender ? "AirPlay from \(sender)" : "AirPlay")
    }

    private var label: String {
        if hasSender {
            return "AIRPLAY · \(sender.uppercased())"
        }
        return "AIRPLAY"
    }
}

#if DEBUG
#Preview("With sender") {
    AirplaySourceBadge(sender: "Eduardo's iPhone")
        .padding()
        .background(Stellar.Color.baseBackground)
}

#Preview("Empty sender") {
    AirplaySourceBadge(sender: "")
        .padding()
        .background(Stellar.Color.baseBackground)
}

#Preview("Long sender") {
    AirplaySourceBadge(sender: "Eduardo's Apple Watch Ultra 2 Pro Max XDR")
        .padding(20)
        .frame(width: 240)
        .background(Stellar.Color.baseBackground)
}
#endif
