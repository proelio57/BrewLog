#!/usr/bin/env bash
# Release notes for the commit being released (HEAD): what changed, without "Merge pull request …" lines,
# Co-Authored-By trailers or conventional-commit prefixes ("feat(ios): "). For a merge commit the notes are the
# messages of the commits it brings in; otherwise the commit's own message. Needs the history of the merged
# branch (CI: actions/checkout with fetch-depth). At most 2000 characters (SideStore / GitHub release notes).
set -euo pipefail

rev=${1:-HEAD}
if git rev-parse -q --verify "$rev^2" >/dev/null; then
  range=("$rev^1..$rev")
else
  range=(-1 "$rev")
fi

git log --no-merges --reverse --format='%x1e%B' "${range[@]}" | python3 -c '
import re, sys
out = []
for message in sys.stdin.read().split("\x1e"):
    lines = [l.rstrip() for l in message.strip().splitlines()]
    lines = [l for l in lines if not re.match(r"(?i)^(co-authored-by|signed-off-by):", l)]
    if not lines:
        continue
    subject = re.sub(r"^[a-z]+(\([^)]*\))?!?:\s*", "", lines[0])
    subject = subject[:1].upper() + subject[1:]
    body = "\n".join(lines[1:]).strip()
    out.append("• " + subject + ("\n" + body if body else ""))
text = "\n\n".join(out) or "Bug fixes and improvements."
print(text[:2000].rstrip())
'
