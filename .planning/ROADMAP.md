# Roadmap: Stellar Remote — iPad Port

**Branch:** `feature/ipad-port` (all six phases land here; one merge to `main` at the end)
**Granularity:** standard · **Execution:** sequential · TDD required · code review per phase

Each phase ends with: tests green on all three simulators → zero-warning build →
code review → conventional commit → **push**.

---

## Phase 1 — Make it an iPad app at all

**Goal:** the existing app, unchanged in structure, builds and runs on iPad in
every orientation and participates in multitasking.

- `project.yml`: `TARGETED_DEVICE_FAMILY: "1,2"`, drop `UIRequiresFullScreen`,
  add iPad orientations while keeping the iPhone portrait-only.
- Regenerate, build, launch on the iPad primary simulator.
- Add a regression test that pins the iPhone root hierarchy so later phases
  cannot silently change it.

**Covers:** BUILD-01…05, REG-01, REG-03
**Done when:** app launches on iPad, rotates, and survives a Split View resize.
It will look like a stretched iPhone app — that is expected at this stage.
**Risk:** low. Config-only, fully reversible.

---

## Phase 2 — The layout decision, as a testable type

**Goal:** one pure type decides the navigation mode. No view logic yet.

- New value type (e.g. `RootLayoutMode`) mapping size class → `.tabs` / `.sidebar`.
- Written test-first: the tests exist before the type compiles.
- Zero view changes in this phase — it is pure logic, fully unit-tested.

**Covers:** NAV-06
**Done when:** the type is covered by tests and nothing else in the app has changed.
**Risk:** low. Nothing consumes it yet.
**Why separate:** it is the one piece of the port that can be TDD'd properly, and
isolating it keeps Phase 3's view surgery small.

---

## Phase 3 — Sidebar navigation on iPad

**Goal:** `NavigationSplitView` on regular width; the existing `TabView`
untouched on compact.

- `ContentView` branches on the Phase 2 type. The compact path is moved, not
  rewritten.
- Sidebar: Now Playing / Library / Settings as selection; LCD and VU as
  **toggle rows** with live-state icons — replacing the phantom-tab trick, which
  has no sidebar equivalent (see CONCERNS.md §2).
- Library drill-down works in the detail pane; selection survives rotation and
  resize.
- Render tests hosting the root at iPad and iPhone sizes assert the right branch.

**Covers:** NAV-01…05, NAV-07
**Done when:** both branches render correctly and the iPhone hierarchy test from
Phase 1 still passes.
**Risk:** highest in the project. Both branches live in one `ContentView`, so an
iPhone regression is the thing to guard hardest.

---

## Phase 4 — Make it look right at iPad sizes

**Goal:** nothing clipped, stranded or comically small from 320 pt to 1366 pt.

- Adapt the phone-fixed frames catalogued in ARCHITECTURE.md: `AlbumTracksView`
  240×240 hero, `AirplaySourceBadge` 240 pt, `StellarLogoView`,
  `StellarGlassyBackground`'s absolute 280 pt gradient radius.
- Verify the album/artist grids reflow (they are already `.adaptive`).
- Check sheet presentation on a large canvas.
- Keep every touch target ≥ 44 pt; keep using design tokens, not literals.

**Covers:** LAYOUT-01…07
**Done when:** screenshots at 320 pt, iPad mini, 11" and 13" all hold up.
**Risk:** medium — touches shared views, so iPhone regression is possible.

---

## Phase 5 — Parity sweep and full regression

**Goal:** prove all eight capabilities work on iPad and nothing on iPhone moved.

- Drive each capability against the live Pi backend from the iPad simulator.
- Full suite on all three simulators.
- Confirm the wire contract is untouched and volume stays unwired.
- `/gsd:code-review` over the whole branch diff.

**Covers:** PARITY-01…08, REG-02, REG-04, REG-05
**Done when:** the review is clean and all three simulators are green.
**Risk:** low, but this is the phase most likely to send work back to Phase 3 or 4.

---

## Phase 6 — Physical iPad

**Goal:** it works on real hardware.

- `scripts/deploy-to-device.sh` against the iPad (the script currently selects
  iPhones — expect a small change).
- Manual pass: all eight capabilities, both orientations, Split View, Stage Manager.
- Fix whatever the simulator hid.

**Covers:** DEVICE-01, DEVICE-02
**Done when:** the user has used it on the iPad and is satisfied.
**Blocked until:** the iPad is available (expected 2026-09-10).
**Risk:** unknown until hardware exists — device-only issues (real multitasking,
memory pressure, Bonjour on a real network) surface here.

---

## Merge

After Phase 6: `feature/ipad-port` → `main`, single merge.

## Phase dependency

```
1 ──► 2 ──► 3 ──► 4 ──► 5 ──► 6
                        ▲     (needs hardware)
              corrections loop back to 3/4
```

Phases 1–5 are simulator-only and can run today. Phase 6 waits on the iPad.
