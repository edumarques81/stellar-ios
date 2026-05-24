#!/bin/bash
# Build the iOS app for the iPhone 16 Pro simulator. Used as the compile-check
# after each code change during plan execution.
#
# Uses a UDID to disambiguate when multiple "iPhone 16 Pro" simulators exist.
# If this UDID is stale, run: xcrun simctl list devices | grep "iPhone 16 Pro"
# and update the id below.
set -euo pipefail
SIM_ID="${IOS_SIM_ID:-71E156C3-0CC1-4659-86AA-B044DE8CDBEB}"
exec xcodebuild \
  -scheme StellarVolumiO \
  -destination "platform=iOS Simulator,id=${SIM_ID}" \
  build -quiet
