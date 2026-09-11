import XCTest

/// Phase 5 parity sweep — every shipped capability, driven on an iPad.
///
/// The port did not touch a single feature; it changed the shell they sit in.
/// So what this sweep is actually asking is narrow and worth stating: does each
/// capability still *reach* the user when it is rendered inside a
/// `NavigationSplitView` detail column instead of a `TabView` page. Every
/// failure mode the port could introduce — a section that never mounts, a
/// drill-down that pushes onto the wrong stack, a control stranded outside the
/// visible detail area, a sheet that presents from a column instead of the
/// window — shows up as an element that cannot be found or cannot be tapped.
///
/// **These talk to the real backend and change the appliance's state.** They
/// are deliberately not in the `StellarVolumiO` scheme: `scripts/test.sh` stays
/// hermetic and fast. Run this suite explicitly, and only against a reachable
/// Pi:
///
///     xcodebuild test -scheme StellarVolumiOUITests -destination "id=<ipad-sim>"
///
/// Three safety rails, all of them added after the first run:
///
/// - **iPad only.** Every test below drives the sidebar. On an iPhone
///   simulator `app.buttons["LCD"]` matches the LCD *tab item* instead and the
///   run would still toggle the physical panel while asserting nothing about
///   the port. The whole class skips off-iPad.
/// - **Restores run in teardown, not in the test body.** `continueAfterFailure`
///   is false, so a mid-test failure aborts the method — anything restored on
///   the last line would never run, and the LCD or the transport would be left
///   flipped.
/// - **The queue-destroying test is opt-in.** `test05` replaces what is playing
///   and cannot put it back, so an absent-minded full-suite run cannot wipe the
///   queue: it runs only under `TEST_RUNNER_STELLAR_SWEEP_DESTRUCTIVE=1`
///   (xcodebuild forwards only `TEST_RUNNER_`-prefixed variables to the test
///   runner, stripping the prefix). Capture and restore around it:
///   `mpc --format "%file%" playlist` + `mpc status` before, then `mpc clear` →
///   re-add → `mpc play <n>` → `mpc seek <mm:ss>` after.
///
/// Method names are numbered because XCTest runs them alphabetically and the
/// cheap, non-destructive checks should fail first.
final class ParitySweepTests: XCTestCase {

    private static let timeout: TimeInterval = 20

    /// Set to "1" to allow `test05` to replace the MPD queue.
    ///
    /// `xcodebuild` does not hand its own environment to the UI-test runner —
    /// only variables prefixed `TEST_RUNNER_` are forwarded, with the prefix
    /// stripped. Both spellings are accepted so the flag works from the command
    /// line and from a scheme's environment list.
    private static let destructiveOptIn = "STELLAR_SWEEP_DESTRUCTIVE"

    private static var destructiveRunAllowed: Bool {
        let env = ProcessInfo.processInfo.environment
        return env[destructiveOptIn] == "1" || env["TEST_RUNNER_" + destructiveOptIn] == "1"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the parity sweep drives the iPad sidebar; on an iPhone its queries match tab items instead"
        )
    }

    /// Launches and waits until the socket has produced state — every
    /// assertion below is about live data, so a launch that has not connected
    /// yet is a false failure, not a finding.
    @discardableResult
    private func launch(file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: Self.timeout),
                      "app must reach the foreground", file: file, line: line)
        // The sidebar is the port's own surface: if it is not here, nothing
        // below is worth reporting.
        XCTAssertTrue(app.staticTexts["Now Playing"].waitForExistence(timeout: Self.timeout),
                      "sidebar must render", file: file, line: line)
        return app
    }

    private func select(_ section: String, in app: XCUIApplication) {
        tap(app.staticTexts[section], "sidebar row '\(section)'")
    }

    /// Wait, then assert hittable, then tap.
    ///
    /// `isHittable` does not wait: called on an element that has not resolved
    /// yet it returns false, and a bare `.tap()` on one raises a raw XCUI "no
    /// matches found" instead of the failure this suite is trying to report.
    /// Every tap below goes through here.
    private func tap(_ element: XCUIElement,
                     _ what: String,
                     file: StaticString = #filePath,
                     line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: Self.timeout),
                      "\(what) must exist", file: file, line: line)
        XCTAssertTrue(element.isHittable,
                      "\(what) must be tappable, not stranded", file: file, line: line)
        element.tap()
    }

    /// The transport row identifies its buttons by SF Symbol name. SwiftUI
    /// gives an `Image(systemName:)` button an accessibility *identifier* equal
    /// to the symbol, and `XCUIElementQuery`'s subscript matches identifier
    /// before label — so this keeps working even though `PlayPauseButton` sets
    /// `.accessibilityLabel("Pause")` over the top. (Verified in the hierarchy
    /// dump: `Button, identifier: 'pause.fill', label: 'Pause'`.)
    private func isPlaying(_ app: XCUIApplication) -> Bool {
        app.buttons["pause.fill"].exists
    }

    // MARK: - PARITY-04 / PARITY-07 — the two sidebar switches

    /// Flips a sidebar switch and registers a teardown that puts it back.
    ///
    /// The restore is a teardown block rather than a final tap because
    /// `continueAfterFailure` is false: a failed assertion between the two taps
    /// aborts the method, and a restore written inline would never run — the
    /// LCD panel would be left off, on real hardware, silently.
    private func assertSidebarSwitchToggles(button name: String,
                                            onIcon: String,
                                            offIcon: String,
                                            in app: XCUIApplication) {
        let button = app.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: Self.timeout),
                      "\(name) must be a button in the sidebar, not a destination")

        let wasOn = app.images[onIcon].exists
        XCTAssertTrue(wasOn || app.images[offIcon].exists,
                      "\(name) icon must reflect a known state")

        addTeardownBlock {
            let expected = wasOn ? onIcon : offIcon
            if !app.images[expected].exists {
                app.buttons[name].tap()
                _ = app.images[expected].waitForExistence(timeout: Self.timeout)
            }
        }

        tap(button, name)
        let flipped = wasOn ? app.images[offIcon] : app.images[onIcon]
        XCTAssertTrue(flipped.waitForExistence(timeout: Self.timeout),
                      "\(name) icon must follow the backend's new state")

        // Selection must not have moved — that is the whole point of NAV-03.
        XCTAssertTrue(app.buttons["pause.fill"].exists || app.buttons["play.fill"].exists,
                      "toggling \(name) must leave the detail column on Now Playing")
    }

    /// The port's riskiest single change: the phantom-tab trick could not
    /// survive into a `List`, so these became buttons. A button that navigates
    /// instead of acting would show up as a lost selection; one that does
    /// nothing would show up as an icon that never flips.
    func test01LcdToggleActsWithoutNavigating() {
        let app = launch()
        assertSidebarSwitchToggles(button: "LCD", onIcon: "display", offIcon: "display.slash", in: app)
    }

    func test02VuToggleActsWithoutNavigating() {
        let app = launch()
        assertSidebarSwitchToggles(button: "VU Meter", onIcon: "waveform", offIcon: "waveform.slash", in: app)
    }

    // MARK: - PARITY-05 — backend selection

    func test03BackendSelectionOpensBothRoutes() {
        let app = launch()
        select("Settings", in: app)

        let discover = app.buttons["Discover on Wi-Fi"]
        XCTAssertTrue(discover.waitForExistence(timeout: Self.timeout),
                      "Bonjour route must be reachable from the detail column")
        discover.tap()

        // The sheet is a form sheet on iPad — a separate presentation from the
        // split view, which is exactly the thing that could go wrong.
        let sheetTitle = app.navigationBars["Discover backend"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: Self.timeout),
                      "discovery sheet must present over the split view")
        tap(app.buttons["Done"].firstMatch, "the sheet's Done button")
        XCTAssertTrue(discover.waitForExistence(timeout: Self.timeout),
                      "dismissing the sheet must return to Settings, not a blank column")

        let manual = app.buttons["Manual entry"]
        // Collapse the disclosure again on the way out, whatever happens in
        // between — Settings state persists across launches.
        addTeardownBlock {
            if app.textFields.firstMatch.exists {
                app.buttons["Manual entry"].tap()
                XCTAssertFalse(app.textFields.firstMatch.waitForExistence(timeout: 2),
                               "manual entry must collapse again")
            }
        }
        tap(manual, "manual host/port route")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: Self.timeout),
                      "manual entry must expand into editable fields")
    }

    // MARK: - PARITY-08 — ingest

    func test04IngestSectionIsReachable() {
        let app = launch()
        select("Settings", in: app)

        XCTAssertTrue(app.staticTexts["Add music"].waitForExistence(timeout: Self.timeout),
                      "ingest section must render in the detail column")
        tap(app.buttons["Check inbox again"], "inbox re-check")
        XCTAssertTrue(app.staticTexts["Add music"].waitForExistence(timeout: Self.timeout),
                      "the section must survive a re-check")
    }

    // MARK: - PARITY-02 — album picker → tracks → play

    /// The one destructive test: Play Album replaces the queue, and nothing
    /// here can put the previous queue back. It exists because "the button is
    /// hittable" is not the claim worth making — the claim is that a tap inside
    /// the detail column reaches the backend and changes what is playing.
    ///
    /// Opt in with `STELLAR_SWEEP_DESTRUCTIVE=1`, after capturing the queue.
    func test05AlbumPickerDrillsDownAndPlays() throws {
        try XCTSkipUnless(
            Self.destructiveRunAllowed,
            "replaces the MPD queue — set TEST_RUNNER_\(Self.destructiveOptIn)=1 to run, after capturing it with `mpc`"
        )

        let app = launch()
        select("Library", in: app)

        tap(app.buttons["Albums"], "library Albums segment")

        let grid = app.scrollViews["album-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: Self.timeout), "album grid must render")

        // Whichever album the library sorts first, so the test does not depend
        // on the user's collection.
        tap(grid.buttons.firstMatch, "the first album tile")

        // Read the title from the tracks screen rather than parsing the tile's
        // "<title>, <artist>" label — a title containing a comma would be
        // truncated, and several in this library do.
        let heading = app.staticTexts["album-tracks-title"]
        XCTAssertTrue(heading.waitForExistence(timeout: Self.timeout),
                      "album tracks screen must push inside the detail column, not the sidebar")
        let title = heading.label

        tap(app.buttons["Play Album"], "the Play Album CTA")

        select("Now Playing", in: app)
        let nowPlayingAlbum = app.staticTexts["now-playing-album"]
        XCTAssertTrue(nowPlayingAlbum.waitForExistence(timeout: Self.timeout),
                      "Now Playing must render an album line")
        expectation(for: NSPredicate(format: "label == %@", title),
                    evaluatedWith: nowPlayingAlbum, handler: nil)
        waitForExpectations(timeout: Self.timeout)
    }

    // MARK: - PARITY-03 — artist picker → albums → tracks

    func test06ArtistPickerDrillsDown() {
        let app = launch()
        select("Library", in: app)

        tap(app.buttons["Artists"], "library Artists segment")

        // Scoped by identifier: the sidebar is a collection view too, and an
        // index-based lookup finds it first.
        let artistList = app.collectionViews["artist-list"]
        XCTAssertTrue(artistList.waitForExistence(timeout: Self.timeout), "artist list must render")
        tap(artistList.cells.firstMatch, "the first artist row")

        // The artist's albums use the same tile as the album grid, and tapping
        // one must reach the same tracks screen — two pushes deep inside the
        // detail column, which is where a split view most easily goes wrong.
        let albumGrid = app.scrollViews["artist-album-grid"]
        XCTAssertTrue(albumGrid.waitForExistence(timeout: Self.timeout),
                      "artist detail must list that artist's albums")
        tap(albumGrid.buttons.firstMatch, "the artist's first album tile")

        XCTAssertTrue(app.staticTexts["album-tracks-title"].waitForExistence(timeout: Self.timeout),
                      "artist → album → tracks must land on the tracks screen")
        XCTAssertTrue(app.buttons["Play Album"].exists,
                      "the tracks screen reached via Artists must carry the same CTA")

        // `LibraryView` keeps its own `NavigationStack` inside the split view's
        // detail column, which Apple documents as unsupported nesting and which
        // classically shows up as two stacked bars in the detail column. It
        // does not happen here: two bars exist in the window and they are the
        // sidebar's and the detail's, one each. Pinned so that if a future
        // SwiftUI release does start stacking them, this fails instead of
        // shipping.
        XCTAssertEqual(app.navigationBars.count, 2,
                       "expected exactly the sidebar bar and the detail bar, got: "
                       + (0..<app.navigationBars.count)
                            .map { app.navigationBars.element(boundBy: $0).identifier }
                            .joined(separator: " | "))
        XCTAssertTrue(app.navigationBars["Stellar"].exists, "the sidebar keeps its own bar")
    }

    // MARK: - PARITY-01 — transport

    /// Runs last: it is the only capability whose evidence is a change in
    /// playback, so leaving it until the navigation tests have passed keeps a
    /// failure elsewhere from being reported as a transport problem.
    ///
    /// Everything here stays inside the current queue — pause/play, next,
    /// previous, seek — and every one of them is undone in teardown so an
    /// aborted run does not leave the appliance paused mid-track.
    func test07TransportControlsDriveThePlayer() {
        let app = launch()

        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: Self.timeout),
                      "seek slider must render on the iPad canvas")

        for (symbol, what) in [("backward.fill", "previous"), ("forward.fill", "next")] {
            let button = app.buttons[symbol]
            XCTAssertTrue(button.waitForExistence(timeout: Self.timeout), "\(what) must render")
            XCTAssertTrue(button.isHittable, "\(what) must be reachable")
        }

        let startedPlaying = isPlaying(app)
        let clock = app.staticTexts["elapsed-time"]
        XCTAssertTrue(clock.waitForExistence(timeout: Self.timeout), "elapsed time must render")
        let startedAt = clock.label
        let startedOn = app.staticTexts["now-playing-title"].label

        addTeardownBlock {
            // Track, then position, then transport state — in that order,
            // because a track change resets the position.
            let title = app.staticTexts["now-playing-title"]
            if title.label != startedOn {
                app.buttons["backward.fill"].tap()
                _ = title.waitForExistence(timeout: Self.timeout)
            }
            if let seconds = Self.seconds(from: startedAt),
               let total = Self.seconds(from: app.staticTexts["total-time"].label),
               total > 0 {
                app.sliders.firstMatch.adjust(toNormalizedSliderPosition: seconds / total)
            }
            if app.buttons["pause.fill"].exists != startedPlaying {
                app.buttons[startedPlaying ? "play.fill" : "pause.fill"].tap()
            }
        }

        // Play/pause round trip.
        tap(app.buttons[startedPlaying ? "pause.fill" : "play.fill"], "play/pause")
        let opposite = app.buttons[startedPlaying ? "play.fill" : "pause.fill"]
        XCTAssertTrue(opposite.waitForExistence(timeout: Self.timeout),
                      "play/pause must reach the backend and come back changed")
        tap(opposite, "play/pause, on the way back")
        XCTAssertTrue(app.buttons[startedPlaying ? "pause.fill" : "play.fill"]
                        .waitForExistence(timeout: Self.timeout),
                      "play/pause must return to the state it started in")

        // Next / previous, inside the current queue.
        let titleLabel = app.staticTexts["now-playing-title"]
        tap(app.buttons["forward.fill"], "next")
        expectation(for: NSPredicate(format: "label != %@", startedOn),
                    evaluatedWith: titleLabel, handler: nil)
        waitForExpectations(timeout: Self.timeout)

        tap(app.buttons["backward.fill"], "previous")
        expectation(for: NSPredicate(format: "label == %@", startedOn),
                    evaluatedWith: titleLabel, handler: nil)
        waitForExpectations(timeout: Self.timeout)

        // Seek. The elapsed label is the observable half; the slider is the
        // control. Moving the control must move the label.
        let elapsedBefore = clock.label
        slider.adjust(toNormalizedSliderPosition: 0.6)
        expectation(for: NSPredicate(format: "label != %@", elapsedBefore),
                    evaluatedWith: clock, handler: nil)
        waitForExpectations(timeout: Self.timeout)
    }

    /// "m:ss" → seconds. Returns nil on anything else so teardown can skip the
    /// restore rather than seek to a garbage position.
    private static func seconds(from label: String) -> Double? {
        let parts = label.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let secs = Double(parts[1]) else { return nil }
        return minutes * 60 + secs
    }

    // MARK: - NAV-07 / BUILD-04 — rotation

    /// Rotation is the one multitasking event the simulator can actually be
    /// made to perform, and it is the event the port is most exposed to: the
    /// shell is chosen from the horizontal size class, so a rotation that
    /// crossed a size-class boundary would rebuild the root. On iPad both
    /// orientations are regular width, so the sidebar must survive — and the
    /// section the user was on must survive with it, because both shells write
    /// the same `selectedTab`.
    ///
    /// Split View and Stage Manager cannot be driven from here; they are the
    /// human pass in Phase 6.
    func test08RotationKeepsShellAndSelection() {
        let app = launch()
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }

        select("Settings", in: app)
        XCTAssertTrue(app.buttons["Discover on Wi-Fi"].waitForExistence(timeout: Self.timeout),
                      "Settings must be the section before rotating")

        XCUIDevice.shared.orientation = .landscapeLeft

        XCTAssertTrue(app.staticTexts["Now Playing"].waitForExistence(timeout: Self.timeout),
                      "sidebar must survive rotation — landscape is still regular width")
        XCTAssertTrue(app.buttons["Discover on Wi-Fi"].waitForExistence(timeout: Self.timeout),
                      "rotation must not reset the detail column to the first section")

        XCUIDevice.shared.orientation = .portrait

        XCTAssertTrue(app.buttons["Discover on Wi-Fi"].waitForExistence(timeout: Self.timeout),
                      "rotating back must still not reset the section")
        XCTAssertTrue(app.staticTexts["Now Playing"].exists,
                      "sidebar must survive the return to portrait")
    }
}
