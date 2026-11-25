#!/usr/bin/env bash
# Tests scripts/release-notes.sh: one short line per feat/fix/perf commit, nothing from the commit body,
# no trailers, no URLs or session ids. Runs in a throw-away repository.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/release-notes.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q -b main
git config user.name Test
git config user.email test@example.com
git config commit.gpgsign false
git commit -q --allow-empty -m "chore: start"

fail=0
check() {
  local name=$1 expected=$2 actual
  actual=$("$script" HEAD)
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $name"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
    fail=1
  fi
}

# A merged branch with user-facing and internal commits.
git checkout -q -b feature
git commit -q --allow-empty -m "feat(ios): import GaggiMate profiles as espresso recipes

From a profile file or straight from the machine. Phases map to
pre-infusion, yield and pressure.

Co-Authored-By: X <x@y>
Claude-Session: https://claude.ai/code/session_123"
git commit -q --allow-empty -m "fix: the mode switch no longer hitches

The switch was rebuilt on every change."
git commit -q --allow-empty -m "docs: statistics"
git commit -q --allow-empty -m "chore(ci): bump"
git commit -q --allow-empty -m "fix(ios): crash on start, see https://example.com/x (session_01AbC)"
git commit -q --allow-empty -m "fix: thing (see https://x.y/z) for real"
git commit -q --allow-empty -m "feat: add thing Claude-Session: https://claude.ai/code/session_x"
git checkout -q main
git merge -q --no-ff feature -m "Merge pull request #1 from someone/feature

Claude-Session: https://claude.ai/code/session_456"

check merged "• Import GaggiMate profiles as espresso recipes
• The mode switch no longer hitches
• Crash on start
• Thing for real
• Add thing"

# Only internal commits.
git checkout -q -b docs-only
git commit -q --allow-empty -m "docs: readme"
git checkout -q main
git merge -q --no-ff docs-only -m "Merge docs"
check docs-only "Bug fixes and improvements."

# A release that brings RELEASE_NOTES.md: its text (grouped by platform) instead of the commit subjects.
git checkout -q -b curated
printf '<!-- notes for the next release -->\niOS\n• Pressure view\n\nAndroid\n• Dark mode\n' > RELEASE_NOTES.md
git add RELEASE_NOTES.md
git commit -q -m "docs: release notes"
git commit -q --allow-empty -m "feat: something else"
git checkout -q main
git merge -q --no-ff curated -m "Merge curated"
check curated-file "iOS
• Pressure view

Android
• Dark mode"

# Lines that are the same for several platforms are written once under a shared heading.
git checkout -q -b shared
printf 'iOS\n• Same everywhere\n• Only iOS\n\nAndroid\n• Same everywhere\n• Only Android\n\nWeb\n• No changes in this release\n' > RELEASE_NOTES.md
git add RELEASE_NOTES.md
git commit -q -m "docs: shared notes"
git checkout -q main
git merge -q --no-ff shared -m "Merge shared"
check shared-lines "iOS & Android
• Same everywhere

iOS
• Only iOS

Android
• Only Android

Web
• No changes in this release"

git checkout -q -b everywhere
printf 'iOS\n• Same\n\nAndroid\n• Same\n\nWeb\n• Same\n• Web only\n' > RELEASE_NOTES.md
git add RELEASE_NOTES.md
git commit -q -m "docs: notes for everyone"
git checkout -q main
git merge -q --no-ff everywhere -m "Merge everywhere"
check all-platforms "All platforms
• Same

Web
• Web only"

git checkout -q -b nochanges
printf 'iOS\n• A thing\n\nAndroid\n• No changes in this release\n\nWeb\n• No changes in this release\n' > RELEASE_NOTES.md
git add RELEASE_NOTES.md
git commit -q -m "docs: notes with nothing for two platforms"
git checkout -q main
git merge -q --no-ff nochanges -m "Merge nochanges"
check no-changes-merged "iOS
• A thing

Android & Web
• No changes in this release"

# The next release doesn't touch the file: back to commit subjects.
git checkout -q -b after
git commit -q --allow-empty -m "fix: later fix"
git checkout -q main
git merge -q --no-ff after -m "Merge after"
check after-curated "• Later fix"

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "release notes OK"
