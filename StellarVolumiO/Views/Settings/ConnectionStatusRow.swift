import SwiftUI

struct ConnectionStatusRow: View {
    @Environment(SocketService.self) private var socket

    var body: some View {
        HStack(spacing: 10) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Stellar.Color.surfaceLow, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var statusDot: some View {
        switch socket.reportedConnectionState {
        case .connected:
            Circle().fill(Stellar.Color.statusGreen).frame(width: 10, height: 10)
        case .connecting:
            ProgressView().scaleEffect(0.6).frame(width: 10, height: 10)
        case .disconnected:
            Circle().fill(Stellar.Color.statusRed).frame(width: 10, height: 10)
        case .error:
            Circle().fill(Stellar.Color.statusRed).frame(width: 10, height: 10)
        }
    }

    private var headline: String {
        switch socket.reportedConnectionState {
        case .connected:    return "Connected"
        case .connecting:   return "Connecting…"
        case .disconnected: return "Disconnected"
        case .error:        return "Connection error"
        }
    }

    private var detail: String {
        switch socket.reportedConnectionState {
        case .error(let msg):
            return String(msg.prefix(80))
        default:
            return "\(socket.serverHost):\(socket.serverPort)"
        }
    }
}
