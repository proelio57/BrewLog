#!/bin/bash
# Publishes BrewLog for SideStore (run by GitHub Actions):
#   release <ipa> <version> <build>  GitHub release with the .ipa + source.json, recipes.json and icon.png
#   recipes                          only recipes.json (online recipe updates, no app update needed)
# The files live on the "sidestore" branch of $RELEASE_REPO and are served by raw.githubusercontent.com,
# so $RELEASE_REPO must be public. Needs GH_TOKEN with write access to it, plus gh, git and python3.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${RELEASE_REPO:?set RELEASE_REPO=owner/repo}"
: "${GH_TOKEN:?set GH_TOKEN}"
BRANCH=sidestore
RAW="https://raw.githubusercontent.com/$RELEASE_REPO/$BRANCH"
ROOT=$(pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Recipes must be a valid list before they go out to every phone.
python3 - "$ROOT/Shared/recipes.json" <<'PY'
import json, sys
recipes = json.load(open(sys.argv[1], encoding="utf-8"))
assert isinstance(recipes, list) and recipes, "recipes.json must be a non-empty list"
ids = [r["id"] for r in recipes]
assert len(ids) == len(set(ids)), "recipe ids must be unique"
for r in recipes:
    assert r.get("name") and r.get("steps"), f"{r.get('id')}: name and steps are required"
PY

checkout_branch() {
  git -C "$WORK" init -q
  # RELEASE_GIT_URL only for testing against a local repository.
  git -C "$WORK" remote add origin "${RELEASE_GIT_URL:-https://x-access-token:${GH_TOKEN}@github.com/${RELEASE_REPO}.git}"
  if git -C "$WORK" fetch -q --depth 1 origin "$BRANCH" 2>/dev/null; then
    git -C "$WORK" checkout -q -B "$BRANCH" FETCH_HEAD
  else
    git -C "$WORK" checkout -q --orphan "$BRANCH"
    printf '# BrewLog for SideStore\n\nAdd this source in SideStore: %s/source.json\n' "$RAW" > "$WORK/README.md"
  fi
  git -C "$WORK" config user.name "github-actions[bot]"
  git -C "$WORK" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
}

# Commits and pushes the branch, retrying when another run pushed in between.
push_branch() {
  local message=$1 update=$2
  for attempt in 1 2 3 4; do
    "$update"
    git -C "$WORK" add -A
    if git -C "$WORK" diff --cached --quiet; then echo "Nothing to publish"; return 0; fi
    git -C "$WORK" commit -q -m "$message"
    if git -C "$WORK" push -q origin "HEAD:$BRANCH"; then return 0; fi
    echo "Push failed (attempt $attempt), retrying"
    sleep $((attempt * 2))
    git -C "$WORK" fetch -q --depth 1 origin "$BRANCH"
    git -C "$WORK" reset -q --hard FETCH_HEAD
  done
  echo "Could not push to $RELEASE_REPO" >&2
  return 1
}

copy_recipes() { cp "$ROOT/Shared/recipes.json" "$WORK/recipes.json"; }

case "${1:-}" in
  recipes)
    checkout_branch
    push_branch "Recipes from ${GITHUB_SHA:-local}" copy_recipes
    echo "Recipes: $RAW/recipes.json"
    ;;
  release)
    ipa=$2 version=$3 build=$4
    notes=$(git log -1 --format=%B | head -c 2000)
    checkout_branch
    # Make sure the branch exists, so the release tag can point at it (the release repo may be empty).
    push_branch "Set up SideStore branch" copy_recipes
    if gh release view "v$version" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
      gh release upload "v$version" "$ipa" --repo "$RELEASE_REPO" --clobber   # re-run of the same build
    else
      gh release create "v$version" "$ipa" --repo "$RELEASE_REPO" --target "$BRANCH" \
        --title "BrewLog $version" --notes "$notes"
    fi
    update_source() {
      copy_recipes
      cp "$ROOT/BrewLog/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "$WORK/icon.png"
      python3 "$ROOT/scripts/sidestore_source.py" "$WORK/source.json" \
        --version "$version" --build "$build" --ipa "$ipa" \
        --download-url "https://github.com/$RELEASE_REPO/releases/download/v$version/$(basename "$ipa")" \
        --source-url "$RAW/source.json" --icon-url "$RAW/icon.png" --notes "$notes"
    }
    push_branch "BrewLog $version" update_source
    echo "SideStore source: $RAW/source.json"
    ;;
  *)
    echo "usage: $0 release <ipa> <version> <build> | recipes" >&2
    exit 2
    ;;
esac
