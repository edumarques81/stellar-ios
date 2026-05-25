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
#
set -e -o pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="StellarVolumiO"
PROJECT="$REPO/$SCHEME.xcodeproj"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-3S2JYQ4JNX}"
CONFIGURATION="${CONFIGURATION:-Debug}"

echo "🚀 stellar-ios — Physical Device Deployment"
echo "==========================================="
echo "  Repo:    $REPO"
echo "  Scheme:  $SCHEME"
echo "  Config:  $CONFIGURATION"
echo "  Team:    $DEVELOPMENT_TEAM"
echo ""

# ── Find the device ──────────────────────────────────────────────────────────
# xcodebuild needs the hardware UDID (the 00008xxx-... form from xctrace).
# devicectl needs its own CoreDevice UUID. They are NOT the same.

echo "🔎 Locating paired iPhone/iPad…"

# devicectl line — pick the first iPhone/iPad in `available` state.
DEVICECTL_LINE=$(xcrun devicectl list devices 2>/dev/null \
                  | grep -iE "iphone|ipad" \
                  | grep -E "available|connected" \
                  | head -1 || true)

if [ -z "$DEVICECTL_LINE" ]; then
  echo "❌ No paired iPhone/iPad visible to devicectl."
  echo "   → Make sure the phone is on the same Wi-Fi (or USB-connected),"
  echo "     unlocked, and previously paired with this Mac in Xcode."
  echo "   → Run: xcrun devicectl list devices"
  exit 1
fi

# devicectl's identifier (UUID) is the second-to-last token before the State column.
DEVICECTL_UUID=$(echo "$DEVICECTL_LINE" \
                  | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
                  | head -1)

# Hardware UDID (the long hex with one hyphen, e.g. 00008130-001024A61A50001C)
# appears inside the hostname as <UDID>.coredevice.local.
HW_UDID=$(echo "$DEVICECTL_LINE" \
            | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}' \
            | head -1)

DEVICE_NAME=$(echo "$DEVICECTL_LINE" | awk -F'  +' '{print $1}')

if [ -z "$DEVICECTL_UUID" ] || [ -z "$HW_UDID" ]; then
  echo "❌ Could not extract UDIDs from devicectl output:"
  echo "   $DEVICECTL_LINE"
  exit 1
fi

echo "✅ Device : $DEVICE_NAME"
echo "   xcodebuild UDID : $HW_UDID"
echo "   devicectl UUID  : $DEVICECTL_UUID"
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

BUILD_LOG=$(mktemp -t stellar-ios-build).log
set +e
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "id=$HW_UDID" \
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
echo "   on:        $DEVICE_NAME"

xcrun devicectl device install app \
  --device "$DEVICECTL_UUID" \
  "$APP_PATH" 2>&1 | tail -6

# ── Launch ───────────────────────────────────────────────────────────────────
if [ -n "$BUNDLE_ID" ]; then
  echo ""
  echo "🚀 Launching $BUNDLE_ID on $DEVICE_NAME…"
  echo "   (unlock the phone first if the screen is off)"
  xcrun devicectl device process launch \
    --device "$DEVICECTL_UUID" \
    "$BUNDLE_ID" 2>&1 | tail -5 \
    || echo "   ⚠️  Launch skipped — unlock the phone and tap the StellarVolumiO icon."
fi

echo ""
echo "✅ Done."
echo ""
echo "Default backend:          192.168.86.221:3000 (Stores/BackendConfigStore.defaultHost)"
echo "                          Override in-app via Settings → Backend Server."
echo "Mac stellar log:          ~/Library/Logs/stellar-backend.err.log"
