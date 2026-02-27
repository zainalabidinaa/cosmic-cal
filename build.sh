#!/bin/bash
set -e

# Requires: Xcode 26+, XcodeGen
# Install XcodeGen: brew install xcodegen

if ! command -v xcodegen &>/dev/null; then
    echo "Error: XcodeGen not found. Install with: brew install xcodegen"
    exit 1
fi

XCODE_VER=$(xcodebuild -version 2>/dev/null | awk 'NR==1{print $2}')
XCODE_MAJOR=$(echo "$XCODE_VER" | cut -d. -f1)

if [ -z "$XCODE_MAJOR" ] || [ "$XCODE_MAJOR" -lt 26 ]; then
    echo "Error: Xcode 26 or later is required (found: ${XCODE_VER:-none})."
    echo "Download Xcode 26 from https://developer.apple.com/xcode/"
    exit 1
fi

echo "Xcode $XCODE_VER — OK"
echo "Generating Xcode project..."
xcodegen generate --spec project.yml

DESTINATION="${1:-platform=iOS,id=00008130-000145483E21001C}"

echo "Building for: $DESTINATION"
xcodebuild \
    -project WorkLog.xcodeproj \
    -scheme WorkLog \
    -configuration Debug \
    -destination "$DESTINATION" \
    -allowProvisioningUpdates \
    build | xcpretty 2>/dev/null || xcodebuild \
    -project WorkLog.xcodeproj \
    -scheme WorkLog \
    -configuration Debug \
    -destination "$DESTINATION" \
    -allowProvisioningUpdates \
    build

echo "Build succeeded."
