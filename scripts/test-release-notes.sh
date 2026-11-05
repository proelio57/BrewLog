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

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "release notes OK"
