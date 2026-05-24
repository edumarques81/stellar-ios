import SwiftUI

struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Stellar.Color.gold)
                    .frame(width: Stellar.Metric.playDisc, height: Stellar.Metric.playDisc)
                    .shadow(color: Stellar.Color.gold.opacity(0.3), radius: 16, y: 4)

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.black)
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .offset(x: isPlaying ? 0 : Stellar.Metric.playGlyphOffset)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}
