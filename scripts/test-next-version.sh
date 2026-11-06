#!/usr/bin/env bash
# Tests scripts/next-version.sh with fixed release tags.
set -euo pipefail
script="$(cd "$(dirname "$0")" && pwd)/next-version.sh"
fail=0
check() {
  local name=$1 tags=$2 expected=$3 actual
  actual=$(RELEASE_TAGS="$tags" "$script")
  if [ "$actual" != "$expected" ]; then echo "FAIL: $name: expected '$expected', got '$actual'"; fail=1; fi
}
check "highest across platforms" $'v0.1.48\nv0.1.80\nv0.1.79\nv0.1.46' "0.1.81 81"
check "numeric, not alphabetical" $'v0.1.9\nv0.1.10' "0.1.11 11"
check "suffixed tags count" $'v0.1.75-web\nv0.1.74-android\nv0.1.73' "0.1.76 76"
check "other tags ignored" $'recipes\nv0.1.5\nlatest' "0.1.6 6"
check "no releases yet" "" "0.1.1 1"
[ "$fail" -eq 0 ] && echo "next-version: all tests passed"
exit $fail
