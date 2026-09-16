#!/usr/bin/env bash
# Succeeds when every commit since the latest tag is a date-holidays data sync.
# The sync workflow already ran the parity suite on that data, so the release
# PR for it is pure bookkeeping and can merge without a human.
set -euo pipefail

tag=$(git describe --tags --abbrev=0 2>/dev/null) || {
  echo "no release tag yet"
  exit 1
}

subjects=$(git log --format=%s "$tag..HEAD")

if [ -z "$subjects" ]; then
  echo "nothing since $tag"
  exit 1
fi

pattern='^fix: sync date-holidays data [0-9a-f]+$'

if grep -vqE "$pattern" <<< "$subjects"; then
  echo "commits since $tag that are not data syncs:"
  grep -vE "$pattern" <<< "$subjects"
  exit 1
fi

echo "only data syncs since $tag:"
echo "$subjects"
