import SwiftUI

/// Settings tab — Phase 5.4 redesign.
///
/// Vertical stack of three rows on the StellarGlassyBackground:
///   1. LCD on/off toggle (custom Button-based row, see iOS 18 note below).
///   2. ConnectionStatusRow — socket connection state + host:port.
///   3. DecodeErrorRow — surfaces the last socket decode error (hidden in
///      steady state).
///
/// The screen scope stays the same as before: this is the only Settings UI
/// the app exposes. See CLAUDE.md "Scope".
struct SettingsView: View {
    @Environment(LcdStore.self) private var lcd

    var body: some View {
        ZStack {
            StellarGlassyBackground()

            ScrollView {
                VStack(spacing: 12) {
                    lcdToggleRow
                    ConnectionStatusRow()
                    DecodeErrorRow()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        // Load-bearing: forces a fresh `getLcdStatus` emit whenever the
        // Settings tab appears, so the toggle reconciles against the Pi
        // after backgrounding / tab switches.
        .onAppear { lcd.refresh() }
    }

    // iOS 18.3 SwiftUI `Toggle("", isOn: Binding(get:set:)).labelsHidden()`
    // silently drops tap dispatch in certain HStack layouts (see commit
    // 1422f62). We keep the Button-wrapped row + custom Capsule+Circle
    // switch graphic forward into the new redesign visual rather than
    // re-introducing a native Toggle.
    private var lcdToggleRow: some View {
        Button {
            lcd.setOn(!lcd.isOn)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LCD screen")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(lcd.isOn ? "On" : "Standby")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Custom switch graphic — mimics native UIToggle visually.
                // Gold tint when on (the verbatim plan's `.tint(.gold)` on
                // the native Toggle lives in this Capsule fill instead).
                ZStack(alignment: lcd.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(lcd.isOn ? Stellar.Color.gold : Color.gray.opacity(0.35))
                        .frame(width: 51, height: 31)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 27, height: 27)
                        .padding(.horizontal, 2)
                        .shadow(radius: 1)
                }
                .animation(.easeInOut(duration: 0.15), value: lcd.isOn)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Stellar.Color.surfaceLow, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
