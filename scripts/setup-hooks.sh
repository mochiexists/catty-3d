#!/bin/bash
#
# scripts/setup-hooks.sh
#
# Install the pre-commit hook into .git/hooks/. Run once after cloning
# the repo (and again after creating a new worktree). Mirrors the
# pattern used by Local AI Chat — keeps xcodegen in sync with project.yml
# and runs swiftlint on staged Swift before commit.
#

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"
SRC_HOOK="$REPO_ROOT/scripts/pre-commit"

if [ ! -f "$SRC_HOOK" ]; then
  echo "✗ scripts/pre-commit missing; nothing to install"
  exit 1
fi

mkdir -p "$HOOKS_DIR"
cp "$SRC_HOOK" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"

echo "✓ Installed pre-commit hook → $HOOKS_DIR/pre-commit"
