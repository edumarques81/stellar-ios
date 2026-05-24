import SwiftUI

struct SeekBar: View {
    let currentSeconds: Double
    let totalSeconds: Double
    let onSeek: (Int) -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    private var displayed: Double { isDragging ? dragValue : currentSeconds }
    private var safeTotal: Double { max(1, totalSeconds) }

    var body: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { displayed },
                    set: { dragValue = $0 }
                ),
                in: 0...safeTotal,
                onEditingChanged: { editing in
                    if editing { dragValue = currentSeconds }
                    isDragging = editing
                    if !editing { onSeek(Int(dragValue)) }
                }
            )
            .tint(Stellar.Color.gold)

            HStack {
                Text(format(displayed))
                Spacer()
                Text(format(totalSeconds))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
