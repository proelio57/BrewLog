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

# The build is unsigned, so the App Group entitlement (widgets) isn't in the binaries yet. ldid writes it in;
# SideStore keeps it when signing, registers the group for your team and updates ALTAppGroups in Info.plist.
app=build/Payload/BrewLog.app
if command -v ldid >/dev/null 2>&1; then
  group=$(/usr/libexec/PlistBuddy -c 'Print :ALTAppGroups:0' "$app/Info.plist" 2>/dev/null || true)
  if [ -n "$group" ]; then
    ent=$(mktemp)
    cat > "$ent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.application-groups</key><array><string>$group</string></array>
</dict></plist>
PLIST
    for appex in "$app"/PlugIns/*.appex; do
      [ -d "$appex" ] && ldid -S"$ent" "$appex/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$appex/Info.plist")"
    done
    ldid -S"$ent" "$app/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")"
    rm -f "$ent"
    echo "Added App Group entitlement $group"
  fi
else
  echo "warning: ldid not found, widgets will show no data (brew install ldid)"
fi
(cd build && zip -qry BrewLog.ipa Payload)

echo "Built $(pwd)/build/BrewLog.ipa"
if [ -z "${CI:-}" ]; then open -R build/BrewLog.ipa; fi
