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
/// **These talk to the real backend.** They are deliberately not in the
/// `StellarVolumiO` scheme: `scripts/test.sh` stays hermetic and fast. Run this
/// suite explicitly, and only against a reachable Pi:
///
///     xcodebuild test -scheme StellarVolumiOUITests -destination "id=<ipad-sim>"
///
/// Playback-affecting steps stay inside the current queue (pause/play, next,
/// previous, seek) except `test05` which deliberately replaces it — see the
/// note there. Restore the Pi afterwards if you care about what was playing.
///
/// Method names are numbered because XCTest runs them alphabetically and the
/// cheap, non-destructive checks should fail first.
final class ParitySweepTests: XCTestCase {

    private static let timeout: TimeInterval = 20

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
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
        let row = app.staticTexts[section]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "sidebar row '\(section)' must exist")
        row.tap()
    }

    /// The transport row identifies its buttons by SF Symbol name, which is
    /// also how the play/pause state is readable from outside.
    private func isPlaying(_ app: XCUIApplication) -> Bool {
        app.buttons["pause.fill"].exists
    }

    // MARK: - PARITY-04 / PARITY-07 — the two sidebar switches

    /// The port's riskiest single change: the phantom-tab trick could not
    /// survive into a `List`, so these became buttons. A button that navigates
    /// instead of acting would show up as a lost selection; one that does
    /// nothing would show up as an icon that never flips.
    func test01LcdToggleActsWithoutNavigating() {
        let app = launch()

        let lcd = app.buttons["LCD"]
        XCTAssertTrue(lcd.exists, "LCD must be a button in the sidebar, not a destination")

        let wasOn = app.images["display"].exists
        XCTAssertTrue(wasOn || app.images["display.slash"].exists,
                      "LCD icon must reflect a known state")

        lcd.tap()
        let flipped = wasOn ? app.images["display.slash"] : app.images["display"]
        XCTAssertTrue(flipped.waitForExistence(timeout: Self.timeout),
                      "LCD icon must follow the backend's new state")

        // Selection must not have moved — that is the whole point of NAV-03.
        XCTAssertTrue(app.buttons["pause.fill"].exists || app.buttons["play.fill"].exists,
                      "toggling LCD must leave the detail column on Now Playing")

        lcd.tap()
        let restored = wasOn ? app.images["display"] : app.images["display.slash"]
        XCTAssertTrue(restored.waitForExistence(timeout: Self.timeout),
                      "LCD must return to the state it started in")
    }

    func test02VuToggleActsWithoutNavigating() {
        let app = launch()

        let vu = app.buttons["VU Meter"]
        XCTAssertTrue(vu.exists, "VU Meter must be a button in the sidebar")

        let wasOn = app.images["waveform"].exists
        XCTAssertTrue(wasOn || app.images["waveform.slash"].exists,
                      "VU icon must reflect a known state")

        vu.tap()
        let flipped = wasOn ? app.images["waveform.slash"] : app.images["waveform"]
        XCTAssertTrue(flipped.waitForExistence(timeout: Self.timeout),
                      "VU icon must follow the backend's new state")

        XCTAssertTrue(app.buttons["pause.fill"].exists || app.buttons["play.fill"].exists,
                      "toggling the VU meter must leave the detail column on Now Playing")

        vu.tap()
        let restored = wasOn ? app.images["waveform"] : app.images["waveform.slash"]
        XCTAssertTrue(restored.waitForExistence(timeout: Self.timeout),
                      "VU meter must return to the state it started in")
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
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(discover.waitForExistence(timeout: Self.timeout),
                      "dismissing the sheet must return to Settings, not a blank column")

        let manual = app.buttons["Manual entry"]
        XCTAssertTrue(manual.exists, "manual host/port route must be reachable")
        manual.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: Self.timeout),
                      "manual entry must expand into editable fields")
        manual.tap()
    }

    // MARK: - PARITY-08 — ingest

    func test04IngestSectionIsReachable() {
        let app = launch()
        select("Settings", in: app)

        XCTAssertTrue(app.staticTexts["Add music"].waitForExistence(timeout: Self.timeout),
                      "ingest section must render in the detail column")
        let recheck = app.buttons["Check inbox again"]
        XCTAssertTrue(recheck.exists, "inbox re-check must be reachable")
        XCTAssertTrue(recheck.isHittable, "inbox re-check must be tappable, not stranded")
        recheck.tap()
        XCTAssertTrue(app.staticTexts["Add music"].waitForExistence(timeout: Self.timeout),
                      "the section must survive a re-check")
    }

    // MARK: - PARITY-02 — album picker → tracks → play

    /// The one destructive test: Play Album replaces the queue. It is here
    /// because "the button is hittable" is not the claim worth making — the
    /// claim is that a tap inside the detail column reaches the backend and
    /// changes what is playing.
    func test05AlbumPickerDrillsDownAndPlays() {
        let app = launch()
        select("Library", in: app)

        XCTAssertTrue(app.buttons["Albums"].waitForExistence(timeout: Self.timeout),
                      "library segment control must render")
        app.buttons["Albums"].tap()

        let grid = app.scrollViews.element(boundBy: 1)
        XCTAssertTrue(grid.waitForExistence(timeout: Self.timeout), "album grid must render")

        // Albums are buttons labelled "<title>, <artist>". Take whichever the
        // library happens to sort first so the test does not depend on the
        // user's collection.
        let album = grid.buttons.element(boundBy: 0)
        XCTAssertTrue(album.waitForExistence(timeout: Self.timeout), "at least one album must load")
        let albumLabel = album.label
        album.tap()

        let playAlbum = app.buttons["Play Album"]
        XCTAssertTrue(playAlbum.waitForExistence(timeout: Self.timeout),
                      "album tracks screen must push inside the detail column, not the sidebar")
        XCTAssertTrue(playAlbum.isHittable, "Play Album must be reachable on a wide canvas")

        playAlbum.tap()

        select("Now Playing", in: app)
        // The album label starts with the title; the Now Playing screen shows
        // that same title under the track name.
        let title = String(albumLabel.split(separator: ",").first ?? "")
        let shown = app.staticTexts[title]
        XCTAssertTrue(shown.waitForExistence(timeout: Self.timeout),
                      "Play Album must change what is playing to '\(title)'")
    }

    // MARK: - PARITY-03 — artist picker → albums → tracks

    func test06ArtistPickerDrillsDown() {
        let app = launch()
        select("Library", in: app)

        let artists = app.buttons["Artists"]
        XCTAssertTrue(artists.waitForExistence(timeout: Self.timeout), "Artists segment must exist")
        artists.tap()

        // Scope past the sidebar: it is a collection view too, and its rows
        // would otherwise satisfy every "first row" query in this test.
        let artistList = app.collectionViews.matching(
            NSPredicate(format: "label != %@", "Sidebar")).element(boundBy: 0)
        XCTAssertTrue(artistList.waitForExistence(timeout: Self.timeout), "artist list must render")
        let artistRow = artistList.cells.element(boundBy: 0)
        XCTAssertTrue(artistRow.waitForExistence(timeout: Self.timeout), "artist list must load")
        artistRow.tap()

        // The artist's albums use the same tile as the album grid, and tapping
        // one must reach the same tracks screen — two pushes deep inside the
        // detail column, which is where a split view most easily goes wrong.
        let albumTile = app.scrollViews.buttons.element(boundBy: 0)
        XCTAssertTrue(albumTile.waitForExistence(timeout: Self.timeout),
                      "artist detail must list that artist's albums")
        albumTile.tap()

        XCTAssertTrue(app.buttons["Play Album"].waitForExistence(timeout: Self.timeout),
                      "artist → album → tracks must land on the tracks screen")
    }

    // MARK: - PARITY-01 — transport

    /// Runs last: it is the only capability whose evidence is a change in
    /// playback, so leaving it until the navigation tests have passed keeps a
    /// failure elsewhere from being reported as a transport problem.
    func test07TransportControlsDriveThePlayer() {
        let app = launch()

        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: Self.timeout),
                      "seek slider must render on the iPad canvas")

        XCTAssertTrue(app.buttons["backward.fill"].isHittable, "previous must be reachable")
        XCTAssertTrue(app.buttons["forward.fill"].isHittable, "next must be reachable")

        // Play/pause round trip.
        let startedPlaying = isPlaying(app)
        let toggle = app.buttons[startedPlaying ? "pause.fill" : "play.fill"]
        XCTAssertTrue(toggle.isHittable, "play/pause must be reachable")
        toggle.tap()
        let opposite = app.buttons[startedPlaying ? "play.fill" : "pause.fill"]
        XCTAssertTrue(opposite.waitForExistence(timeout: Self.timeout),
                      "play/pause must reach the backend and come back changed")
        opposite.tap()
        XCTAssertTrue(app.buttons[startedPlaying ? "pause.fill" : "play.fill"]
                        .waitForExistence(timeout: Self.timeout),
                      "play/pause must return to the state it started in")

        // Next / previous, inside the current queue. Scope to the detail
        // column's scroll view: `app.staticTexts` would start at the sidebar.
        let detail = app.scrollViews.firstMatch
        let titleLabel = detail.staticTexts.element(boundBy: 0)
        let firstTrack = titleLabel.label
        app.buttons["forward.fill"].tap()
        expectation(for: NSPredicate(format: "label != %@", firstTrack),
                    evaluatedWith: titleLabel, handler: nil)
        waitForExpectations(timeout: Self.timeout)

        app.buttons["backward.fill"].tap()
        expectation(for: NSPredicate(format: "label == %@", firstTrack),
                    evaluatedWith: titleLabel, handler: nil)
        waitForExpectations(timeout: Self.timeout)

        // Seek. The elapsed label is the observable half; the slider is the
        // control. Moving the control must move the label. Matched by shape
        // rather than by index so an absent format strip cannot shift it.
        let clock = detail.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+:[0-9]{2}")).element(boundBy: 0)
        XCTAssertTrue(clock.waitForExistence(timeout: Self.timeout), "elapsed time must render")
        let elapsedBefore = clock.label
        slider.adjust(toNormalizedSliderPosition: 0.6)
        expectation(for: NSPredicate(format: "label != %@", elapsedBefore),
                    evaluatedWith: clock, handler: nil)
        waitForExpectations(timeout: Self.timeout)
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
