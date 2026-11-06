#!/usr/bin/env bash
# The version of the next release, semantic versioning from the Conventional Commits it brings (like
# scripts/release-notes.sh: for a merge commit the commits it merges, otherwise the commit itself):
#   breaking change ("feat!:" or "BREAKING CHANGE" in a subject) → next major (2.3.1 → 3.0.0)
#   a feat                                                      → next minor (2.3.1 → 2.4.0)
#   anything else (fix, perf, …)                                → next patch (2.3.1 → 2.3.2)
# counted from the highest release version of $RELEASE_REPO. iOS and Android use it for the same merge, so both land
# in one release. Prints "<version>"; the workflows use their run number as build number, which only goes up.
# Test inputs (scripts/test-next-version.sh): $RELEASE_TAGS (one per line) instead of `gh release list`,
# $COMMIT_SUBJECTS (one per line) instead of the git history.
set -euo pipefail

rev=${1:-HEAD}
if [ -z "${RELEASE_TAGS+x}" ]; then
  RELEASE_TAGS=$(gh release list --repo "${RELEASE_REPO:?RELEASE_REPO not set}" --limit 1000 --json tagName --jq '.[].tagName')
fi
if [ -z "${COMMIT_SUBJECTS+x}" ]; then
  if git rev-parse -q --verify "$rev^2" >/dev/null; then range=("$rev^1..$rev"); else range=(-1 "$rev"); fi
  COMMIT_SUBJECTS=$(git log --no-merges --format=%s "${range[@]}")
fi

TAGS="$RELEASE_TAGS" SUBJECTS="$COMMIT_SUBJECTS" python3 -c '
import os, re
versions = []
for tag in os.environ["TAGS"].split():
    match = re.match(r"^v(\d+)\.(\d+)\.(\d+)(?:-[A-Za-z0-9.-]+)?$", tag)
    if match:
        versions.append(tuple(int(x) for x in match.groups()))
major, minor, patch = max(versions) if versions else (0, 1, 0)
subjects = [s.strip() for s in os.environ["SUBJECTS"].splitlines() if s.strip()]
types = [re.match(r"^([a-z]+)(\([^)]*\))?(!)?:", s) for s in subjects]
if any(m and m.group(3) for m in types) or any("BREAKING CHANGE" in s for s in subjects):
    print(f"{major + 1}.0.0")
elif any(m and m.group(1) == "feat" for m in types):
    print(f"{major}.{minor + 1}.0")
else:
    print(f"{major}.{minor}.{patch + 1}")
'
