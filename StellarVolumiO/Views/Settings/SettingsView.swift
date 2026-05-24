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

    // Regression note (2026-05-25):
    //   The previous lcdCard used `Toggle("", isOn: Binding(get:set:)).labelsHidden()`
    //   nested inside `HStack { Image; VStack(text); Spacer(); Toggle }` inside a
    //   `NavigationStack` with `.navigationBarTitleDisplayMode(.inline)` and
    //   `.toolbarBackground(.visible, for: .navigationBar)`. On iOS 18.3 this
    //   combination silently dropped the Toggle's tap dispatch — the `set` closure
    //   was never invoked even though the card itself was visible and rendered
    //   correctly. Tab navigation, button taps in other views (NowPlaying play,
    //   Library album tap), and the SettingsView's `.onTapGesture` on the parent
    //   all worked, isolating the dead zone to interactive controls inside the
    //   card after the Spacer().
    //
    //   The fix: make the whole row a single Button with a custom Capsule+Circle
    //   switch graphic. The Button reliably receives the tap (we verified an
    //   identical structure with a Button instead of Toggle fires) and the
    //   custom graphic keeps the visual match to a native iOS switch. The
    //   setOn semantics are pinned by `LcdStoreTests`.
    private var lcdCard: some View {
        Button {
            lcd.setOn(!lcd.isOn)
        } label: {
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

                // Custom switch graphic — mimics native UIToggle visually.
                ZStack(alignment: lcd.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(lcd.isOn ? Color.mdPrimary : Color.mdOnSurfaceVariant.opacity(0.35))
                        .frame(width: 51, height: 31)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 27, height: 27)
                        .padding(.horizontal, 2)
                        .shadow(radius: 1)
                }
                .animation(.easeInOut(duration: 0.15), value: lcd.isOn)
            }
            .padding(16)
            .background(.mdSurfaceContainerHigh, in: RoundedRectangle(cornerRadius: .mdShapeLarge))
            .contentShape(RoundedRectangle(cornerRadius: .mdShapeLarge))
        }
        .buttonStyle(.plain)
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
