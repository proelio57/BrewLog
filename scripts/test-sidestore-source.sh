#!/usr/bin/env bash
# Tests the iOS notes and the app description of scripts/sidestore_source.py.
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'PY'
import sidestore_source as s

def check(name, got, want):
    assert got == want, f"FAIL {name}: expected {want!r}, got {got!r}"

check("ios section only",
      s.ios_notes("iOS\n• Settings pages\n\nAndroid\n• Dark mode\n\nWeb\n• No changes in this release"),
      "• Settings pages")
check("shared heading", s.ios_notes("iOS & Android\n• Both\n\niOS\n• Only iOS\n\nAndroid\n• Only Android"), "• Both\n• Only iOS")
check("all platforms", s.ios_notes("All platforms\n• Everything\n\nWeb\n• Web only"), "• Everything")
check("android only release", s.ios_notes("iOS\n• No changes in this release\n\nAndroid\n• A thing"), "Bug fixes and improvements.")
check("no changes everywhere", s.ios_notes("All platforms\n• No changes in this release"), "Bug fixes and improvements.")
check("commit subjects are kept", s.ios_notes("• Fix one\n• Fix two"), "• Fix one\n• Fix two")
check("empty", s.ios_notes(""), "Bug fixes and improvements.")
assert "BOOKOO" in s.DESCRIPTION and "espresso" in s.SUBTITLE.lower()
assert len(s.DESCRIPTION) < 1500
print("sidestore source: all tests passed")
PY
