import SwiftUI

/// Renders `SocketService.lastDecodeError` when present. Hidden when nil.
struct DecodeErrorRow: View {
    @Environment(SocketService.self) private var socket

    var body: some View {
        if let err = socket.lastDecodeError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Stellar.Color.statusRed)
                    .font(.system(size: 13))
                Text(err)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Stellar.Color.statusRed)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Stellar.Color.surfaceLow, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
