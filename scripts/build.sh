#!/bin/bash
# Build the iOS app for the iPhone 16 Pro simulator. Used as the compile-check
# after each code change during plan execution.
#
# Destination resolution:
#   - If IOS_SIM_ID is set in the environment, the build targets that specific
#     simulator UDID — use this on machines with multiple "iPhone 16 Pro" entries.
#   - If IOS_SIM_ID is unset or empty, the build falls back to name=iPhone 16 Pro,
#     which works on any fresh Xcode install or CI runner without extra config.
#
# Example (operator with two matching sims):
#   export IOS_SIM_ID=71E156C3-0CC1-4659-86AA-B044DE8CDBEB
#   scripts/build.sh
set -euo pipefail
SIM_ID="${IOS_SIM_ID:-}"
if [ -n "$SIM_ID" ]; then
  DEST="platform=iOS Simulator,id=$SIM_ID"
else
  DEST="platform=iOS Simulator,name=iPhone 16 Pro"
fi
exec xcodebuild \
  -scheme StellarVolumiO \
  -destination "$DEST" \
  build -quiet
