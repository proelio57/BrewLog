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
  changed="$rev^1..$rev"
else
  range=(-1 "$rev")
  changed="$rev~1..$rev"
fi

# Notes written by hand: a release whose commits change RELEASE_NOTES.md (repo root) uses that file, grouped by
# platform ("iOS", "Android", "Web" with "• " lines under each). HTML comments in it are left out. A line that is
# the same for several platforms is written once, under a shared heading ("iOS & Android", "All platforms").
if git diff --name-only "$changed" -- RELEASE_NOTES.md 2>/dev/null | grep -q .; then
  git show "$rev:RELEASE_NOTES.md" | python3 -c '
import re, sys
PLATFORMS = ["iOS", "Android", "Web"]
text = re.sub(r"<!--.*?-->", "", sys.stdin.read(), flags=re.S).strip()
sections, loose, current = {}, [], None
for raw in text.splitlines():
    line = raw.strip()
    if not line:
        continue
    if line in PLATFORMS:
        current = line
        sections.setdefault(current, [])
        continue
    (sections[current] if current else loose).append(line)
if sections:
    # Which platforms share each line (in the order the lines first appear).
    owners = {}
    for platform in PLATFORMS:
        for line in sections.get(platform, []):
            owners.setdefault(line, [])
            if platform not in owners[line]:
                owners[line].append(platform)
    groups = {}
    for line, platforms in owners.items():
        groups.setdefault(tuple(platforms), []).append(line)
    # Shared groups first (the widest first), then each platform on its own; "No changes" lines come last.
    def empty(key):
        return all(re.match(r"(?i)^(•|-|\*)?\s*no (app )?changes", line) for line in groups[key])
    keys = sorted(groups, key=lambda k: (empty(k), -len(k), [PLATFORMS.index(p) for p in k]))
    blocks = (["\n".join(loose)] if loose else [])
    for key in keys:
        heading = "All platforms" if len(key) == len(PLATFORMS) else " & ".join(key)
        blocks.append(heading + "\n" + "\n".join(groups[key]))
    text = "\n\n".join(blocks)
print((text or "Bug fixes and improvements.")[:2000].rstrip())
'
  exit 0
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
    # No links, session ids or trailer names in the notes, and no "see" / brackets they leave behind.
    cleaned = re.sub(r"(?i)\b(co-authored-by|signed-off-by|claude-session)\b\s*:?", "", subject)
    cleaned = re.sub(r"https?://\S+|\bsession_[A-Za-z0-9]+", "", cleaned)
    if cleaned != subject:
        cleaned = re.sub(r"\(\s*(see\b)?\s*\)", "", cleaned)
        cleaned = re.sub(r"\(\s*see\b\s*", "", cleaned)
        if cleaned.count("(") > cleaned.count(")"):
            i = cleaned.rfind("(")
            cleaned = cleaned[:i] + cleaned[i + 1:]
        cleaned = re.sub(r"[\s,;:]*(\bsee\b)?[\s,;:]*$", "", cleaned)
        cleaned = re.sub(r"\s{2,}", " ", cleaned)
    subject = cleaned.strip()
    if not subject:
        continue
    out.append("• " + subject[:1].upper() + subject[1:])
text = "\n".join(out) or "Bug fixes and improvements."
print(text[:2000].rstrip())
'
