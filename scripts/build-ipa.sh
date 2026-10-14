#!/bin/bash
# Builds an unsigned build/BrewLog.ipa for sideloading with SideStore / AltStore.
# Needs Xcode and XcodeGen, but no Apple ID. Run from anywhere: ./scripts/build-ipa.sh
# Extra arguments go to xcodebuild, e.g. MARKETING_VERSION=1.0.5 (used by GitHub Actions).
set -euo pipefail

cd "$(dirname "$0")/.."

# Use the full Xcode even when xcode-select points at the Command Line Tools.
if ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcodegen generate

xcodebuild build \
  -project BrewLog.xcodeproj \
  -scheme BrewLog \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -quiet \
  "$@"

rm -rf build/Payload build/BrewLog.ipa
mkdir -p build/Payload
cp -R build/DerivedData/Build/Products/Release-iphoneos/BrewLog.app build/Payload/
(cd build && zip -qry BrewLog.ipa Payload)

echo "Built $(pwd)/build/BrewLog.ipa"
if [ -z "${CI:-}" ]; then open -R build/BrewLog.ipa; fi
