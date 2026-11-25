#!/usr/bin/env bash
# Tests scripts/whats-new.sh with fixed release notes.
set -euo pipefail
script="$(cd "$(dirname "$0")" && pwd)/whats-new.sh"
fail=0
check() {
  local name=$1 notes=$2 platform=$3 expected=$4 actual
  actual=$(NOTES="$notes" "$script" 2.14.0 | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['$platform'], ensure_ascii=False))")
  if [ "$actual" != "$expected" ]; then echo "FAIL: $name: expected $expected, got $actual"; fail=1; fi
}
grouped=$'iOS\n• Settings are split into pages\n• Compact brew tab\n\nAndroid\n• No changes in this release\n\nWeb\n• No app changes (2.7.0 was a re-run)'
check "ios section" "$grouped" ios '["Settings are split into pages", "Compact brew tab"]'
check "android says no changes" "$grouped" android '[]'
check "web says no app changes" "$grouped" web '[]'
loose=$'• Fixed the chart labels\n• Added a flush button'
check "ungrouped notes apply to ios" "$loose" ios '["Fixed the chart labels", "Added a flush button"]'
check "ungrouped notes apply to android" "$loose" android '["Fixed the chart labels", "Added a flush button"]'
check "fallback line" "Bug fixes and improvements." web '["Bug fixes and improvements."]'
check "missing section is empty" $'iOS\n• One thing' android '[]'
shared=$'iOS & Android\n• Shared line\n\niOS\n• Only iOS\n\nWeb\n• No changes in this release'
check "shared heading: ios" "$shared" ios '["Shared line", "Only iOS"]'
check "shared heading: android" "$shared" android '["Shared line"]'
check "shared heading: web" "$shared" web '[]'
everyone=$'All platforms\n• For everyone\n\nAndroid & Web\n• Not iOS'
check "all platforms: ios" "$everyone" ios '["For everyone"]'
check "all platforms: web" "$everyone" web '["For everyone", "Not iOS"]'
version=$(NOTES="$grouped" "$script" 2.14.0 | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])")
[ "$version" = "2.14.0" ] || { echo "FAIL: version $version"; fail=1; }
[ "$fail" -eq 0 ] && echo "whats-new: all tests passed"
exit $fail
