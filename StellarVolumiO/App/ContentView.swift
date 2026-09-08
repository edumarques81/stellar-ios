import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(SocketService.self) private var socket
    @Environment(LcdStore.self) private var lcd
    @Environment(LcdViewStore.self) private var lcdView
    // Read only by `sectionBecameVisible` — see the note there on why the
    // sidebar shell has to drive these by hand.
    @Environment(IngestStore.self) private var ingest
    @Environment(AlbumPickerStore.self) private var albums
    @Environment(ArtistPickerStore.self) private var artists
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.stellarIdiom) private var idiom

    @State private var selectedTab: Tab = .player
    @State private var focusBackendInSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Sections the split view's detail column has built at least once.
    /// See `detailColumn`.
    @State private var mountedSections: Set<Tab> = []
    /// Bumped to force the sidebar `List` to rebuild when it clears its own
    /// selection. See `sidebarSelection`.
    @State private var sidebarNonce = 0

    /// `.lcd` and `.vu` are action-only — they are never actually selected.
    /// See `tabSelection`.
    enum Tab { case player, library, lcd, vu, settings }

    /// Which navigation shell to build. The decision itself lives in
    /// `RootLayoutMode` (NAV-06) so it can be unit-tested without a window;
    /// this is the only place in the app that asks.
    private var layoutMode: RootLayoutMode {
        RootLayoutMode.resolve(horizontalSizeClass: horizontalSizeClass,
                               idiom: idiom)
    }

    /// The section the detail column should be showing.
    ///
    /// `Tab` carries two action tags that are never navigated to, and both
    /// selection bindings intercept them. Mapping them here rather than relying
    /// on that makes the detail column total: there is no value of
    /// `selectedTab` that renders an empty column.
    private var visibleSection: Tab {
        switch selectedTab {
        case .lcd, .vu: return .player
        case .player, .library, .settings: return selectedTab
        }
    }

    var body: some View {
        Group {
            switch layoutMode {
            case .tabs:
                // The banner sits above the whole window here, which is what
                // the phone shipped with.
                ZStack(alignment: .top) {
                    compactTabs
                    failureBannerIfNeeded
                }
            case .sidebar:
                // In the sidebar shell a full-width banner would sit on top of
                // the top sidebar rows — including Settings, which is where the
                // banner's own "Server Settings" button sends the user. It goes
                // inside the detail column instead (see `detailColumn`).
                regularSidebar
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

    /// The connection-failure banner — non-blocking, and only once the socket
    /// is truly disconnected (post grace period) with a captured error to show.
    @ViewBuilder
    private var failureBannerIfNeeded: some View {
        if shouldShowFailureBanner {
            connectionFailureBanner
                .padding(.horizontal, 12)
                .padding(.top, 4)
                // Capped like every other surface Phase 4 capped — stretched
                // across a 1046pt detail column the banner reads as a wall of
                // text rather than a notice.
                .frame(maxWidth: Stellar.Metric.contentMaxWidth)
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .top).combined(with: .opacity))
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

    /// A selectable sidebar row. Pins the same 44pt minimum the two Display
    /// buttons pin explicitly — `List` almost certainly clears it on its own,
    /// but having three of the five rows rely on that and two not is how a
    /// later style change drops below it on only some of them.
    private func sidebarRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .frame(minHeight: Stellar.Metric.minTouchTarget, alignment: .leading)
    }

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
                    sidebarRow("Now Playing", icon: "music.note").tag(Tab.player)
                    sidebarRow("Library", icon: "square.stack").tag(Tab.library)
                    sidebarRow("Settings", icon: "gear").tag(Tab.settings)
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
                    // The icon carries the state visually; without this
                    // VoiceOver announces only "LCD, button" and the user
                    // cannot tell what a tap will do. `SettingsView`'s own LCD
                    // row already gets this right.
                    .accessibilityValue(lcd.isOn ? "On" : "Off")
                    .accessibilityHint(lcd.isOn ? "Turns the panel off" : "Turns the panel on")

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
                    .accessibilityValue(lcdView.isShowingVuMeter ? "Showing" : "Hidden")
                    .accessibilityHint(lcdView.isShowingVuMeter
                                       ? "Returns the panel to Now Playing"
                                       : "Shows the VU meter on the panel")
                }
            }
            .listStyle(.sidebar)
            // Rebuilt when the list clears its own selection — see
            // `sidebarSelection`.
            .id(sidebarNonce)
            .navigationTitle("Stellar")
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Stellar.Color.gold)
        // A Slide Over round trip collapses the sidebar and there is no other
        // surface exposing the sections, so coming back to a roomy canvas has
        // to put it back — otherwise the app returns with a detail column and
        // no way to leave it.
        .onChange(of: layoutMode) { _, mode in
            if mode == .sidebar { columnVisibility = .all }
        }
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
    /// retried, so the grid stays empty for the whole session.
    ///
    /// What retention does *not* reproduce is `TabView`'s third property: it
    /// re-fires `onAppear` every time a tab is re-selected. A retained view is
    /// never re-inserted, so its `onAppear` runs exactly once per launch. Three
    /// sections depend on that re-fire — `SettingsView` calls its own refresh
    /// "load-bearing" — so `sectionBecameVisible` drives them explicitly.
    private var detailColumn: some View {
        ZStack(alignment: .top) {
            ZStack {
                if mountedSections.contains(.player) {
                    NowPlayingView()
                        .detailSection(visible: visibleSection == .player)
                }
                if mountedSections.contains(.library) {
                    LibraryView()
                        .detailSection(visible: visibleSection == .library)
                }
                if mountedSections.contains(.settings) {
                    SettingsView(focusBackendOnAppear: $focusBackendInSettings)
                        .detailSection(visible: visibleSection == .settings)
                }
            }
            failureBannerIfNeeded
        }
        .onAppear { mountedSections.insert(visibleSection) }
        .onChange(of: visibleSection) { _, section in
            // Insert here as well as in the selection setter: the setter covers
            // taps, this covers any other route into a section (the failure
            // banner's "Server Settings" button, for one).
            mountedSections.insert(section)
            sectionBecameVisible(section)
        }
        // A Slide Over or Stage Manager resize takes the app regular →
        // compact → regular. On the way back `detailColumn` is rebuilt, and a
        // `mountedSections` carried across would mount every previously-visited
        // section at once — the eager mount this whole mechanism exists to
        // avoid. Start again from whatever is actually on screen.
        .onChange(of: layoutMode) { _, _ in
            mountedSections = [visibleSection]
        }
    }

    /// The work a section's `onAppear` would do if the section were being
    /// inserted rather than revealed.
    ///
    /// This duplicates three call sites, which is worth stating plainly: the
    /// alternative is re-inserting the view, and re-insertion is exactly what
    /// destroys the scroll position and drill-down state that retention exists
    /// to keep. The duplication is small, and each line below has a comment in
    /// the view it mirrors.
    ///
    /// It is only reachable from the sidebar shell. The `TabView` branch gets
    /// the real thing from SwiftUI.
    private func sectionBecameVisible(_ section: Tab) {
        switch section {
        case .player:
            // Mirrors NowPlayingView.onAppear: an AirPlay session can start,
            // end or change track while the user is elsewhere in the app.
            socket.requestAirplayState()
        case .settings:
            // Mirrors SettingsView.onAppear. `ingest.requestStatus()` is the
            // only thing that ever sets `IngestStore.isAvailable`, and the
            // whole ingest card renders behind it — lose the one emit and the
            // capability is invisible for the rest of the session.
            lcd.refresh()
            ingest.requestStatus()
        case .library:
            // Mirrors the load-if-empty guards in AlbumPickerView and
            // ArtistPickerView, which are the only retry either store gets.
            if albums.albums.isEmpty && !albums.loading { albums.load() }
            if artists.artists.isEmpty && !artists.loading { artists.load() }
        case .lcd, .vu:
            break   // never a visible section — see `visibleSection`.
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
            get: { visibleSection },
            set: { newValue in
                guard let newValue else {
                    // The list has already dropped its own highlight by the
                    // time this arrives, and re-returning the same value from
                    // the getter will not bring it back — nothing changed, so
                    // nothing re-renders. Rebuild the list instead, which is
                    // cheap for five rows and leaves highlight and detail
                    // agreeing again.
                    sidebarNonce += 1
                    return
                }
                // Mount before selecting, so the section is present in the same
                // render pass that reveals it rather than one frame later.
                mountedSections.insert(newValue)
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
