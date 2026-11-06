#!/usr/bin/env bash
# Cut a release: point every pin in the repository at the new tag, commit,
# and tag. Nothing is pushed; the last line prints the command for that.
#
#   scripts/release.sh v0.2.0
#
# Run it on main, with a clean tree, after the changes for the release are
# merged. The tagged commit's templates pin the tag itself, so a machine made
# from that release's template gets that release.
set -euo pipefail

version=${1:-}
if ! [[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 vMAJOR.MINOR.PATCH" >&2
  exit 1
fi

cd "$(git rev-parse --show-toplevel)"

if [ -n "$(git status --porcelain)" ]; then
  echo "The working tree is not clean; commit or stash first." >&2
  exit 1
fi
branch=$(git branch --show-current)
if [ "$branch" != main ]; then
  echo "Release from main, not '$branch'." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$version" >/dev/null; then
  echo "$version is already tagged." >&2
  exit 1
fi

# Rewritten by pattern, not by the old value, so a pin that had drifted is
# caught up too. check-version-pins.sh then proves nothing was missed.
mapfile -t files < <(git grep -lE 'wsl-reference/(archive/)?v[0-9]' -- ':!flake.lock')
sed -i -E \
  -e "s#(JesperJ/wsl-reference/)v[0-9][0-9.]*[0-9]#\1$version#g" \
  -e "s#(wsl-reference/archive/)v[0-9][0-9.]*[0-9]\.tar\.gz#\1$version.tar.gz#g" \
  "${files[@]}"
scripts/check-version-pins.sh "$version"

git add -- "${files[@]}"
if git diff --cached --quiet; then
  echo "Every pin already says $version; tagging HEAD."
else
  git commit -q -m "Release $version"
fi
git tag -a "$version" -m "$version"

echo
echo "Tagged $version. Check it, then publish with:"
echo "  git push origin main $version"
