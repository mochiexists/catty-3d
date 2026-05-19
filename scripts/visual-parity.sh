#!/usr/bin/env bash
#
# visual-parity.sh — before/after screenshot parity for the Catty 3D
# renderer. The safety net for the Phase-2 rendering decomposition
# (docs/planning/oss-refactor-plan.md): catches wrong mesh, misplaced
# pane, broken texture/material binding, wrong camera — things unit
# tests can't see.
#
# How it works:
#   1. Build + run the deterministic parity UI tests on a BASELINE git
#      ref (its production code) → baseline PNGs.
#   2. Same on the current working tree → current PNGs.
#   3. Perceptual-diff each pair; fail if any moves more than the
#      threshold. Diffs land in .parity/diff/ for inspection.
#
# The parity tests run with CATTY_DETERMINISTIC_RENDER=1 (frozen scene,
# no starfield, scripted terminal) so a non-zero diff means the
# rendering ACTUALLY changed — not animation noise.
#
# Usage:
#   scripts/visual-parity.sh [BASELINE_REF] [--threshold PCT]
#     BASELINE_REF  git ref to compare against (default: origin/main)
#     --threshold   max changed-pixel %% before FAIL (default: 0.10)
#
# Requirements: xcodegen, xcodebuild, ImageMagick (magick), git.
#
# IMPORTANT: BASELINE_REF must already contain this parity harness
# (deterministic mode + CattyParityUITests). Refs older than the
# harness commit have no deterministic rendering and can't be a valid
# baseline — the script detects this and errors clearly. Normal flow:
# branch off main (which has the harness), refactor, then run
# `scripts/visual-parity.sh main`.

set -euo pipefail

BASELINE_REF="origin/main"
THRESHOLD_PCT="0.10"
while [ $# -gt 0 ]; do
  case "$1" in
    --threshold) THRESHOLD_PCT="$2"; shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) BASELINE_REF="$1"; shift ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
WORK="$ROOT/.parity"
WT="$WORK/baseline-src"
SCHEME="Catty"
ONLY="-only-testing:CattyUITests/CattyParityUITests"

for tool in xcodegen xcodebuild magick git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "::error::missing required tool: $tool"; exit 2; }
done

cleanup() { git worktree remove --force "$WT" >/dev/null 2>&1 || true; }
trap cleanup EXIT

rm -rf "$WORK"
mkdir -p "$WORK/baseline" "$WORK/current" "$WORK/diff"

# A run = generate project, ensure unsigned local config, run the
# deterministic parity test class, collecting PNGs into $1.
run_capture() {
  local out_dir="$1" src_dir="$2" label="$3"
  echo "▶ Capturing $label ($src_dir)"
  ( cd "$src_dir"
    [ -f Local.xcconfig ] || cp Local.example.xcconfig Local.xcconfig
    xcodegen generate >/dev/null
    SNAPSHOT_MAC_OUTPUT_DIR="$out_dir" \
      xcodebuild test \
        -project Catty.xcodeproj \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination 'platform=macOS' \
        CODE_SIGNING_ALLOWED=NO \
        $ONLY >/dev/null 2>&1 ) \
    || { echo "::error::parity test run failed for $label"; exit 1; }
  local n; n=$(find "$out_dir" -name 'parity_*.png' | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || { echo "::error::$label produced no parity_*.png"; exit 1; }
  echo "  $n shots"
}

# Baseline: isolated worktree of the ref (never touches the working tree).
git worktree add --detach "$WT" "$BASELINE_REF" >/dev/null 2>&1 \
  || { echo "::error::cannot create worktree for '$BASELINE_REF'"; exit 2; }
if [ ! -f "$WT/UITests/CattyParityUITests.swift" ]; then
  echo "::error::'$BASELINE_REF' predates the parity harness — pick a ref at/after the harness commit."
  exit 2
fi
run_capture "$WORK/baseline" "$WT" "baseline ($BASELINE_REF)"

# Current working tree.
run_capture "$WORK/current" "$ROOT" "current (working tree)"

# Diff. ImageMagick AE (absolute error) with a small fuzz to absorb
# sub-pixel AA jitter; fail when changed pixels exceed the threshold.
echo
echo "▶ Diff (threshold ${THRESHOLD_PCT}% changed pixels)"
fails=0
shopt -s nullglob
for base in "$WORK"/baseline/parity_*.png; do
  name="$(basename "$base")"
  cur="$WORK/current/$name"
  if [ ! -f "$cur" ]; then
    echo "  ✗ $name — missing in current"
    fails=$((fails + 1)); continue
  fi
  read -r w h < <(magick identify -format '%w %h' "$base")
  total=$((w * h))
  ae=$(magick compare -metric AE -fuzz 2% "$base" "$cur" "$WORK/diff/$name" 2>&1 || true)
  ae=${ae%%.*}; [ -z "$ae" ] && ae=0
  pct=$(awk -v a="$ae" -v t="$total" 'BEGIN{printf "%.4f", t? a*100.0/t : 100}')
  over=$(awk -v p="$pct" -v th="$THRESHOLD_PCT" 'BEGIN{print (p>th)?1:0}')
  if [ "$over" = "1" ]; then
    echo "  ✗ $name — ${pct}% changed (${ae}/${total} px)"
    fails=$((fails + 1))
  else
    echo "  ✓ $name — ${pct}% changed"
  fi
done

echo
if [ "$fails" -eq 0 ]; then
  echo "RESULT: PARITY HELD — rendering is byte-equivalent within tolerance."
  exit 0
fi
echo "RESULT: ${fails} REGRESSION(S) — inspect .parity/diff/*.png"
exit 1
