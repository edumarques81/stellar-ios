#!/usr/bin/env bash
# deploy-to-device.sh — Build + install + launch StellarVolumiO on a paired iPhone.
#
# Works over USB or the local network — anything `xcrun devicectl` can reach.
# Swift Packages alone can't produce a signed iOS .app, so this script
# generates a thin Xcode-project wrapper via xcodegen + project.yml, builds
# it with xcodebuild, then installs+launches via devicectl.
#
# Usage:
#   ./scripts/deploy-to-device.sh
#
# Env overrides:
#   DEVELOPMENT_TEAM  Apple developer team id used for codesigning.
#                     Default is the team already used elsewhere on this Mac
#                     (3S2JYQ4JNX). Override if your team differs.
#   CONFIGURATION     Debug | Release (default Debug — Release strips logging
#                     symbols and is signed the same way, both work over the LAN).
#   DEVICE_UDID       Hardware UDID of the phone to install on. Required only
#                     when more than one iOS device is paired and stdin is not
#                     a TTY (the script prompts interactively otherwise).
#
# Device selection:
#   Two iPhones are paired with this Mac and BOTH are named "Eduardo's iPhone",
#   so the marketing name (iPhone 15 Pro / iPhone 12 Pro) is what actually
#   distinguishes them. Pass a substring as the first argument to pick one:
#
#   ./scripts/deploy-to-device.sh "15 Pro"
#   DEVICE_UDID=00008130-001024A61A50001C ./scripts/deploy-to-device.sh
#
set -e -o pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="StellarVolumiO"
PROJECT="$REPO/$SCHEME.xcodeproj"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-3S2JYQ4JNX}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DEVICE_FILTER="${1:-}"

echo "🚀 stellar-ios — Physical Device Deployment"
echo "==========================================="
echo "  Repo:    $REPO"
echo "  Scheme:  $SCHEME"
echo "  Config:  $CONFIGURATION"
echo "  Team:    $DEVELOPMENT_TEAM"
echo ""

# ── Find the device ──────────────────────────────────────────────────────────
# Two different identifiers are in play and they are NOT interchangeable:
#   * hardwareProperties.udid  (00008130-001024A61A50001C) — the xcodebuild form
#   * identifier               (86222812-423C-...)         — the devicectl form
#
# Both come from `devicectl list devices --json-output`. The human-readable
# table is NOT parseable for this: it used to embed the hardware UDID in the
# hostname as <UDID>.coredevice.local, but hostnames are name-based now
# (Eduardos-iPhone.coredevice.local), so scraping it yields nothing.

echo "🔎 Locating paired iOS devices…"

command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 not found — needed to parse devicectl JSON."
  echo "   → Install the Xcode Command Line Tools: xcode-select --install"
  exit 1
}

DEVICES_JSON=$(mktemp -t stellar-ios-devices)
trap 'rm -f "$DEVICES_JSON"' EXIT
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1 || {
  echo "❌ devicectl could not enumerate devices. Run: xcrun devicectl list devices"
  exit 1
}

# One TAB-separated record per paired iOS device (the Apple Watch is filtered
# out by platform). Fields: udid, coredevice uuid, marketing name, given name,
# tunnel state.
DEVICE_TABLE=$(python3 - "$DEVICES_JSON" <<'PY'
import json, sys
with open(sys.argv[1]) as fh:
    payload = json.load(fh)
for dev in payload.get("result", {}).get("devices", []):
    hw = dev.get("hardwareProperties", {})
    if hw.get("platform") != "iOS":
        continue
    udid = hw.get("udid")
    ident = dev.get("identifier")
    if not udid or not ident:
        continue
    print("\t".join([
        udid,
        ident,
        hw.get("marketingName") or "unknown model",
        dev.get("deviceProperties", {}).get("name") or "unnamed",
        dev.get("connectionProperties", {}).get("tunnelState") or "unknown",
    ]))
PY
)

if [ -z "$DEVICE_TABLE" ]; then
  echo "❌ No paired iPhone/iPad visible to devicectl."
  echo "   → Make sure the phone is on the same Wi-Fi (or USB-connected),"
  echo "     unlocked, and previously paired with this Mac in Xcode."
  echo "   → Run: xcrun devicectl list devices"
  exit 1
fi

# Narrow by DEVICE_UDID (exact) or the first argument (case-insensitive
# substring against the model and the device name).
if [ -n "${DEVICE_UDID:-}" ]; then
  MATCHES=$(printf '%s\n' "$DEVICE_TABLE" | awk -F'\t' -v u="$DEVICE_UDID" '$1 == u')
  [ -z "$MATCHES" ] && { echo "❌ No paired iOS device with UDID $DEVICE_UDID"; exit 1; }
elif [ -n "$DEVICE_FILTER" ]; then
  FILTER_LC=$(printf '%s' "$DEVICE_FILTER" | tr '[:upper:]' '[:lower:]')
  MATCHES=$(printf '%s\n' "$DEVICE_TABLE" \
            | awk -F'\t' -v f="$FILTER_LC" 'index(tolower($3 " " $4), f) > 0')
  [ -z "$MATCHES" ] && { echo "❌ No paired iOS device matching \"$DEVICE_FILTER\""; exit 1; }
else
  MATCHES="$DEVICE_TABLE"
fi

MATCH_COUNT=$(printf '%s\n' "$MATCHES" | grep -c . || true)

if [ "$MATCH_COUNT" -gt 1 ]; then
  if [ -t 0 ]; then
    echo ""
    echo "Multiple iOS devices are paired — pick one:"
    echo ""
    i=0
    while IFS=$'\t' read -r udid ident model name tunnel; do
      i=$((i + 1))
      printf '  %d) %-14s  %-22s  %s\n' "$i" "$model" "$name" "$udid"
    done <<< "$MATCHES"
    echo ""
    printf 'Device [1-%d]: ' "$MATCH_COUNT"
    read -r CHOICE
    case "$CHOICE" in
      ''|*[!0-9]*) echo "❌ Not a number."; exit 1 ;;
    esac
    [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "$MATCH_COUNT" ] || { echo "❌ Out of range."; exit 1; }
    SELECTED=$(printf '%s\n' "$MATCHES" | sed -n "${CHOICE}p")
  else
    echo "❌ $MATCH_COUNT iOS devices are paired and no selector was given."
    echo "   Re-run with a model substring or an explicit UDID:"
    echo ""
    while IFS=$'\t' read -r udid ident model name tunnel; do
      printf '     ./scripts/deploy-to-device.sh "%s"        # %s\n' "$model" "$name"
      printf '     DEVICE_UDID=%s ./scripts/deploy-to-device.sh\n' "$udid"
    done <<< "$MATCHES"
    exit 1
  fi
else
  SELECTED="$MATCHES"
fi

IFS=$'\t' read -r HW_UDID DEVICECTL_UUID DEVICE_MODEL DEVICE_NAME TUNNEL_STATE <<< "$SELECTED"

echo "✅ Device : $DEVICE_MODEL — $DEVICE_NAME"
echo "   xcodebuild UDID : $HW_UDID"
echo "   devicectl UUID  : $DEVICECTL_UUID"
echo "   tunnel          : $TUNNEL_STATE"
if [ "$TUNNEL_STATE" != "connected" ]; then
  echo "   ⚠️  No active tunnel — devicectl will try to connect at install time."
  echo "      Unlock the phone and keep it on this Wi-Fi network."
fi
echo ""

# ── Regenerate the Xcode project from project.yml ───────────────────────────

cd "$REPO"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "❌ xcodegen not found. Install with: brew install xcodegen"
  exit 1
fi
echo "🛠  Regenerating $SCHEME.xcodeproj from project.yml…"
xcodegen generate --spec project.yml 2>&1 | tail -3

# ── Resolve package dependencies ─────────────────────────────────────────────

echo ""
echo "📦 Resolving Swift package dependencies…"
xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme "$SCHEME" 2>&1 | tail -3

# ── Build for device ─────────────────────────────────────────────────────────

echo ""
echo "🔨 Building $SCHEME for device ($CONFIGURATION)…"
echo "   (first build can take 3–5 min; subsequent builds are incremental)"

BUILD_LOG=$(mktemp -t stellar-ios-build)
set +e
# `generic/platform=iOS` rather than `id=$HW_UDID`: the generic destination
# builds one arm64 binary valid for either paired phone and does not require an
# active tunnel to the device, so the build still succeeds when the phone is
# asleep or off-network. The device identity only matters at install time.
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "generic/platform=iOS" \
  -configuration "$CONFIGURATION" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  > "$BUILD_LOG" 2>&1
BUILD_STATUS=$?
set -e

# Surface only the interesting lines (errors + final verdict).
grep -E '^/Users.+\.swift:[0-9]+:[0-9]+:|error:|warning:|BUILD SUCCEEDED|BUILD FAILED' "$BUILD_LOG" \
  | grep -v "^//" | tail -20 || true

if [ $BUILD_STATUS -ne 0 ] || grep -q "BUILD FAILED" "$BUILD_LOG"; then
  echo ""
  echo "❌ Build failed. Full log: $BUILD_LOG"
  exit 1
fi

# ── Locate the built .app bundle ─────────────────────────────────────────────
# Swift Package builds land under DerivedData/<scheme>-<hash>/Build/Products/<Config>-iphoneos/.
# Take the most recently modified .app whose name matches the scheme.

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData \
            -type d -name "${SCHEME}.app" \
            -path "*/${CONFIGURATION}-iphoneos/*" \
            -not -path "*/Index.noindex/*" \
            -print0 2>/dev/null \
          | xargs -0 ls -dt 2>/dev/null \
          | head -1)

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "❌ Built .app bundle not found under DerivedData."
  echo "   Looked for ${SCHEME}.app inside ${CONFIGURATION}-iphoneos/."
  exit 1
fi

# Extract bundle id from Info.plist so we don't have to hardcode it.
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist" 2>/dev/null || true)
if [ -z "$BUNDLE_ID" ]; then
  echo "⚠️  Could not read CFBundleIdentifier from $APP_PATH/Info.plist — launch step may fail."
fi

echo ""
echo "📦 Installing $APP_PATH"
[ -n "$BUNDLE_ID" ] && echo "   Bundle id: $BUNDLE_ID"
echo "   on:        $DEVICE_MODEL — $DEVICE_NAME"

xcrun devicectl device install app \
  --device "$DEVICECTL_UUID" \
  "$APP_PATH" 2>&1 | tail -6

# ── Launch ───────────────────────────────────────────────────────────────────
if [ -n "$BUNDLE_ID" ]; then
  echo ""
  echo "🚀 Launching $BUNDLE_ID on $DEVICE_MODEL…"
  echo "   (unlock the phone first if the screen is off)"
  xcrun devicectl device process launch \
    --device "$DEVICECTL_UUID" \
    "$BUNDLE_ID" 2>&1 | tail -5 \
    || echo "   ⚠️  Launch skipped — unlock the phone and tap the StellarVolumiO icon."
fi

echo ""
echo "✅ Done."
echo ""
echo "Default backend:          stellar.local:3000 (Stores/BackendConfigStore.defaultHost)"
echo "                          Override in-app via Settings → Backend Server."
echo "Backend log (on the Pi):  journalctl -u stellar-backend -f"
