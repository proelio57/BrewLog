#!/usr/bin/env bash
# The notes of the release being built as JSON, for the apps' "What's new" screen after an update:
#   {"version": "2.14.0", "ios": ["…"], "android": ["…"], "web": ["…"]}
# CI writes it to Shared/whats-new.json (bundled by iOS and Android) before the build. The notes are those of
# scripts/release-notes.sh: hand-written ones are grouped by platform ("iOS", "Android", "Web" with "• " lines);
# notes without those headings (commit subjects) apply to every platform. A platform whose lines all say
# "No changes …" gets an empty list, and an app shows nothing for an empty list.
# Usage: whats-new.sh VERSION [REV]. Test: scripts/test-whats-new.sh ($NOTES replaces release-notes.sh's output).
set -euo pipefail

version=${1:?version}
rev=${2:-HEAD}
if [ -z "${NOTES+x}" ]; then
  NOTES=$("$(cd "$(dirname "$0")" && pwd)/release-notes.sh" "$rev")
fi

VERSION="$version" NOTES="$NOTES" python3 -c '
import json, os, re
platforms = {"ios": "ios", "android": "android", "web": "web"}
sections = {}
current = None
loose = []
for raw in os.environ["NOTES"].splitlines():
    line = raw.strip()
    if not line:
        continue
    if line.lower() in platforms:
        current = platforms[line.lower()]
        sections.setdefault(current, [])
        continue
    text = re.sub(r"^[•\-*]\s*", "", line)
    if re.match(r"(?i)^no (app )?changes\b", text):
        continue
    (sections[current] if current else loose).append(text)
result = {"version": os.environ["VERSION"]}
for key in platforms.values():
    # Grouped notes: only the platform'"'"'s own section. Ungrouped ones apply to every platform.
    result[key] = sections.get(key, []) if sections else loose
print(json.dumps(result, ensure_ascii=False, indent=2))
'
