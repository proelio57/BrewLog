#!/usr/bin/env bash
# Release notes for the commit being released (HEAD): one short line per change users notice, i.e. the subject line
# of commits of type feat, fix or perf ("feat(ios): …"), without the type prefix. Commit bodies, trailers
# (Co-Authored-By, Claude-Session …), links and session ids are left out, as are CI, build, docs, chore, test and
# refactor commits and merge lines. Test: scripts/test-release-notes.sh. For a merge commit the notes come from the commits it brings
# in; otherwise from the commit itself. Needs the history of the merged
# branch (CI: actions/checkout with fetch-depth). At most 2000 characters (SideStore / GitHub release notes).
set -euo pipefail

rev=${1:-HEAD}
if git rev-parse -q --verify "$rev^2" >/dev/null; then
  range=("$rev^1..$rev")
else
  range=(-1 "$rev")
fi

git log --no-merges --reverse --format='%x1e%s' "${range[@]}" | python3 -c '
import re, sys
out = []
for subject in sys.stdin.read().split("\x1e"):
    subject = subject.strip()
    match = re.match(r"^([a-z]+)(\([^)]*\))?!?:\s*", subject)
    # Only user-facing changes; untyped commits (e.g. edits on github.com) are not release notes either.
    if not match or match.group(1) not in ("feat", "fix", "perf"):
        continue
    subject = subject[match.end():]
    # No links or session ids in the notes, and no "see" / brackets they leave behind.
    cleaned = re.sub(r"https?://\S+|\bsession_[A-Za-z0-9]+", "", subject)
    if cleaned != subject:
        cleaned = re.sub(r"\(\s*\)", "", cleaned)
        cleaned = re.sub(r"[\s,;:]*(\bsee\b)?[\s,;:]*$", "", cleaned)
    subject = cleaned.strip()
    if not subject:
        continue
    out.append("• " + subject[:1].upper() + subject[1:])
text = "\n".join(out) or "Bug fixes and improvements."
print(text[:2000].rstrip())
'
