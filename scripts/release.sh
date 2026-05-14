#!/bin/bash
# release.sh — safe wrapper for dispatching the Outdoor (Direct Download)
# release workflow. Mirrors localaicat's pattern.
#
# Why this exists: `gh workflow run` checks out origin/<branch>, not your
# local branch. If outdoor-cat is unpushed, the runner builds an old SHA
# and you ship a release that contains none of your fixes. This blocks
# that.
#
# Usage:
#   scripts/release.sh 0.1.0 1
#
# Args:
#   $1  version (X.Y or X.Y.Z)
#   $2  build number (positive integer, must be strictly greater than the
#       max prior released build)

set -euo pipefail

VERSION="${1:-}"
BUILD="${2:-}"

if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
  cat <<USAGE
Usage: $0 <version> <build_number>

  version       X.Y or X.Y.Z (e.g. 0.1.0)
  build_number  positive integer, monotonic across all releases

Example:
  $0 0.1.0 1

The workflow validates: clean tree, on outdoor-cat, pushed to origin,
build number > all prior releases. Tag-pushing alternative:
  git tag release/v${VERSION:-X.Y.Z}+${BUILD:-N} outdoor-cat
  git push origin release/v${VERSION:-X.Y.Z}+${BUILD:-N}
USAGE
  exit 1
fi

if ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "ERROR: build_number must be a positive integer (got: $BUILD)" >&2
  exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "ERROR: version must look like X.Y or X.Y.Z (got: $VERSION)" >&2
  exit 1
fi

# 1) Must be on outdoor-cat (the release source branch). main is the
# Indoor / App Store quality bar; main fast-forwards from outdoor-cat
# after a successful Outdoor release.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "outdoor-cat" ]; then
  echo "ERROR: releases must dispatch from outdoor-cat (currently on '$BRANCH')" >&2
  echo "       Switch with: git checkout outdoor-cat" >&2
  exit 1
fi

# 2) Working tree must be clean.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "ERROR: working tree has uncommitted changes:" >&2
  git status --short >&2
  exit 1
fi

# 3) origin must match HEAD — magic auto-pushing as a release side-effect
# is too easy to misuse.
echo "▶ Fetching origin/outdoor-cat..."
git fetch origin outdoor-cat --quiet 2>/dev/null || true

UNPUSHED="$(git rev-list --count origin/outdoor-cat..HEAD 2>/dev/null || echo 0)"
if [ "$UNPUSHED" -gt 0 ]; then
  echo
  echo "ERROR: local outdoor-cat is $UNPUSHED commit(s) ahead of origin/outdoor-cat:" >&2
  git log --oneline "origin/outdoor-cat..HEAD" >&2
  echo >&2
  echo "  Push first:  git push origin outdoor-cat" >&2
  exit 1
fi

# 4) Confirm interactively unless --yes.
if [ "${3:-}" != "--yes" ]; then
  echo
  echo "About to dispatch:"
  echo "  workflow:     release-direct.yml"
  echo "  version:      $VERSION"
  echo "  build_number: $BUILD"
  echo "  branch:       outdoor-cat @ $(git rev-parse --short HEAD)"
  echo
  read -r -p "Proceed? [y/N] " ans
  case "$ans" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

gh workflow run release-direct.yml \
  --ref outdoor-cat \
  -f "version=$VERSION" \
  -f "build_number=$BUILD"

echo
echo "✓ dispatched. Watch progress:"
echo "  gh run watch -R \"$(gh repo view --json nameWithOwner --jq .nameWithOwner)\""
