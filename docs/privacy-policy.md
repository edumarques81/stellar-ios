# Privacy Policy — Stellar Remote

**Effective date:** 2026-05-28
**App:** Stellar Remote (iOS)
**Developer:** Eduardo Marques
**Contact:** eduardo.marques81@gmail.com

## Summary

**Stellar Remote does not collect any personal data.**

Stellar Remote is a remote-control app that communicates only with a Stellar music backend server running on your own local Wi-Fi network. The app sends playback commands and reads your music library from that server. No data ever leaves your local network as a result of using this app, and the developer has no access to anything you do with it.

## What the app does on your network

- Discovers a Stellar backend on the local network via Bonjour (mDNS service type `_stellar._tcp`), or connects to a host/port you enter manually.
- Sends Socket.IO events for playback commands: play, pause, next, previous, seek, volume, mute, stop.
- Sends Socket.IO events to request your music library: album list, artist list, album tracks.
- Sends a single command to wake or standby the connected LCD display.
- Receives broadcast events from the backend to update the UI in real time (current track, queue, library refresh notifications, AirPlay session state).

All of the above happen between your iPhone and your own backend server. The developer is not in the loop and has no way to observe or store this traffic.

## What the app does NOT do

- Does not include any third-party analytics SDK.
- Does not include any crash reporter.
- Does not collect an advertising identifier (IDFA) or any other tracking identifier.
- Does not have any user account system, login, or password.
- Does not transmit any data outside your local network.
- Does not store music files, listening history, or user activity on any server controlled by the developer.

## Data the device stores locally

The app stores a small amount of preference data in iOS UserDefaults on your device only:

- The host, port, and scheme of your selected Stellar backend.
- The last selected color theme.

This data never leaves the device. Uninstalling the app removes it.

## Network permission

The app requests permission to access the local network (`NSLocalNetworkUsageDescription`). This permission is required by iOS 14+ for any app that communicates with devices on the local Wi-Fi network. The app uses this permission solely to reach your Stellar backend server.

## Children

The app is rated 4+. It does not collect any data from any user, including children.

## Changes to this policy

If this policy ever changes, the updated version will replace this page and the effective date above will be updated.

## Contact

Questions about this policy: **eduardo.marques81@gmail.com**
