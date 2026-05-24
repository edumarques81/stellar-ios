import SwiftUI

struct FormatBadgeStrip: View {
    let trackType: String
    let samplerate: String
    let bitdepth: String

    private var badges: [String] {
        var out: [String] = []
        if !trackType.isEmpty { out.append(trackType.uppercased()) }
        if let sr = Double(samplerate), sr > 0 {
            out.append(String(format: "%.0fkHz", sr / 1000))
        }
        if !bitdepth.isEmpty, bitdepth != "0" {
            out.append("\(bitdepth)bit")
        }
        return out
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(badges, id: \.self) { badge in
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Stellar.Color.gold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Stellar.Color.goldFill, in: Capsule())
            }
        }
    }
}
