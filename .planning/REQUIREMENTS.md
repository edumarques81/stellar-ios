# Requirements: Stellar Remote — iPad Port

**Defined:** 2026-09-09
**Core Value:** The iPhone app must not regress.

## v1 Requirements

### Build & platform (BUILD)

- [x] **BUILD-01**: `TARGETED_DEVICE_FAMILY` is `"1,2"`; the app installs and launches on an iPad simulator.
- [x] **BUILD-02**: `UIRequiresFullScreen` is removed from `project.yml`.
- [x] **BUILD-03**: `UISupportedInterfaceOrientations` covers portrait, portrait-upside-down, landscape-left and landscape-right on iPad; the iPhone remains portrait-only.
- [ ] **BUILD-04**: The app participates in Split View and Stage Manager without crashing, blanking, or losing socket connection. *(Rotation is verified on the simulator by `ParitySweepTests.test08`; Split View and Stage Manager cannot be driven there, so the remaining half moves to DEVICE-02.)*
- [x] **BUILD-05**: `xcodegen generate --spec project.yml` regenerates cleanly and the build emits **zero** warnings.

### Navigation (NAV)

- [x] **NAV-01**: On a regular-width horizontal size class the root is a `NavigationSplitView` with a sidebar; on compact it is the existing `TabView`, unchanged.
- [x] **NAV-02**: The sidebar lists Now Playing, Library and Settings as selectable destinations.
- [x] **NAV-03**: LCD power and VU meter are **toggle controls** in the sidebar, not navigation destinations — the phantom-tab trick is not carried over.
- [x] **NAV-04**: Their icons reflect live state (`display`/`display.slash`, `waveform`/`waveform.slash`) exactly as the tab bar does today.
- [x] **NAV-05**: Library drill-down (album → tracks, artist → albums → tracks) works in the detail pane and the back affordance behaves correctly.
- [x] **NAV-06**: The layout decision is made by a pure, unit-testable type — not by scattered `if horizontalSizeClass == …` checks in views.
- [x] **NAV-07**: Sidebar selection survives rotation and Split View resize without resetting to the first item.

### Layout (LAYOUT)

- [x] **LAYOUT-01**: No screen has clipped, overlapped, or stranded content between 320 pt and 1366 pt of width.
- [x] **LAYOUT-02**: Now Playing artwork, the play disc and the AirPlay badge scale sensibly on a large canvas instead of sitting at phone-fixed sizes.
- [x] **LAYOUT-03**: Album and artist grids gain columns on iPad (already `GridItem(.adaptive)`; verify, don't rebuild).
- [x] **LAYOUT-04**: `AlbumTracksView`'s 240×240 hero and `AirplaySourceBadge`'s 240 pt width adapt to available width.
- [x] **LAYOUT-05**: `StellarGlassyBackground`'s radial gradients scale with the canvas rather than using an absolute 280 pt radius.
- [x] **LAYOUT-06**: All touch targets remain ≥ 44×44 pt.
- [x] **LAYOUT-07**: Sheets (`BackendDiscoverySheet`, `IngestSheet`) present appropriately on a large canvas.

### Feature parity (PARITY)

Every shipped capability must work on iPad. Note this is **eight** capabilities,
not the six in the app's stated scope — see `.planning/codebase/CONCERNS.md` §7.

- [x] **PARITY-01**: Transport — play/pause, next/prev, seek.
- [x] **PARITY-02**: Album picker → Album Tracks, including Play Album and per-track play.
- [x] **PARITY-03**: Artist picker → artist albums → Album Tracks.
- [x] **PARITY-04**: LCD on/off toggle.
- [x] **PARITY-05**: Backend server selection — Bonjour discovery sheet and manual host/port.
- [x] **PARITY-06**: AirPlay source mode, with seek and format strip suppressed. *(Branch verified by `AirplayLayoutRenderTests` at every iPad canvas plus the suppression contract; a live session needs a real sender, so end-to-end AirPlay moves to DEVICE-02.)*
- [x] **PARITY-07**: VU meter view toggle.
- [x] **PARITY-08**: Ingest / "Import from inbox" sheet.

### Regression safety (REG)

- [x] **REG-01**: The full existing suite (205 tests) passes on the iPhone simulator.
- [x] **REG-02**: The full suite passes on the iPad primary and iPad small simulators.
- [x] **REG-03**: The iPhone renders the same `TabView` hierarchy as before, verified by test, not by eye.
- [x] **REG-04**: No change to the Socket.IO wire contract; `SocketEmitArgumentShapeTests` still passes unmodified.
- [x] **REG-05**: `setVolume` / `toggleMute` remain present and uncalled.

### On-device (DEVICE)

- [x] **DEVICE-01**: `scripts/deploy-to-device.sh` installs and launches on a physical iPad. *(Eduardo's iPad, iPad12,1 / iPadOS 26.6.1, 2026-09-11. Needed Developer Mode enabled on the device and a script fix so a never-before-seen device gets registered — see the `-allowProvisioningDeviceRegistration` commit.)*
- [ ] **DEVICE-02**: Manual pass of all eight capabilities on real hardware, both orientations, plus a Split View and a Stage Manager check.

## v2 Requirements

Tracked, not in this roadmap.

- **V2-01**: Annotate stores `@MainActor` so main-confinement is compiler-enforced.
- **V2-02**: Add a UI test target for real layout regression coverage.
- **V2-03**: Resolve the six-vs-eight feature-scope drift deliberately.
- **V2-04**: Keyboard shortcuts / pointer interactions for iPad.
- **V2-05**: Revisit volume control, if the user chooses to.

## Out of Scope

| Feature | Reason |
|---|---|
| New app features | The port adds nothing the iPhone lacks. |
| Volume control UI | Bit-perfect audio path; explicit user decision. |
| macOS / Catalyst / visionOS | iPad only. |
| Backend or Volumio2-UI changes | Single-repo port; wire contract untouched. |
| Redesigning ingest or the VU toggle | Ported as-is; drift noted, not fixed here. |
| Raising the iOS deployment target | `NavigationSplitView` is iOS 16+; 17.0 is fine. |

## Traceability

| Requirement | Phase | Status |
|---|---|---|
| BUILD-01, 02, 03, 05 | Phase 1 | Complete |
| BUILD-04 | Phase 1 / Phase 6 | Rotation complete; Split View + Stage Manager deferred to DEVICE-02 |
| REG-01, REG-03 | Phase 1 | Complete |
| NAV-06 | Phase 2 | Complete |
| NAV-01, NAV-02, NAV-07 | Phase 3 | Complete |
| NAV-03, NAV-04, NAV-05 | Phase 3 | Complete |
| LAYOUT-01…07 | Phase 4 | Complete |
| PARITY-01…05, 07, 08 | Phase 5 | Complete |
| PARITY-06 | Phase 5 / Phase 6 | Branch complete; live session deferred to DEVICE-02 |
| REG-02, REG-04, REG-05 | Phase 5 | Complete |
| DEVICE-01 | Phase 6 | Done — installs and launches on iPad12,1 |
| DEVICE-02 | Phase 6 | Pending — manual pass on the iPad |
