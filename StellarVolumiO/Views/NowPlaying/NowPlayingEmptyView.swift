import SwiftUI

struct NowPlayingEmptyView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("Nothing playing")
                    .font(.system(size: 18, weight: .semibold))
                Text("Tap the Library tab to start a track.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
