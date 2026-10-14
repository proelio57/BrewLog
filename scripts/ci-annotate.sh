#!/bin/bash
# Turns compiler and test errors in an xcodebuild log into GitHub annotations,
# so they're readable on the run's summary page (job logs need a login).
# Usage: scripts/ci-annotate.sh build.log
log=$1
root="${GITHUB_WORKSPACE:-$(pwd)}/"
errors=$(grep -E '^/.+:[0-9]+:([0-9]+:)? (fatal )?error: ' "$log" | sed "s|$root||" | sort -u | head -40)
[ -z "$errors" ] && errors=$(grep -E 'error:|\*\* .* FAILED \*\*|Testing failed' "$log" | sort -u | head -20)
[ -z "$errors" ] && exit 0
n=0
while IFS= read -r line; do
  n=$((n + 1))
  [ "$n" -gt 9 ] && break
  if [[ $line =~ ^([^:]+):([0-9]+):([0-9]+:)?\ (fatal\ )?error:\ (.*)$ ]]; then
    echo "::error file=${BASH_REMATCH[1]},line=${BASH_REMATCH[2]}::${BASH_REMATCH[5]}"
  else
    echo "::error::$line"
  fi
done <<< "$errors"
# All of them in one annotation (newlines encoded for the workflow command).
echo "::error title=All errors::$(printf '%s\n' "$errors" | sed ':a;N;$!ba;s/%/%25/g;s/\n/%0A/g')"
