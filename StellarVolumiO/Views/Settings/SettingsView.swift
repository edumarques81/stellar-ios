import SwiftUI

/// Minimal settings: just the LCD on/off toggle. That is intentionally the
/// only thing this app's Settings screen does — see CLAUDE.md "Scope".
struct SettingsView: View {
    @Environment(LcdStore.self) private var lcd
    @Environment(SocketService.self) private var socket

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                lcdCard

                hostFooter

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .background(Color.mdBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.mdBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear { lcd.refresh() }
    }

    private var lcdCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: lcd.isOn ? "display" : "display.trianglebadge.exclamationmark")
                    .font(.system(size: 22))
                    .foregroundStyle(lcd.isOn ? .mdPrimary : .mdOnSurfaceVariant)

                VStack(alignment: .leading, spacing: 2) {
                    Text("LCD screen")
                        .font(StellarFont.titleMedium)
                        .foregroundStyle(.mdOnSurface)
                    Text(lcd.isOn ? "On" : "Off")
                        .font(StellarFont.bodySmall)
                        .foregroundStyle(.mdOnSurfaceVariant)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { lcd.isOn },
                    set: { lcd.setOn($0) }
                ))
                .labelsHidden()
                .tint(.mdPrimary)
            }
        }
        .padding(16)
        .background(.mdSurfaceContainerHigh, in: RoundedRectangle(cornerRadius: .mdShapeLarge))
    }

    private var hostFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Backend")
                .font(StellarFont.labelMedium)
                .foregroundStyle(.mdOnSurfaceVariant.opacity(0.7))
            Text("\(socket.serverHost):\(socket.serverPort)")
                .font(StellarFont.bodySmall.monospaced())
                .foregroundStyle(.mdOnSurfaceVariant)
            Text(connectionLabel)
                .font(StellarFont.labelSmall)
                .foregroundStyle(connectionTint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.mdSurfaceContainerLow, in: RoundedRectangle(cornerRadius: .mdShapeMedium))
    }

    private var connectionLabel: String {
        switch socket.connectionState {
        case .connected:        return "Connected"
        case .connecting:       return "Connecting…"
        case .disconnected:     return "Disconnected"
        case .error(let msg):   return "Error: \(msg)"
        }
    }

    private var connectionTint: Color {
        switch socket.connectionState {
        case .connected:    return .mdSuccess
        case .error:        return .mdError
        default:            return .mdOnSurfaceVariant
        }
    }
}
