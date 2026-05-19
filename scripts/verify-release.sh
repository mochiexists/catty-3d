#!/usr/bin/env bash
# verify-release.sh — End-to-end consistency check for a Catty 3D release.
#
# Confirms the GitHub release, the published DMG, the Homebrew cask, the
# Sparkle appcast, and the `curl … | sh` install.sh all agree on version
# + checksum + size + bundle name, so a `brew install`, a Sparkle
# auto-update, or the install script can't break on a stale sha256, a
# version skew, or a renamed .app bundle.
#
# Usage:
#   scripts/verify-release.sh [VERSION]     # default: latest catty3d-site release
#   scripts/verify-release.sh 0.1.2
#   scripts/verify-release.sh 0.1.2 --brew  # also do a real brew install/uninstall smoke test
#
# Requires: gh (authed with access to the mochiexists repos), curl, shasum.
# Exit code: 0 = all aligned, 1 = a mismatch (details printed).

set -euo pipefail

SITE_REPO="mochiexists/catty3d-site"
TAP_REPO="mochiexists/homebrew-catty3d"
CASK_PATH="Casks/catty.rb"

C_G='\033[0;32m'; C_R='\033[0;31m'; C_Y='\033[1;33m'; C_N='\033[0m'
fails=0
pass() { echo -e "  ${C_G}✓${C_N} $1"; }
fail() { echo -e "  ${C_R}✗${C_N} $1"; fails=$((fails + 1)); }
info() { echo -e "  ${C_Y}·${C_N} $1"; }

VERSION="${1:-}"
DO_BREW=false
for a in "$@"; do [ "$a" = "--brew" ] && DO_BREW=true; done

# 1. Resolve version from the latest release if not given.
if [ -z "$VERSION" ] || [ "$VERSION" = "--brew" ]; then
  VERSION=$(gh release view -R "$SITE_REPO" --json tagName --jq '.tagName' 2>/dev/null | sed 's/^v//')
  [ -z "$VERSION" ] && { echo "Could not resolve latest release version."; exit 1; }
fi
TAG="v${VERSION}"
echo "▶ Verifying Catty release ${TAG}"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
DMG="Catty-${VERSION}.dmg"

# 2. GitHub release + expected assets.
echo "— GitHub release ($SITE_REPO) —"
assets=$(gh release view "$TAG" -R "$SITE_REPO" --json assets --jq '.assets[].name' 2>/dev/null || true)
[ -z "$assets" ] && { fail "release $TAG not found on $SITE_REPO"; echo "RESULT: FAIL"; exit 1; }
for want in "$DMG" "Catty.dmg" "appcast.xml"; do
  echo "$assets" | grep -qx "$want" && pass "asset present: $want" || fail "asset MISSING: $want"
done

# 3. Download the DMG; compute size + sha256 (the source of truth).
echo "— DMG —"
url="https://github.com/${SITE_REPO}/releases/download/${TAG}/${DMG}"
code=$(curl -s -o "$WORK/$DMG" -w "%{http_code}" -L --max-time 120 "$url")
[ "$code" = "200" ] && pass "DMG downloads (HTTP 200)" || fail "DMG download HTTP $code ($url)"
DMG_SIZE=$(wc -c < "$WORK/$DMG" | tr -d ' ')
DMG_SHA=$(shasum -a 256 "$WORK/$DMG" | awk '{print $1}')
info "size=$DMG_SIZE  sha256=$DMG_SHA"
# fixed-name Catty.dmg must be the same file
lcode=$(curl -s -o "$WORK/latest.dmg" -w "%{http_code}" -L --max-time 120 \
  "https://github.com/${SITE_REPO}/releases/latest/download/Catty.dmg")
LSHA=$(shasum -a 256 "$WORK/latest.dmg" 2>/dev/null | awk '{print $1}')
[ "$lcode" = "200" ] && [ "$LSHA" = "$DMG_SHA" ] \
  && pass "latest/Catty.dmg == ${DMG}" \
  || fail "latest/Catty.dmg mismatch (http=$lcode sha=$LSHA)"

# 4. Homebrew cask: version + sha256 must match the DMG.
echo "— Homebrew cask ($TAP_REPO/$CASK_PATH) —"
CASK_APP=""
cask=$(gh api "repos/${TAP_REPO}/contents/${CASK_PATH}" --jq '.content' 2>/dev/null | base64 -d || true)
if [ -z "$cask" ]; then
  fail "cask $CASK_PATH not found in $TAP_REPO"
else
  CASK_VER=$(echo "$cask" | grep -E '^\s*version ' | head -1 | sed -E 's/.*version "([^"]+)".*/\1/')
  CASK_SHA=$(echo "$cask" | grep -E '^\s*sha256 ' | head -1 | sed -E 's/.*sha256 "([^"]+)".*/\1/')
  CASK_APP=$(echo "$cask" | grep -E '^\s*app ' | head -1 | sed -E 's/.*app "([^"]+)".*/\1/')
  [ "$CASK_VER" = "$VERSION" ] && pass "cask version = $VERSION" || fail "cask version '$CASK_VER' != '$VERSION'"
  [ "$CASK_SHA" = "$DMG_SHA" ] && pass "cask sha256 == DMG sha256" || fail "cask sha256 '$CASK_SHA' != DMG '$DMG_SHA'"
fi

# 5. Sparkle appcast: shortVersionString + enclosure length must match.
echo "— Sparkle appcast —"
ac=$(curl -s -L --max-time 30 "https://github.com/${SITE_REPO}/releases/download/${TAG}/appcast.xml" || true)
AC_VER=$(echo "$ac" | tr '>' '\n' | grep -A1 'sparkle:shortVersionString' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
AC_LEN=$(echo "$ac" | grep -oE 'length="[0-9]+"' | head -1 | grep -oE '[0-9]+')
echo "$ac" | grep -q 'sparkle:edSignature="[^"]\{20,\}"' && pass "appcast is EdDSA-signed" || fail "appcast missing/short edSignature"
[ "$AC_VER" = "$VERSION" ] && pass "appcast version = $VERSION" || fail "appcast version '$AC_VER' != '$VERSION'"
[ "$AC_LEN" = "$DMG_SIZE" ] && pass "appcast enclosure length == DMG size" || fail "appcast length '$AC_LEN' != DMG '$DMG_SIZE'"

# 6. install.sh — the `curl … | sh` path must resolve the same repo,
#    the same DMG bytes, and the same .app bundle name as the cask.
echo "— install.sh ($SITE_REPO/public/install.sh) —"
ish=$(gh api "repos/${SITE_REPO}/contents/public/install.sh" --jq '.content' 2>/dev/null | base64 -d || true)
if [ -z "$ish" ]; then
  fail "install.sh not found in $SITE_REPO"
else
  ISH_REPO=$(echo "$ish" | grep -E '^REPO=' | head -1 | sed -E 's/^REPO="?([^"#]+)"?.*/\1/' | tr -d ' ' || true)
  [ "$ISH_REPO" = "$SITE_REPO" ] \
    && pass "install.sh REPO = $SITE_REPO" \
    || fail "install.sh REPO '$ISH_REPO' != '$SITE_REPO'"

  # Model install.sh's resolution — "the latest release, first asset
  # whose URL ends in .dmg" — deterministically via `gh api --jq`.
  # install.sh itself awk-parses the *pretty* JSON that an unauthed
  # runtime `curl` returns; that endpoint is rate-limited from shared
  # CI runners and an authed fetch returns *compact* JSON the awk can't
  # read, so we assert the same resolved result format-independently.
  # install.sh resolves via the releases/latest pointer. Run as a
  # post-publish gate, that pointer can lag a few seconds behind the
  # `gh release create --latest` we just did. Poll with a bounded
  # retry so the gate tests install.sh's real path without flaking on
  # propagation; if it never converges it's a genuine failure (latest
  # doesn't point at this release) and we hard-fail below.
  ISH_TAG=""; ISH_URL=""
  for attempt in 1 2 3 4 5 6; do
    ISH_TAG=$(gh api "repos/${SITE_REPO}/releases/latest" --jq '.tag_name' 2>/dev/null || true)
    ISH_URL=$(gh api "repos/${SITE_REPO}/releases/latest" \
      --jq '[.assets[].browser_download_url | select(test("\\.dmg$";"i"))][0] // ""' 2>/dev/null || true)
    [ "$ISH_TAG" = "$TAG" ] && break
    if [ "$attempt" -lt 6 ]; then
      info "releases/latest = '${ISH_TAG:-<none>}', awaiting $TAG (retry $attempt/5)"
      sleep 5
    fi
  done
  [ "$ISH_TAG" = "$TAG" ] \
    && pass "releases/latest tag = $TAG (install.sh + cask livecheck agree)" \
    || fail "releases/latest tag '$ISH_TAG' != '$TAG' after retries"
  if [ -z "$ISH_URL" ]; then
    fail "install.sh would find no .dmg on releases/latest"
  else
    case "$ISH_URL" in
      "https://github.com/${SITE_REPO}/releases/download/"*) pass "install.sh DMG URL host/path aligned" ;;
      *) fail "install.sh DMG URL off-repo: $ISH_URL" ;;
    esac
    icode=$(curl -s -o "$WORK/ish.dmg" -w "%{http_code}" -L --max-time 120 "$ISH_URL" || true)
    ISH_SHA=$(shasum -a 256 "$WORK/ish.dmg" 2>/dev/null | awk '{print $1}' || true)
    [ "$icode" = "200" ] && [ "$ISH_SHA" = "$DMG_SHA" ] \
      && pass "install.sh DMG == cask DMG (sha256)" \
      || fail "install.sh DMG mismatch (http=$icode sha=$ISH_SHA vs $DMG_SHA)"
  fi

  # The .app inside the DMG must match the cask `app` stanza, else
  # `brew install` and `curl … | sh` land different bundle names.
  if [ "$(uname -s)" = "Darwin" ] && command -v hdiutil >/dev/null 2>&1; then
    MP=$(/usr/bin/hdiutil attach "$WORK/$DMG" -nobrowse -readonly 2>/dev/null | grep -o '/Volumes/.*' | head -1)
    if [ -n "${MP:-}" ]; then
      APP_IN_DMG=$(basename "$(find "$MP" -maxdepth 1 -name '*.app' -print -quit)")
      /usr/bin/hdiutil detach "$MP" -quiet 2>/dev/null || true
      [ -n "$APP_IN_DMG" ] && [ "$APP_IN_DMG" = "$CASK_APP" ] \
        && pass "DMG bundle '$APP_IN_DMG' == cask app stanza" \
        || fail "DMG bundle '$APP_IN_DMG' != cask app '$CASK_APP'"
    else
      info "could not mount DMG — skipping bundle-name check"
    fi
  else
    info "not macOS — skipping DMG bundle-name check"
  fi
fi

# 7. Optional: real brew install/uninstall smoke test (system-modifying).
if $DO_BREW; then
  echo "— brew smoke test (--brew) —"
  if command -v brew >/dev/null 2>&1; then
    brew tap "${TAP_REPO%/*}/${TAP_REPO#*/homebrew-}" "https://github.com/${TAP_REPO}.git" 2>/dev/null || true
    if brew install --cask catty 2>&1 | tail -3; then
      pass "brew install --cask catty succeeded"
      brew uninstall --cask catty 2>&1 | tail -1 && pass "brew uninstall succeeded" || fail "brew uninstall failed"
    else
      fail "brew install --cask catty failed"
    fi
  else
    info "brew not installed — skipping smoke test"
  fi
fi

echo
if [ "$fails" -eq 0 ]; then
  echo -e "${C_G}RESULT: ALL ALIGNED${C_N} — release/DMG/cask/appcast agree on ${TAG}."
  exit 0
else
  echo -e "${C_R}RESULT: ${fails} MISMATCH(ES)${C_N} — see ✗ above."
  exit 1
fi
