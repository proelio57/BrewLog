#!/usr/bin/env bash
# The version of the next release: the highest release version of $RELEASE_REPO with the last number + 1
# (v0.1.80 and v0.1.75-web → 0.1.81). iOS and Android use it for the same merge, so both land in one release
# and the numbers only go up, whichever platform built last. Prints "<version> <build>"; build is the last number.
# The release tags come from `gh release list`, or from $RELEASE_TAGS (one per line, for scripts/test-next-version.sh).
set -euo pipefail

if [ -z "${RELEASE_TAGS+x}" ]; then
  RELEASE_TAGS=$(gh release list --repo "${RELEASE_REPO:?RELEASE_REPO not set}" --limit 1000 --json tagName --jq '.[].tagName')
fi

printf '%s\n' "$RELEASE_TAGS" | python3 -c '
import re, sys
versions = []
for tag in sys.stdin.read().split():
    match = re.match(r"^v(\d+)\.(\d+)\.(\d+)(?:-[A-Za-z0-9.-]+)?$", tag)
    if match:
        versions.append(tuple(int(x) for x in match.groups()))
major, minor, patch = max(versions) if versions else (0, 1, 0)
print(f"{major}.{minor}.{patch + 1} {patch + 1}")
'
