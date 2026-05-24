#!/bin/bash
# Run StellarVolumiOTests via xcodebuild on the iPhone 16 Pro simulator.
#
# Usage:
#   scripts/test.sh                          # all tests
#   scripts/test.sh PlayerStateParserTests   # filter to one suite
#
# Destination resolution:
#   - If IOS_SIM_ID is set in the environment, the test run targets that specific
#     simulator UDID — use this on machines with multiple "iPhone 16 Pro" entries.
#   - If IOS_SIM_ID is unset or empty, the test run falls back to name=iPhone 16 Pro,
#     which works on any fresh Xcode install or CI runner without extra config.
#
# Example (operator with two matching sims):
#   export IOS_SIM_ID=71E156C3-0CC1-4659-86AA-B044DE8CDBEB
#   scripts/test.sh SmokeTest
set -euo pipefail
SIM_ID="${IOS_SIM_ID:-}"
if [ -n "$SIM_ID" ]; then
  DEST="platform=iOS Simulator,id=$SIM_ID"
else
  DEST="platform=iOS Simulator,name=iPhone 16 Pro"
fi
if [ $# -eq 0 ]; then
  exec xcodebuild test \
    -scheme StellarVolumiO \
    -destination "$DEST" \
    -quiet
else
  exec xcodebuild test \
    -scheme StellarVolumiO \
    -destination "$DEST" \
    -only-testing:"StellarVolumiOTests/$1" \
    -quiet
fi
