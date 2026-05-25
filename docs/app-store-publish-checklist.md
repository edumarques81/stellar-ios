# Stellar VolumiO — App Store Publish Checklist

**Research date:** 2026-05-26
**Target:** Submit by 2026-05-27 AM
**Bundle ID:** `fit.stellar.remote` | **Team:** `3S2JYQ4JNX`

---

## 1. Feasibility Verdict

### Review SLA in 2026

| Metric | Time |
|---|---|
| App Store: Waiting for Review (avg) | ~10 h |
| App Store: In Review (avg) | ~2 h |
| App Store: total end-to-end p90 | 24–48 h for clean first-time submissions |
| Delay spike (March 2026 data) | Some submissions took 7–30 days — typically apps that triggered guideline flags |
| TestFlight Beta Review (external) | ~9 h wait + ~2 h review = ~11 h total |
| TestFlight Internal (no review) | 15–30 min build processing, then available instantly |

Source: [Runway App Review Times](https://www.runway.team/appreviewtimes), [iOS App Review Delays March 2026](https://www.lowcode.agency/blog/ios-app-review-delays-march-2026)

### Expedited Review

- **Qualifying criteria:** critical bug fix, security vulnerability, event-tied launch, regulatory deadline.
- "Submit by tomorrow because I'd like to" does not qualify.
- "Launching for [specific event on date X]" qualifies if accurate.
- Submit the request at: **https://developer.apple.com/contact/app-store/?topic=expedite**
- Response: 2–24 h on business days. If approved, review finishes in ~4–12 h.

### Fastest Realistic Path — RECOMMENDATION

**Use TestFlight Internal first. Submit to App Store in parallel.**

| Path | When users can install | Review required |
|---|---|---|
| TestFlight Internal | Tonight ~1 h after upload | None |
| TestFlight External | Tomorrow +11 h after submission | Beta App Review (~11 h) |
| App Store | 24–48 h after submission (best case) | Yes; no time guarantee |

**Concrete recommendation:**

1. Tonight: upload a correctly signed archive. Within 30 min of processing, you and any App Store Connect team members can install via TestFlight — no App Store review at all.
2. Simultaneously submit to App Store tonight. Given Runway's ~10 h average wait + ~2 h review and a historically clean new-app submission, there is a realistic (not guaranteed) chance of approval before tomorrow noon. Clean metadata and complete review notes are the biggest levers you control.
3. Do not request expedited review unless there is a real event deadline — the claim must be credible. If you have a launch event, use it.

**Date estimate:** If you start the archive/upload by 22:00 tonight (2026-05-26):
- TestFlight Internal: available by ~22:30
- App Store (optimistic): approved by 2026-05-27 08:00–10:00
- App Store (realistic): approved by 2026-05-27 14:00–18:00

---

## 2. App Store Connect Record Setup

### 2.1 Register the Bundle ID (if not already done)

1. Go to [https://developer.apple.com/account/resources/identifiers/list](https://developer.apple.com/account/resources/identifiers/list)
2. Click **+** → **App IDs** → **App**
3. Description: `Stellar Remote`
4. Bundle ID: **Explicit** → `fit.stellar.remote`
5. Capabilities needed: none beyond defaults (no Push, no CloudKit, no iCloud)
6. Register.

### 2.2 Create the App Record

URL: [https://appstoreconnect.apple.com/apps](https://appstoreconnect.apple.com/apps)

1. Click **+** (top-left) → **New App**
2. Platform: **iOS**
3. **Name:** `Stellar Remote` (≤60 chars) — "Stellar" alone risks trademark confusion (see Section 9); use "Stellar Remote" or "Stellar VolumiO"
4. **Primary Language:** English (or your preference)
5. **Bundle ID:** select `fit.stellar.remote` from dropdown (it must exist — Step 2.1)
6. **SKU:** `stellar-remote-v1` (internal only, never shown to users; letters/numbers/hyphens/periods/underscores only)
7. Click **Create**

### 2.3 App Information Fields

Navigate to: **App Store Connect → [your app] → App Information**

| Field | Value | Limit |
|---|---|---|
| Name | `Stellar Remote` | 60 chars |
| Subtitle | `Music player remote for your Pi` | 30 chars |
| Primary Category | **Music** | — |
| Secondary Category | **Utilities** | optional |
| Content Rights | Confirm you own or license all content | — |
| Age Rating | Complete the age-rating questionnaire; result will be 4+ | — |

**Category rationale:** The app controls music playback. "Music" is the closest match (Apple places Volumio's official iOS app in "Music"). "Utilities" is acceptable as secondary — it's a hardware control tool.

### 2.4 Privacy Policy URL — REQUIRED

Apple requires a live URL for every app. Options for a hobby app with no analytics:

**Option A (fastest — 10 min):** GitHub Pages
1. Create a public repo `stellar-privacy-policy` (or a `docs/` folder in this repo if it has a GitHub Pages site).
2. Commit a single `index.html` or `privacy.md` stating: no personal data is collected, no third-party analytics, the app communicates only with a user-provided LAN device.
3. Enable GitHub Pages → URL: `https://<yourusername>.github.io/stellar-privacy-policy/`

**Option B (2 min, zero hosting):** [App Privacy Policy Generator](https://app-privacy-policy-generator.firebaseapp.com/) — generates a hosted URL automatically. Select "I don't collect any data."

**Option C:** Notion page (share publicly) or a Vercel/Netlify static deploy.

Whatever URL you choose, paste it into:
- App Store Connect → App Information → Privacy Policy URL
- Also link to it inside the app (a tappable URL in Settings view is sufficient — this is a hard requirement)

### 2.5 App Privacy "Nutrition Label"

Navigate to: **App Store Connect → [your app] → App Privacy**

For Stellar, the correct answers are:

**Does this app collect data?** → **No**

Rationale: Stellar collects nothing. All socket events are sent to a LAN server that the user owns and controls. The app has no analytics SDK, no account system, no device fingerprinting, no crash reporter. Data transmitted to the local backend (play/pause commands, seek position) is processed in real time and not retained by the app developer. Per Apple's definition: *"Collect" = transmitting data in a way that allows the developer or third parties to access it for longer than needed to service the real-time request.* Stellar does not retain, store or have access to any event payload after it leaves the phone. Therefore: no data collected.

**Result on the App Store page:** The label will display "No Data Collected" — a selling point for privacy-conscious users.

**Important:** Your privacy policy text must be consistent with this declaration. Do not include language about analytics in the policy if you answer "no data collected" in App Store Connect. Apple cross-references these.

---

## 3. Assets Needed

### 3.1 App Icon

Xcode 16 / xcodegen-generated projects require a single master asset in the `Assets.xcassets` catalog. Verify:

- **Required:** 1024×1024 px PNG, sRGB or Display P3 color space, no transparency, no pre-applied rounded corners (iOS applies the superellipse mask automatically), no alpha channel.
- All other sizes (180×180, 120×120, 87×87, 80×80, 60×60, 58×58, 40×40, 29×29, 20×20) are auto-generated by Xcode from the 1024 master.

**Check:** Open `StellarVolumiO/Assets.xcassets` → `AppIcon.appiconset`. Verify the 1024 slot is filled. If it shows a warning triangle, the icon is missing or wrong format.

```bash
# Quick check: does the iconset have a 1024 asset?
ls StellarVolumiO/Assets.xcassets/AppIcon.appiconset/
# Should show a file plus Contents.json
```

If the icon is missing, create a 1024×1024 PNG and drag it into Xcode's AppIcon slot.

### 3.2 Screenshots — Mandatory Sizes (2026)

Apple now accepts a **single screenshot set** for the largest supported iPhone size and auto-scales down. For an iPhone-only app (TARGETED_DEVICE_FAMILY = 1 in project.yml — confirmed):

| What to provide | Resolution (portrait) | Covers |
|---|---|---|
| **REQUIRED: 6.9" iPhone** | **1320 × 2868 px** | iPhone 17 Pro Max, 16 Pro Max, 15 Pro Max |
| Optional fallback: 6.5" | 1284 × 2778 px | iPhone 14 Plus, 13 Pro Max, 12 Pro Max |

**You only need to upload 1 screenshot set (6.9") for iPhone-only apps.** App Store Connect scales it to all smaller shelf sizes in that family.

**Format:** PNG or JPEG, RGB, no alpha, exact pixel dimensions.
**Count:** 1–10 screenshots per device family. Aim for 3–5 showing each of the four features (Now Playing, Albums, Artists, Settings/LCD toggle).

**No iPad screenshots needed** because `TARGETED_DEVICE_FAMILY: "1"` (iPhone only).

**How to get them:**
```bash
# Boot the 6.9" simulator
xcrun simctl boot "iPhone 16 Pro Max"
# Build + run on it
xcodebuild -scheme StellarVolumiO \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
  -configuration Release \
  build
# Take screenshots via simctl
xcrun simctl io booted screenshot screenshot1.png
```
Or use the Simulator app → File → Take Screenshot (saves to Desktop at correct resolution).

Note: simulator screenshots of a LAN app will show a disconnected state. Either mock the UI state in a debug build, or use a device screenshot on your real iPhone connected to the backend.

### 3.3 App Preview Video

Optional. Not required. Skip for a first submission.

### 3.4 Metadata Fields

Navigate to: **App Store Connect → [your app] → [version] → App Store Information**

| Field | Value | Limit |
|---|---|---|
| Description | See draft below | 4000 chars |
| Promotional Text | `Minimal, fast remote control for your Stellar music backend.` | 170 chars |
| Keywords | `music,remote,volumio,player,mpd,raspberry pi,audio,transport,library,control` | 100 chars total |
| Support URL | Your GitHub repo URL or a dedicated support page | required |
| Marketing URL | Optional — can leave blank |  |
| Version | `1.0` | |
| What's New | Leave blank for 1.0 | |

**Draft description (edit to taste; ~300 chars — well under the 4000 limit):**

```
Stellar Remote is a minimal, fast remote control for the Stellar music backend.

Features:
• Transport — play, pause, next, previous, seek, volume
• Album browser — browse your full library, tap to play
• Artist browser — drill from artist to albums to tracks
• LCD toggle — wake or standby your Pi display from the Settings tab

Requires a Stellar backend running on your local network.
```

---

## 4. App Review Guidelines: Risks for Stellar

### 4.1 Guideline 5.1.5 — Local Network (HIGH RISK if missing)

iOS 14+ requires apps that access the local network to:
1. Include `NSLocalNetworkUsageDescription` in Info.plist
2. Display the iOS system prompt explaining why

**Current state:** `project.yml` has `NSAllowsLocalNetworking: YES` under `NSAppTransportSecurity`, which exempts ATS for local IPs. That is correct for HTTP. But **`NSLocalNetworkUsageDescription` is a separate, distinct key** and may be missing.

**Check:**
```bash
grep -r "NSLocalNetworkUsageDescription" StellarVolumiO/
```

**If missing, add to `project.yml` under `info.properties`:**
```yaml
NSLocalNetworkUsageDescription: "Stellar Remote connects to your music player on the local network to control playback and browse your library."
```

After adding: `xcodegen generate --spec project.yml` to regenerate the xcodeproj.

**Recommended wording** (clear and specific — Apple rejects generic descriptions):

> "Stellar Remote connects to the Stellar music backend on your local Wi-Fi network. This connection is used only to send playback commands (play, pause, skip, volume) and retrieve your music library. No data leaves your local network."

**Rejection risk without this key:** High. The app will trigger the local network permission prompt at runtime; if the plist key is absent, Apple may reject under 5.1.5.

### 4.2 Guideline 2.1 — App Completeness: The Reviewer-Can't-Reach-Your-LAN Problem

This is the **highest-rejection-risk** issue for Stellar.

**The problem:** Apple reviewers will see a blank/disconnected screen and cannot reach `192.168.86.221:3000`. The app will appear broken.

**Accepted industry patterns for hardware-dependent apps:**

| Pattern | How it works | Effort |
|---|---|---|
| **Demo mode (RECOMMENDED)** | App detects no connection → shows canned/mock state for transport, album list, artist list. Reviewer can tap everything. | Medium — 1–2 days |
| **Review Notes + video** | Explain in Notes for Review that hardware is required. Upload a screen-recorded video to YouTube/Dropbox, paste link. | Low — 1 h |
| **VPN access to your LAN** | Not practical — reviewer will not install a VPN you set up |  |

**The Volumio official iOS app strategy:** Ships a web view that connects to the local Volumio instance. When disconnected it shows a connection screen. Reviewers know what music-server remote apps are.

**Minimum viable mitigation (for tomorrow's submission):**

In Notes for Review, include all of the following:
1. Explain the app is a hardware remote that requires a Stellar backend server on the local network.
2. State that core UI cannot be tested without the hardware.
3. Provide a link to a screen-recorded video (record your phone controlling the Pi — ~2 min of every feature).
4. Offer to provide TestFlight access with your own device for Apple to video-call-review if needed.

This is commonly accepted for IoT and AV receiver remotes (Denon AVR Remote, Marantz AVR Remote, Torpedo Wireless Remote are all on the App Store with this same constraint).

**Longer-term (do not block submission on this):** Add a demo mode that shows canned data when `SocketService.isConnected == false`. This removes the risk entirely on resubmission.

**Sample Notes for Review text:**
```
HARDWARE REQUIREMENT — PLEASE READ

Stellar Remote requires a Stellar music backend server running on the user's 
local network (typically a Raspberry Pi or Mac). Apple reviewers will not be 
able to reach this server.

The app will display "Connecting..." on all tabs when no server is found. 
This is expected behavior, not a bug.

A screen recording demonstrating all four features on a live setup is 
available at: [INSERT YOUR VIDEO URL HERE]

Features demonstrated in the video:
1. Now Playing: transport controls (play/pause/skip/seek/volume)
2. Library → Albums: album grid, tap to open tracks, Play Album
3. Library → Artists: artist list, drill to albums, play tracks
4. Settings: LCD on/off toggle controlling the Pi's HDMI display

If further review is required, I am happy to provide a live demonstration.
```

### 4.3 Guideline 4.0 / 4.2 — Minimum Functionality

Risk: **Low.** The app has clear, distinct utility (remote control of a physical music player). It is not a single-feature "button" app. Four features plus a real socket protocol and library browser should satisfy 4.2 comfortably.

No risk from 4.1 (copycats) or 4.3 (spam).

### 4.4 Guideline 3.2.2 — Acceptable Business Practices

No risk. The app is free (no IAP, no ads, no subscription). None of the 3.2.2 subcategories apply.

### 4.5 Guideline 5.2.1 — Third-Party Hardware Compatibility

Apple allows apps that interact with third-party hardware as long as:
- You do not falsely imply Apple endorsement.
- You have the rights to reference the hardware/brand.

You own the Stellar backend. You built it. No MFi certification is required (MFi applies to Lightning/USB-C accessories, not LAN servers).

Optional disclosure in review notes: *"This app communicates with the Stellar backend server, an open-source project developed by the same developer."*

No blocking risk here.

---

## 5. Export Compliance

### 5.1 Does the App Use Encryption?

**Short answer: No non-exempt encryption. Set `ITSAppUsesNonExemptEncryption` to `NO`.**

Analysis:
- The app uses Socket.IO over plain HTTP (no TLS). Confirmed by `NSAllowsLocalNetworking: YES` in project.yml.
- Socket.IO/WebSocket without TLS does not use encryption.
- The SocketIO-Client-Swift library itself does not add encryption.
- iOS system-level HTTPS (URLSession, TLS) is ATS-managed and is exempt from export reporting requirements even when used.
- There is no proprietary or custom encryption in the codebase.

**Therefore: `ITSAppUsesNonExemptEncryption = NO`**

This avoids the export compliance documentation upload requirement.

### 5.2 Info.plist Key to Add

Add to `project.yml` under `info.properties`:

```yaml
ITSAppUsesNonExemptEncryption: NO
```

After adding: `xcodegen generate --spec project.yml`

Setting this key eliminates the "Missing Export Compliance" warning that appears in App Store Connect after upload and prevents reviewers from being blocked waiting for compliance documentation.

### 5.3 App Transport Security — Complete Picture

Current `project.yml` state:
```yaml
NSAppTransportSecurity:
  NSAllowsLocalNetworking: YES
```

This is correct and sufficient. `NSAllowsLocalNetworking: YES` allows HTTP connections to:
- Link-local addresses (169.254.x.x)
- Loopback (127.0.0.1, ::1)
- Local hostnames (`.local` mDNS)
- **Private range IPs including 192.168.x.x, 10.x.x.x, 172.16-31.x.x**

It does NOT disable ATS for the public internet, which is the right posture.

**Do NOT use `NSAllowsArbitraryLoads: YES`** — that disables ATS globally, is a red flag in review, and is not needed.

**Note for future Bonjour work:** When mDNS auto-discovery ships, `NSBonjourServices` must be added listing your service type (e.g., `_http._tcp`). That is out of scope for this submission but add it when the Bonjour phase ships.

---

## 6. Code Signing and Distribution

### 6.1 Assets Required

| Asset | Where to create | Type |
|---|---|---|
| Apple Distribution certificate | Xcode → Settings → Accounts → Manage Certificates, or developer.apple.com/account/resources/certificates | Automatically managed (preferred) or manual |
| App Store provisioning profile for `fit.stellar.remote` | Auto-generated when CODE_SIGN_STYLE = Automatic, or manually at developer.apple.com/account/resources/profiles | Distribution |

### 6.2 Signing Mode

`project.yml` already has `CODE_SIGN_STYLE: Automatic` and `DEVELOPMENT_TEAM: 3S2JYQ4JNX`. This means Xcode will automatically create/renew distribution certificates and provisioning profiles when you archive with `-allowProvisioningUpdates`.

**No manual certificate/profile download needed if you archive through Xcode or use `-allowProvisioningUpdates` on the command line.**

### 6.3 Archive Build Command

```bash
# From the stellar-ios/ directory
# Step 1: Regenerate xcodeproj after any project.yml changes
xcodegen generate --spec project.yml

# Step 2: Archive for distribution
xcodebuild \
  -project StellarVolumiO.xcodeproj \
  -scheme StellarVolumiO \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath ./build/StellarVolumiO.xcarchive \
  -allowProvisioningUpdates \
  archive
```

`-allowProvisioningUpdates` lets Xcode automatically create or update certificates and provisioning profiles if they don't exist yet. Without it, the archive step will fail if a distribution profile isn't pre-installed.

### 6.4 Export the IPA

Create `ExportOptions.plist` in the project root:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>
  <key>teamID</key>
  <string>3S2JYQ4JNX</string>
  <key>destination</key>
  <string>upload</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
```

Then export (and upload in one step if `destination = upload`):

```bash
xcodebuild \
  -exportArchive \
  -archivePath ./build/StellarVolumiO.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath ./build/ipa \
  -allowProvisioningUpdates
```

With `destination = upload` in the plist, this exports **and uploads** the IPA to App Store Connect in a single command. No separate `altool` or `notarytool` call needed.

### 6.5 Alternative: Xcode Organizer (GUI)

If the CLI fails for any reason:
1. Open `StellarVolumiO.xcodeproj` in Xcode.
2. Product → Archive.
3. When Organizer opens, click **Distribute App** → **App Store Connect** → **Upload** → Next through the wizard.
4. Xcode handles signing and upload automatically.

This is the most reliable fallback. Use it if CLI signing errors appear.

### 6.6 altool vs notarytool in 2026

- `altool` for **notarization** (macOS apps) was deprecated in Xcode 13. **Do not use `altool --notarize-app`.**
- `altool` for **iOS App Store upload** (`--upload-app`) still works as of 2026 but is not the preferred method. The `xcodebuild -exportArchive` with `destination = upload` in the plist is preferred.
- `xcrun notarytool` is for **macOS notarization only** — not relevant for iOS.
- For iOS uploads, the options in priority order: (1) xcodebuild exportArchive with upload destination, (2) Xcode Organizer, (3) Transporter app from the Mac App Store.

### 6.7 Common Signing Pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| "No signing certificate found" | No Apple Distribution cert in Keychain | Run archive with `-allowProvisioningUpdates` or create cert in Xcode → Settings → Accounts |
| "Provisioning profile doesn't match entitlements" | Entitlements in archive differ from profile | Check Signing & Capabilities in Xcode; ensure no capabilities are checked that aren't in the profile |
| "Missing push notification entitlement" | project.yml accidentally enabled a capability | Verify targets.StellarVolumiO has no unexpected capabilities entries |
| Transporter error 90205 | Binary contains invalid architectures | Use `-destination "generic/platform=iOS"` not a simulator destination |
| "CODE_SIGNING_REQUIRED" on archive | Release config not set to use distribution signing | Ensure Release config uses the Apple Distribution identity |

---

## 7. TestFlight Path (Faster Alternative)

### 7.1 Internal Testers (Available Tonight — Recommended First Step)

- **Who qualifies:** Users in your App Store Connect account (Team Agent, Admin, Developer, Marketing roles).
- **Review:** None required.
- **Time to available:** ~15–30 min after successful upload (build processing time).
- **Limit:** 100 internal testers.
- **Build expiry:** 90 days.

**Steps:**
1. Upload the archive (Section 6.3/6.4).
2. In App Store Connect → [your app] → **TestFlight** tab.
3. Wait for the build to show "Ready to Test" (processing).
4. Click the build → **Enable** under "Internal Testing."
5. Under "Internal Testers" → add your Apple ID.
6. You receive a TestFlight invite email → install TestFlight app → install Stellar.

### 7.2 External Testers (Available ~Tomorrow Afternoon)

- **Who qualifies:** Anyone — just needs an Apple ID and TestFlight installed.
- **Review:** Beta App Review required before the first external build is distributed. Average ~11 h.
- **Limit:** 10,000 external testers.
- **Steps:**
  1. In TestFlight tab → **External Testing** → **+** to create a group.
  2. Add testers by email or create a public link.
  3. Click **Submit for Beta Review** on the build.
  4. After Beta App Review approval (~11 h), testers can install.

### 7.3 Internal vs External for Stellar

Use internal immediately for yourself. For "user installs from somewhere other than Xcode" — internal TestFlight is the fastest possible path. No review. No screenshots required. No metadata. Upload tonight, install tonight.

---

## 8. App Store Submission Step-by-Step

### 8.1 Pre-Submission Checklist

Before clicking Submit for Review, verify every item:

**Build & Technical**
- [ ] `NSLocalNetworkUsageDescription` present in Info.plist (check with `grep -r NSLocalNetworkUsageDescription StellarVolumiO/`)
- [ ] `ITSAppUsesNonExemptEncryption = NO` in Info.plist
- [ ] `NSAllowsLocalNetworking: YES` under `NSAppTransportSecurity` (already in project.yml — confirm after xcodegen regenerate)
- [ ] App builds without warnings in Release configuration
- [ ] App runs on a physical device — not just simulator
- [ ] No crash on cold launch (test on device disconnected from backend to verify the "Connecting..." graceful state)
- [ ] `MARKETING_VERSION` is `1.0`, `CURRENT_PROJECT_VERSION` is `1` (in project.yml — looks correct)
- [ ] Archive built with `generic/platform=iOS` destination (not a simulator)

**App Store Connect Metadata**
- [ ] App name set (≤60 chars)
- [ ] Subtitle set (≤30 chars)
- [ ] Primary category: Music
- [ ] Description written (≤4000 chars)
- [ ] Promotional text set (≤170 chars)
- [ ] Keywords set (≤100 chars total — commas separate, no spaces after commas)
- [ ] Support URL is a live, reachable URL
- [ ] Privacy policy URL is live and reachable (fetch it in a browser right before submitting)
- [ ] Privacy policy URL also linked inside the app (Settings view or About screen)
- [ ] Privacy nutrition label: "No Data Collected" selected
- [ ] Age rating questionnaire completed
- [ ] Screenshots uploaded (at least 1 × 1320×2868 for 6.9" iPhone)
- [ ] Build selected for the submission version (the upload from Step 6.4)

**Notes for Review (CRITICAL for this app)**
- [ ] Notes for Review filled in (use the template from Section 4.2 above)
- [ ] Video URL of the app working included in Notes for Review
- [ ] Contact email in Notes for Review (so Apple can reach you fast if they have questions)

### 8.2 How to Submit

1. App Store Connect → [your app] → [version 1.0] → scroll to bottom → **Submit for Review**
2. Answer the three compliance questions:
   - "Does this app use the Advertising Identifier (IDFA)?" → **No**
   - "Does your app contain, display, or access third-party content?" → **No** (or Yes if applicable)
   - "Does your app use encryption?" — If you added `ITSAppUsesNonExemptEncryption = NO` to Info.plist, App Store Connect may not ask this; if it does, answer **No**
3. Click **Submit**

### 8.3 After Submitting

| Status | Meaning |
|---|---|
| Waiting for Review | In queue. Normal ~10 h average. |
| In Review | Actively being reviewed. ~2 h. |
| Approved | Ready to release. You must click Release (or set auto-release). |
| Metadata Rejected | Non-code issue (screenshot, description). Fast to fix. |
| Rejected | Code or guideline issue. You receive a rejection reason. |

**If rejected:**
- Read the rejection message carefully. Common categories: 2.1 (incomplete functionality), 5.1 (privacy), 4.0 (design).
- Reply within the Resolution Center (in App Store Connect) — do not resubmit a new binary for a metadata/notes issue.
- Add the demo video link + notes-for-review text and reply.
- Response can re-trigger review within a few hours.

---

## 9. Risks and Landmines Specific to Stellar

### Risk 1 — LAN-Only App with No Demo Mode (CRITICAL)

**Probability of rejection:** High on first submission without a video link and clear notes.

**Mitigations in priority order:**

1. **[Tonight — required]** Write detailed Notes for Review with screen-recording video URL. See Section 4.2 template. This alone can get the app through — Denon AVR Remote, Marantz AVR Remote, and similar hardware remote apps are all on the App Store with the same constraint.
2. **[Within 1 week — strongly recommended]** Add a "Demo Mode" that activates when `SocketService.isConnected == false` for > 5 seconds. Populate stores with canned data so the reviewer can browse albums, see the transport UI, and tap the LCD toggle (no-op in demo mode). Resubmit. This eliminates the risk permanently.
3. **[Low effort alternative]** Add a "Demo / Simulate connection" developer flag that can be toggled by tapping the app version label 7 times in Settings (like a hidden diagnostic mode). Document this in Notes for Review.

### Risk 2 — Bundle ID Namespace `fit.stellar.remote`

**The `fit.stellar` prefix is in your Team ID 3S2JYQ4JNX's account** (confirmed by project.yml and prior deploy-to-device.sh output). Register the explicit bundle ID `fit.stellar.remote` in the Developer portal (Section 2.1) before archiving. If the bundle ID is not registered, the archive will fail.

**Check:** [https://developer.apple.com/account/resources/identifiers/list](https://developer.apple.com/account/resources/identifiers/list) — look for `fit.stellar.remote`.

### Risk 3 — App Name "Stellar" Trademark

**Search results:** Existing USPTO registrations for "STELLAR" include:
- Stellar Development Foundation — covers blockchain/smart contract software (not audio)
- Stellar Corporation — covers kitchen furniture
- Stellar Verse Productions — covers downloadable audio files / music content

None of the existing "Stellar" marks appear to cover an iOS remote-control application for music playback. However:

- Do not name the app just "Stellar" — this is too close to the Stellar Development Foundation mark (which is live and covers software).
- Use `Stellar Remote` or `Stellar VolumiO` as the App Store name. These are descriptive + distinctive enough to avoid confusion.
- Full trademark clearance search: [https://tmsearch.uspto.gov](https://tmsearch.uspto.gov) — search "STELLAR" in IC 009 (software/electronics) for a complete picture.
- **This is not a blocking issue for submission**, but use a qualified name.

### Risk 4 — Missing NSLocalNetworkUsageDescription

See Section 4.1. This is an easy fix (one line in project.yml) but will cause rejection if missed. Check tonight before archiving.

### Risk 5 — Screenshots Show Disconnected State

If you take screenshots on a simulator or device not connected to the backend, all tabs will show loading/empty states. Reviewers may interpret this as a broken app. Take screenshots on your actual iPhone connected to the backend, or build a screenshot-state mock.

---

## 10. Recommended Timeline — Submit Tomorrow Morning

**Assumption:** Starting 21:00 on 2026-05-26. Target: Submit button clicked by 09:00 on 2026-05-27.

### Tonight (2026-05-26)

| Time | Task | Notes |
|---|---|---|
| 21:00 | Read this checklist end to end | Identify anything that needs clarification |
| 21:15 | **Check `NSLocalNetworkUsageDescription`** | `grep -r NSLocalNetworkUsageDescription StellarVolumiO/` — if missing, add to project.yml and `xcodegen generate` |
| 21:20 | **Add `ITSAppUsesNonExemptEncryption: NO`** to project.yml | Under `info.properties`; then `xcodegen generate` |
| 21:25 | Verify AppIcon 1024×1024 slot is filled | Open Assets.xcassets in Xcode or Finder |
| 21:30 | **Record screen video** of the app in full operation | 2–3 min covering all 4 features. Upload to YouTube (unlisted) or Dropbox. Save the URL. |
| 21:45 | Take at least 3 screenshots on physical iPhone connected to backend | 1320×2868 capture: Now Playing, Albums, Artists. Save to Desktop. |
| 22:00 | **Build the archive** | `xcodebuild -project ... -scheme StellarVolumiO -configuration Release -destination "generic/platform=iOS" -archivePath ./build/StellarVolumiO.xcarchive -allowProvisioningUpdates archive` |
| 22:20 | **Create App Store Connect app record** | Sections 2.1–2.5. Fill all required fields. Upload screenshots. Paste privacy policy URL (create it first if needed — see Section 2.4). |
| 22:40 | **Export + upload IPA** | `xcodebuild -exportArchive` with ExportOptions.plist (destination = upload). Or Xcode Organizer if CLI fails. |
| 23:00 | Wait for build to appear in App Store Connect | Usually 15–30 min processing. |
| 23:30 | **Enable Internal TestFlight** | Add yourself as internal tester. Install on your iPhone via TestFlight. Smoke test it. |
| 23:45 | **Write Notes for Review** | Use the template in Section 4.2. Paste your video URL. |
| 00:00 | **Fill App Privacy questionnaire** | "No data collected." |
| 00:10 | **Final pre-submission check** | Run through Section 8.1 checklist line by line. |
| 00:15 | **Click Submit for Review** | |

### Tomorrow Morning (2026-05-27)

| Time | Task |
|---|---|
| 08:00 | Check App Store Connect status. "In Review" is good; "Waiting for Review" means queue. |
| 08:30 | If "Rejected": read rejection, reply in Resolution Center with video link + clarification. Do not resubmit binary unless code change is needed. |
| 09:00 | If still "Waiting for Review": consider requesting expedited review only if you have a genuine event/launch date to cite. |

**What MUST happen tonight:**
1. NSLocalNetworkUsageDescription in Info.plist
2. ITSAppUsesNonExemptEncryption = NO in Info.plist
3. App icon 1024×1024 confirmed
4. Screen recording video URL (paste in Notes for Review)
5. Screenshots (at minimum 1 at 1320×2868)
6. App Store Connect record fully populated
7. Upload + submit

**What can wait until morning (do not block on these):**
- Demo mode implementation
- More than 3 screenshots
- App Preview video
- Full trademark search

---

## Sources

- [Runway App Review Times (live)](https://www.runway.team/appreviewtimes)
- [iOS App Review Delays March 2026](https://www.lowcode.agency/blog/ios-app-review-delays-march-2026)
- [iOS Distribution Guide 2026 — Foresight Mobile](https://foresightmobile.com/blog/ios-app-distribution-guide-2026)
- [Apple App Store Review Guidelines (current)](https://developer.apple.com/app-store/review/guidelines/)
- [NSLocalNetworkUsageDescription — Apple Developer Docs](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription)
- [NSAllowsLocalNetworking — Apple Developer Docs](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
- [ITSAppUsesNonExemptEncryption — Apple Developer Docs](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
- [App Privacy Details — Apple Developer](https://developer.apple.com/app-store/app-privacy-details/)
- [Upload Builds — App Store Connect Help](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [App Review — Expedite — Apple Developer](https://developer.apple.com/distribute/app-review/)
- [Screenshot Specifications — App Store Connect Help](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [App Store Screenshot Dimensions 2026 — Screenhance](https://screenhance.com/blog/app-store-screenshot-dimensions-2026)
- [iOS App Icon Sizes 2026 — IconikAI](https://www.iconikai.com/blog/ios-app-icon-size-guidelines-guide)
- [App Store Review Guidelines 2026 Checklist — Adapty](https://adapty.io/blog/how-to-pass-app-store-review/)
- [App Store Review Requirements 2026 — Lexogrine](https://lexogrine.com/blog/apple-app-store-review-requirements-2026)
- [App Submission with Hardware — Apple Developer Forums](https://developer.apple.com/forums/thread/71299)
- [Expedited App Store Review Request Guide — Median.co](https://median.co/blog/how-to-request-the-urgent-expedite-request-for-immediate-release-of-ios-apps)
- [TestFlight Beta Testing Complete Guide — iOS Submission Guide](https://iossubmissionguide.com/testflight-beta-testing-complete-guide/)
- [xcodebuild exportArchive + ExportOptions — Medium](https://medium.com/@liwp.stephen/build-ios-application-and-upload-to-app-store-from-command-line-b7b3b1c35f8b)
- [Privacy Policy for iOS Apps — TermsFeed](https://www.termsfeed.com/blog/ios-apps-privacy-policy/)
- [App Privacy Policy Generator (free/open source)](https://app-privacy-policy-generator.firebaseapp.com/)
- [STELLAR Trademark search — USPTO Report](https://tmsearch.uspto.gov)
