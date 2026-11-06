#!/usr/bin/env bash
# Every place this repository names one of its own releases must name the
# same one -- and, given a version, that version.
#
#   scripts/check-version-pins.sh            # the pins agree with each other
#   scripts/check-version-pins.sh v0.2.0     # ...and they say v0.2.0
#
# The pins are what a new machine gets: templates/*/flake.nix pin wsl-base to
# a tag, and the README's flakeless example fetches a tag's tarball. A release
# that forgets one of them hands new machines the previous version. Used by
# CI on every push (and with the tag's name on a tag push), and by
# scripts/release.sh before it tags anything.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
expected=${1:-}

pattern='wsl-reference/(archive/)?v[0-9]+\.[0-9]+\.[0-9]+'
versions=$(git grep -ohE "$pattern" -- ':!flake.lock' | grep -oE 'v[0-9.]+$' | sort -u)
count=$(printf '%s' "$versions" | grep -c . || true)

if [ "$count" -eq 0 ]; then
  echo "No release pins found. Has the pin format changed? Update the pattern here." >&2
  exit 1
fi
if [ "$count" -gt 1 ]; then
  echo "Release pins disagree:" >&2
  git grep -nE "$pattern" -- ':!flake.lock' >&2
  exit 1
fi
if [ -n "$expected" ] && [ "$versions" != "$expected" ]; then
  echo "Release pins say $versions, expected $expected:" >&2
  git grep -nE "$pattern" -- ':!flake.lock' >&2
  exit 1
fi
echo "Release pins: $versions"
