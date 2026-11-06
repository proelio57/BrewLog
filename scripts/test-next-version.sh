#!/usr/bin/env bash
# Tests scripts/next-version.sh with fixed release tags and commit subjects.
set -euo pipefail
script="$(cd "$(dirname "$0")" && pwd)/next-version.sh"
fail=0
check() {
  local name=$1 tags=$2 subjects=$3 expected=$4 actual
  actual=$(RELEASE_TAGS="$tags" COMMIT_SUBJECTS="$subjects" "$script")
  if [ "$actual" != "$expected" ]; then echo "FAIL: $name: expected '$expected', got '$actual'"; fail=1; fi
}
check "fix → patch" $'v2.0.0\nv1.0.5' "fix(ios): crash" "2.0.1"
check "feat → minor" $'v2.0.3' $'fix: a\nfeat(android): b' "2.1.0"
check "breaking → major" $'v2.4.1' $'feat!: new data format\nfix: c' "3.0.0"
check "BREAKING CHANGE → major" $'v2.4.1' "refactor: BREAKING CHANGE storage" "3.0.0"
check "only ci/docs → patch" $'v2.0.0' $'ci: x\ndocs: y' "2.0.1"
check "highest across platforms" $'v0.1.48\nv0.1.80\nv1.0.5\nv2.0.0' "fix: z" "2.0.1"
check "numeric, not alphabetical" $'v2.9.0\nv2.10.0' "fix: z" "2.10.1"
check "suffixed tags count" $'v2.1.0-web\nv2.0.0' "fix: z" "2.1.1"
check "no releases yet" "" "feat: first" "0.2.0"
[ "$fail" -eq 0 ] && echo "next-version: all tests passed"
exit $fail
