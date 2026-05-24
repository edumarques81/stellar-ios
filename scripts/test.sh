#!/bin/bash
# Run StellarVolumiOTests via xcodebuild on the iPhone 16 Pro simulator.
#
# Usage:
#   scripts/test.sh                          # all tests
#   scripts/test.sh PlayerStateParserTests   # filter to one suite
#
# Uses a UDID to disambiguate when multiple "iPhone 16 Pro" simulators exist.
# If this UDID is stale, run: xcrun simctl list devices | grep "iPhone 16 Pro"
# and update the id below (or set IOS_SIM_ID in your environment).
set -euo pipefail
SIM_ID="${IOS_SIM_ID:-71E156C3-0CC1-4659-86AA-B044DE8CDBEB}"
if [ $# -eq 0 ]; then
  exec xcodebuild test \
    -scheme StellarVolumiO \
    -destination "platform=iOS Simulator,id=${SIM_ID}" \
    -quiet
else
  exec xcodebuild test \
    -scheme StellarVolumiO \
    -destination "platform=iOS Simulator,id=${SIM_ID}" \
    -only-testing:"StellarVolumiOTests/$1" \
    -quiet
fi
