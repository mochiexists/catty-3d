#!/bin/bash
# setup-github-secrets.sh — interactive uploader for the secrets
# `release-direct.yml` needs. Run it once when bootstrapping a fresh
# repo, or any time a secret rotates.
#
# Walks you through each secret, base64-encodes files inline, uploads
# via `gh secret set` (no copy-paste of long blobs into the web UI).
#
# Safe to re-run — `gh secret set` just overwrites in place.
#
#   scripts/setup-github-secrets.sh
#
# Or skip prompts for things you already set:
#
#   SKIP="APPLE_TEAM_ID,APPLE_ID" scripts/setup-github-secrets.sh

set -euo pipefail

REPO="${REPO:-mochiexists/catty-3d}"
SKIP="${SKIP:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh (GitHub CLI) is required" >&2
  exit 1
fi

if ! gh auth status -h github.com >/dev/null 2>&1; then
  echo "error: not authed to github.com — run \`gh auth login\` first" >&2
  exit 1
fi

# ─────────────── helpers ───────────────

skip_check() {
  case ",${SKIP}," in
    *,$1,*) return 0 ;;
    *)       return 1 ;;
  esac
}

set_secret() {
  local name="$1" value="$2"
  if skip_check "$name"; then
    printf "  ↪ skipping %s (in SKIP)\n" "$name"
    return 0
  fi
  if [ -z "$value" ]; then
    printf "  ! skipping %s (empty)\n" "$name"
    return 0
  fi
  printf "%s" "$value" | gh secret set "$name" -R "$REPO" --body -
  printf "  ✓ set %s on %s\n" "$name" "$REPO"
}

ask() {
  local prompt="$1" var
  printf "%s: " "$prompt" >&2
  IFS= read -r var
  printf "%s" "$var"
}

ask_secret() {
  local prompt="$1" var
  printf "%s (hidden): " "$prompt" >&2
  IFS= read -rs var
  printf "\n" >&2
  printf "%s" "$var"
}

ask_file() {
  local prompt="$1" path
  while :; do
    printf "%s\n  path: " "$prompt" >&2
    IFS= read -r path
    # Expand ~
    path="${path/#~/$HOME}"
    if [ -f "$path" ] && [ -r "$path" ]; then
      printf "%s" "$path"
      return 0
    fi
    printf "  ! not found or unreadable: %s — try again\n" "$path" >&2
  done
}

# ─────────────── pre-flight ───────────────

echo "▶ Setting GitHub Actions secrets on $REPO"
echo

# Confirm Catty's repo exists and we have push access
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  echo "error: $REPO not found or no access — check the REPO env var" >&2
  exit 1
fi

# ─────────────── 1. APPLE_TEAM_ID ───────────────

if ! skip_check "APPLE_TEAM_ID"; then
  echo "── 1/8 APPLE_TEAM_ID ────────────────────────────────────────"
  echo "Your 10-character Apple Developer team ID."
  if [ -f Local.xcconfig ]; then
    SUGGESTED=$(awk -F'=' '/DEVELOPMENT_TEAM/ {gsub(/[ \t]/,"",$2); print $2}' Local.xcconfig)
    if [ -n "$SUGGESTED" ]; then
      echo "Found in Local.xcconfig: $SUGGESTED"
      printf "Use this? [Y/n]: "
      IFS= read -r yn
      case "$yn" in
        n|N) APPLE_TEAM_ID=$(ask "Enter team ID") ;;
        *)   APPLE_TEAM_ID="$SUGGESTED" ;;
      esac
    else
      APPLE_TEAM_ID=$(ask "Enter team ID")
    fi
  else
    APPLE_TEAM_ID=$(ask "Enter team ID")
  fi
  set_secret "APPLE_TEAM_ID" "$APPLE_TEAM_ID"
  echo
fi

# ─────────────── 2. APPLE_ID ───────────────

if ! skip_check "APPLE_ID"; then
  echo "── 2/8 APPLE_ID ─────────────────────────────────────────────"
  echo "Apple ID email used for notarization (e.g. you@example.com)."
  APPLE_ID=$(ask "Apple ID")
  set_secret "APPLE_ID" "$APPLE_ID"
  echo
fi

# ─────────────── 3. APPLE_APP_SPECIFIC_PASSWORD ───────────────

if ! skip_check "APPLE_APP_SPECIFIC_PASSWORD"; then
  echo "── 3/8 APPLE_APP_SPECIFIC_PASSWORD ──────────────────────────"
  echo "Generate at https://appleid.apple.com → Sign-In and Security"
  echo "→ App-Specific Passwords → '+' → label it 'Catty release'."
  echo "Looks like: abcd-efgh-ijkl-mnop"
  ASP=$(ask_secret "App-specific password")
  set_secret "APPLE_APP_SPECIFIC_PASSWORD" "$ASP"
  echo
fi

# ─────────────── 4. APPLE_SIGNING_IDENTITY ───────────────

if ! skip_check "APPLE_SIGNING_IDENTITY"; then
  echo "── 4/8 APPLE_SIGNING_IDENTITY ───────────────────────────────"
  echo "Full string of your Developer ID Application cert."
  echo "Available identities in your keychain:"
  security find-identity -v -p codesigning 2>/dev/null \
    | grep -E 'Developer ID Application' \
    | sed 's/^/   /' || true
  echo "Format: \"Developer ID Application: NAME (TEAMID)\""
  SIGN_ID=$(ask "Signing identity")
  set_secret "APPLE_SIGNING_IDENTITY" "$SIGN_ID"
  echo
fi

# ─────────────── 5. APPLE_CERTIFICATE_BASE64 + PASSWORD ───────────────

if ! skip_check "APPLE_CERTIFICATE_BASE64"; then
  echo "── 5/8 APPLE_CERTIFICATE_BASE64 + APPLE_CERTIFICATE_PASSWORD ──"
  echo "The Developer ID Application cert exported from Keychain Access"
  echo "as a .p12 file (right-click cert → Export… → .p12 → set a password)."
  echo
  echo "Tip — if you don't have one handy, in Keychain Access:"
  echo "  1. Click 'login' keychain on the left"
  echo "  2. Find 'Developer ID Application: <your name> (TEAMID)'"
  echo "  3. Right-click → Export… → save as 'Catty-DevID.p12'"
  echo "  4. Choose a strong password and remember it"
  echo
  CERT_PATH=$(ask_file "Path to .p12 file")
  CERT_PASSWORD=$(ask_secret "Export password (the one you set when saving)")
  CERT_B64=$(base64 < "$CERT_PATH" | tr -d '\n')
  set_secret "APPLE_CERTIFICATE_BASE64" "$CERT_B64"
  set_secret "APPLE_CERTIFICATE_PASSWORD" "$CERT_PASSWORD"
  echo
fi

# ─────────────── 6. SPARKLE_PRIVATE_KEY ───────────────

if ! skip_check "SPARKLE_PRIVATE_KEY"; then
  echo "── 6/8 SPARKLE_PRIVATE_KEY ─────────────────────────────────"
  echo "Sparkle EdDSA private key used to sign the direct-download"
  echo "appcast. Generate with scripts/generate-sparkle-key.sh or"
  echo "Sparkle's generate_keys tool; do not commit it."
  SPARKLE_KEY=$(ask_secret "Sparkle private key")
  set_secret "SPARKLE_PRIVATE_KEY" "$SPARKLE_KEY"
  echo
fi

# ─────────────── 7. LOCAL_XCCONFIG_BASE64 ───────────────

if ! skip_check "LOCAL_XCCONFIG_BASE64"; then
  echo "── 7/8 LOCAL_XCCONFIG_BASE64 ────────────────────────────────"
  echo "Your Local.xcconfig (DEVELOPMENT_TEAM + BUNDLE_ID_PREFIX +"
  echo "SPARKLE_ED_PUBLIC_KEY). Reads from ./Local.xcconfig by default."
  if [ -f Local.xcconfig ]; then
    printf "Use ./Local.xcconfig? [Y/n]: "
    IFS= read -r yn
    case "$yn" in
      n|N) XCCONFIG_PATH=$(ask_file "Path to Local.xcconfig") ;;
      *)   XCCONFIG_PATH="Local.xcconfig" ;;
    esac
  else
    XCCONFIG_PATH=$(ask_file "Path to Local.xcconfig")
  fi
  XCCONFIG_B64=$(base64 < "$XCCONFIG_PATH" | tr -d '\n')
  set_secret "LOCAL_XCCONFIG_BASE64" "$XCCONFIG_B64"
  echo
fi

# ─────────────── 8. (optional) APP_ID + APP_PRIVATE_KEY ───────────────

if ! skip_check "APP_ID"; then
  echo "── 8/8 (optional) APP_ID + APP_PRIVATE_KEY ──────────────────"
  echo "GitHub App credentials so the release workflow can publish to"
  echo "catty3d-site, bump homebrew-catty3d, and fast-forward main."
  echo "Without these, the workflow still builds + signs + notarizes"
  echo "and uploads the DMG as a workflow artifact, but won't publish."
  echo
  printf "Configure now? [y/N]: "
  IFS= read -r yn
  case "$yn" in
    y|Y)
      APP_ID_VAL=$(ask "GitHub App ID (numeric)")
      KEY_PATH=$(ask_file "Path to .pem private key")
      KEY_CONTENT=$(cat "$KEY_PATH")
      set_secret "APP_ID" "$APP_ID_VAL"
      set_secret "APP_PRIVATE_KEY" "$KEY_CONTENT"
      ;;
    *)
      echo "  ↪ skipped"
      ;;
  esac
  echo
fi

echo "──────────────────────────────────────────────────────────────"
echo "✓ Done. Verify on GitHub:"
echo "  https://github.com/$REPO/settings/secrets/actions"
echo
echo "Then dispatch a release:"
echo "  scripts/release.sh 0.1.0 1"
echo "  OR  git tag release/v0.1.0+1 outdoor-cat && git push origin release/v0.1.0+1"
