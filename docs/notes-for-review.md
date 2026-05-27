# App Store — Notes for Review

Paste the body below into App Store Connect → version 1.0 → **App Review Information** → **Notes**.

Before submitting, replace the two `[INSERT ...]` placeholders.

---

```
HARDWARE REQUIREMENT — PLEASE READ

Stellar Remote is a remote-control app that requires a Stellar music
backend server running on the user's local Wi-Fi network (typically a
Raspberry Pi or a Mac on the same network). Apple reviewers will not
be able to reach this backend.

Without a reachable backend the app will display "Connecting..." on
all four tabs. This is expected behaviour, not a bug or a crash.

A screen recording demonstrating every feature on a live setup is
available at:

    [INSERT YOUR VIDEO URL HERE]

The video covers all four user-facing features:

  1. Now Playing tab — transport controls (play, pause, next, prev,
     seek, volume) against a live MPD session, plus the AirPlay-source
     mode that activates when the Pi's shairport-sync receiver is
     mid-session (gold "AIRPLAY · <sender>" badge, DACP transport).
  2. Library → Albums — album grid, tap a tile to push the Album
     Tracks screen, tap "Play Album" to play the whole folder, or
     tap any track row to start playback at that track.
  3. Library → Artists — artist list, drill into an artist to see
     their albums, tap an album to push the same Album Tracks screen.
  4. Settings → LCD screen — single toggle that wakes or standbys the
     Pi's HDMI display via the backend.
  5. Settings → Backend Server — auto-discover via Bonjour
     (_stellar._tcp) or enter a custom host/port manually.

If a live demonstration would help the review, I am happy to provide
one — please reply to this submission via Resolution Center and I
will set up a screen-share or recorded follow-up.

Contact: eduardo.marques81@gmail.com
```

---

## Three compliance answers at Submit time

| Question | Answer |
|---|---|
| Does this app use the Advertising Identifier (IDFA)? | **No** |
| Does your app contain, display, or access third-party content? | **No** |
| Does your app use encryption? | **No** (already pre-cleared via `ITSAppUsesNonExemptEncryption=false` in Info.plist; this question may not appear at all) |

## App Privacy nutrition label answers

| Question | Answer |
|---|---|
| Does this app collect data? | **No** |

All other questions disappear after answering "No" to the top-level question. The label will display "Data Not Collected" on the store page.

## Age Rating questionnaire

Answer **None / No** to every category. Result will be **4+**.
