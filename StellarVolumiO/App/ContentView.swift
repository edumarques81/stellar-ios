import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(SocketService.self) private var socket
    @Environment(LcdStore.self) private var lcd
    @Environment(LcdViewStore.self) private var lcdView
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab: Tab = .player
    @State private var focusBackendInSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Sections the split view's detail column has built at least once.
    /// See `detailColumn`.
    @State private var mountedSections: Set<Tab> = []

    /// `.lcd` and `.vu` are action-only — they are never actually selected.
    /// See `tabSelection`.
    enum Tab { case player, library, lcd, vu, settings }

    /// Which navigation shell to build. The decision itself lives in
    /// `RootLayoutMode` (NAV-06) so it can be unit-tested without a window;
    /// this is the only place in the app that asks.
    private var layoutMode: RootLayoutMode {
        RootLayoutMode.resolve(horizontalSizeClass: horizontalSizeClass,
                               idiom: UIDevice.current.userInterfaceIdiom)
    }

    var body: some View {
        ZStack(alignment: .top) {
            switch layoutMode {
            case .tabs:    compactTabs
            case .sidebar: regularSidebar
            }

            // Connection-failure banner — appears only when the socket is
            // truly disconnected (post grace period) AND we have a captured
            // error to show. Non-blocking; sits above the safe area so it
            // doesn't fight the tab bar.
            if shouldShowFailureBanner {
                connectionFailureBanner
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowFailureBanner)
        // Ask the backend for the current LCD power state on launch so the
        // tab-bar item doesn't sit on LcdStore's optimistic `true` default
        // before the first `pushLcdStatus` arrives.
        .onAppear {
            lcd.refresh()
            lcdView.refresh()
        }
    }

    // MARK: - Compact width: the tab bar

    /// The shell the iPhone has always had. Moved into a property by the iPad
    /// port, not rewritten — REG-01 is that this branch stays byte-for-byte
    /// the app that shipped.
    private var compactTabs: some View {
        TabView(selection: tabSelection) {
            NowPlayingView()
                .tabItem { Label("Now Playing", systemImage: "music.note") }
                .tag(Tab.player)

            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(Tab.library)

            // Action-only tabs: never actually selected (see
            // `tabSelection`), they exist purely to render tappable
            // switches in the tab bar. The content is inert.
            //
            // The two are independent, which is why they are two items:
            // `.lcd` is whether the panel is lit, `.vu` is what is drawn
            // on it. The panel can be dark while parked on the VU meter.
            Color.clear
                .tabItem {
                    Label(
                        "LCD",
                        systemImage: lcd.isOn ? "display" : "display.slash"
                    )
                }
                .tag(Tab.lcd)

            Color.clear
                .tabItem {
                    Label(
                        "VU",
                        systemImage: lcdView.isShowingVuMeter ? "waveform" : "waveform.slash"
                    )
                }
                .tag(Tab.vu)

            SettingsView(focusBackendOnAppear: $focusBackendInSettings)
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .tint(Stellar.Color.gold)
    }

    // MARK: - Regular width: the sidebar

    /// The iPad shell: three real destinations plus the two display switches.
    ///
    /// The action-only-tab trick below has no sidebar equivalent — a `List`
    /// selection cannot decline to be selected — so LCD and VU become plain
    /// buttons here (NAV-03). Their icons still flip with live state exactly as
    /// the tab items do (NAV-04), which is the part the user actually reads.
    private var regularSidebar: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: sidebarSelection) {
                Section {
                    Label("Now Playing", systemImage: "music.note").tag(Tab.player)
                    Label("Library", systemImage: "square.stack").tag(Tab.library)
                    Label("Settings", systemImage: "gear").tag(Tab.settings)
                }

                // Untagged rows, so the list cannot select them: they act, they
                // don't navigate. Two rows because the two states are
                // independent — the panel can be dark while parked on the VU
                // meter.
                Section("Display") {
                    Button {
                        lcd.setOn(!lcd.isOn)
                    } label: {
                        Label("LCD", systemImage: lcd.isOn ? "display" : "display.slash")
                            .frame(maxWidth: .infinity,
                                   minHeight: Stellar.Metric.minTouchTarget,
                                   alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        lcdView.toggleVuMeter()
                    } label: {
                        Label(
                            "VU Meter",
                            systemImage: lcdView.isShowingVuMeter ? "waveform" : "waveform.slash"
                        )
                        .frame(maxWidth: .infinity,
                               minHeight: Stellar.Metric.minTouchTarget,
                               alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Stellar")
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Stellar.Color.gold)
    }

    /// Detail column: build a section on first visit, then keep it alive.
    ///
    /// Both halves of that matter, and both exist to match `TabView`, which
    /// creates a tab lazily and retains it afterwards.
    ///
    /// *Keep it alive* — a `switch` here would tear the outgoing section down
    /// on every sidebar tap, so the library would lose its scroll position, its
    /// Albums/Artists segment and any album drill-down each time the user
    /// glanced at Now Playing.
    ///
    /// *Build it lazily* — mounting all three up front fires
    /// `AlbumPickerView.onAppear` at launch, before the socket has connected.
    /// Its `store.load()` is emitted into a dead socket, dropped, and never
    /// retried, so the grid stays empty for the whole session. (That last
    /// weakness is the store's, not the port's — the same thing happens on the
    /// iPhone if Library is the section at launch — but eager mounting is what
    /// would have made it reachable in normal use here.)
    private var detailColumn: some View {
        ZStack {
            if mountedSections.contains(.player) {
                NowPlayingView()
                    .detailSection(visible: selectedTab == .player)
            }
            if mountedSections.contains(.library) {
                LibraryView()
                    .detailSection(visible: selectedTab == .library)
            }
            if mountedSections.contains(.settings) {
                SettingsView(focusBackendOnAppear: $focusBackendInSettings)
                    .detailSection(visible: selectedTab == .settings)
            }
        }
        .onAppear { mountedSections.insert(selectedTab) }
        .onChange(of: selectedTab) { _, section in
            mountedSections.insert(section)
        }
    }

    // MARK: - Selection

    /// Proxy binding that turns `.lcd` and `.vu` into buttons.
    ///
    /// SwiftUI writes the tapped tag through this binding's setter. For the
    /// action tags we perform the toggle and deliberately *don't* update
    /// `selectedTab`, so the getter still returns the previous tab and TabView
    /// snaps straight back — the user stays where they were and the panel
    /// changes in place.
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                switch newValue {
                case .lcd:
                    lcd.setOn(!lcd.isOn)
                case .vu:
                    lcdView.toggleVuMeter()
                default:
                    selectedTab = newValue
                }
            }
        )
    }

    /// `List` hands back `nil` when a tap clears the selection. Swallow it: an
    /// empty detail column is never a state the user asked for.
    ///
    /// Both shells write to the same `selectedTab`, which is what makes NAV-07
    /// true — a rotation or a Split View resize swaps the shell without
    /// resetting where the user was.
    private var sidebarSelection: Binding<Tab?> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                guard let newValue else { return }
                selectedTab = newValue
            }
        )
    }

    // MARK: - Failure banner

    /// True when the resolved (post-grace) state is .disconnected or .error
    /// AND we have a populated `lastConnectionError` to display.
    private var shouldShowFailureBanner: Bool {
        guard socket.lastConnectionError != nil else { return false }
        switch socket.reportedConnectionState {
        case .disconnected, .error: return true
        case .connected, .connecting: return false
        }
    }

    private var connectionFailureBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Stellar.Color.statusRed)
                Text("Can't reach backend")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            if let err = socket.lastConnectionError {
                Text(err)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Button {
                    socket.connect()
                } label: {
                    Text("Retry")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: Stellar.Metric.minTouchTarget * 0.65)
                        .background(Stellar.Color.gold, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)

                Button {
                    selectedTab = .settings
                    // Trigger the SettingsView ScrollViewReader to scroll
                    // to the Backend Server section on its next render.
                    focusBackendInSettings = true
                } label: {
                    Text("Server Settings")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: Stellar.Metric.minTouchTarget * 0.65)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Stellar.Color.gold, lineWidth: 1)
                        )
                        .foregroundStyle(Stellar.Color.gold)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Stellar.Color.statusRed.opacity(0.6), lineWidth: 1)
                )
        )
    }
}

private extension View {
    /// One section of the split view's detail column.
    ///
    /// Kept mounted so its state survives (see `detailColumn`), but invisible,
    /// untappable and skipped by VoiceOver when it isn't the current section.
    func detailSection(visible: Bool) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}
