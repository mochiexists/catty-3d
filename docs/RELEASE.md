# Catty release pipeline

> Status: scaffolding in place, no signed builds yet. This document
> describes the pipeline as it will be once secrets + signing identity
> are wired. Update it as each piece lands.

Catty ships through two channels, mirroring Local AI Cat's split:

| Channel | Sandbox | Distribution | Bundle ID |
|---|---|---|---|
| **Indoor** (Mac App Store) | Yes | App Store / TestFlight | `mochiexists.Catty` |
| **Outdoor** (Direct Download) | No | Notarized DMG + Sparkle appcast + Homebrew cask | `mochiexists.Catty` |

Both channels build from the same Catty codebase and share a bundle
identifier so future iCloud / CloudKit containers cover both
distribution channels (the Local AI Chat pattern). Only one copy of
the app can be installed on a user's Mac at a time — LaunchServices
indexes by bundle ID. The split between the two targets lives in
`project.yml` and the entitlements files (`AppStore.entitlements`
vs `DirectDownload.entitlements`).

---

## Required Apple resources

Set these up once in App Store Connect / Apple Developer Center:

### Bundle identifiers

| Bundle ID | Capabilities | Channel |
|---|---|---|
| `mochiexists.Catty` | Outdoor: Hardened Runtime, no sandbox. Indoor: App Sandbox on, `network.client`, `files.user-selected.read-write`. Same bundle ID — entitlements differ per target. | Outdoor (Developer ID) + Indoor (Mac App Store) |
| `mochiexists.Catty.dev` | Same as Outdoor | Debug-variant tagged builds |
| `mochiexists.Catty.UITests` | Test bundle | UI tests for fastlane snapshot |

### Signing certificates

- **Apple Development** (for local Cmd+R)
- **Developer ID Application** (Outdoor signing)
- **Apple Distribution** (Indoor / App Store signing)
- **Mac Installer Distribution** (Indoor `.pkg` signing)

### App Store Connect API key

Single key works for both `release` (App Store) and `beta` (TestFlight)
lanes. Generate at App Store Connect → Users and Access → Integrations
→ Team Keys. Note the Key ID, Issuer ID, and download the `.p8` file
once (Apple won't show it again).

### Notarytool credential profile

For Outdoor (DMG) notarization. Set up once on the build machine:

```sh
xcrun notarytool store-credentials "catty-notary" \
  --apple-id "<your apple id>" \
  --team-id  "$DEVELOPMENT_TEAM" \
  --password "<app-specific password>"
```

The password is an app-specific one from appleid.apple.com → Sign-In
and Security → App-Specific Passwords.

### Sparkle EdDSA keypair (for Outdoor auto-update)

Generate once with Sparkle's `generate_keys` tool. The **public** key
goes in `Local.xcconfig` (`SPARKLE_ED_PUBLIC_KEY`); the **private**
key stays in macOS Keychain on whichever machine runs the release
pipeline (typically a CI runner).

---

## Local development → fastlane lanes

```sh
brew install xcodegen swiftlint fastlane
cp Local.example.xcconfig Local.xcconfig
$EDITOR Local.xcconfig            # fill in DEVELOPMENT_TEAM + BUNDLE_ID_PREFIX
cp fastlane/.env.example fastlane/.env
$EDITOR fastlane/.env             # fill in ASC_KEY_* / DEVELOPMENT_TEAM

fastlane generate_project          # → Catty.xcodeproj
fastlane mac screenshots           # → fastlane/screenshots/macos/*.png

fastlane mac beta                  # → upload to TestFlight
fastlane mac release               # → upload to App Store Connect
fastlane mac release submit_for_review:true   # ← actually submit, not just upload
fastlane mac release submit_for_review:true automatic_release:true   # ← submit + auto-release on approval

fastlane mac upload_metadata       # push fastlane/metadata/* (descriptions, keywords, etc.)
fastlane mac upload_screenshots    # push fastlane/screenshots/* only
```

The metadata in `fastlane/metadata/` is the source of truth for App
Store strings — name, subtitle, description, keywords, release notes,
URLs, age rating. Edit those files, then `fastlane mac upload_metadata`
to push them up. No need to log into App Store Connect for routine copy
edits.

### Localising

`fastlane/metadata/en-US/` carries the English copy. To add another
locale:

```sh
mkdir fastlane/metadata/fr-FR
# Translate each .txt file from en-US into fr-FR
fastlane mac upload_metadata
```

App Store-supported locales include `en-US`, `en-GB`, `fr-FR`, `de-DE`,
`es-ES`, `it`, `ja`, `ko`, `pt-BR`, `zh-Hans`, `zh-Hant`, plus a few
dozen more. Each locale needs at minimum `name.txt` and `description.txt`;
others fall back to the primary locale.

---

## CI release flow (when wired)

Triggered by a tag push to `mochiexists/catty`:

```
git tag release/v0.1.0+1
git push origin release/v0.1.0+1
```

The `.github/workflows/release-direct.yml` workflow (next ticket — see
issue/task #29) will:

1. Validate the build number is monotonically greater than the last
   successful release (Launch Services on macOS picks the highest
   `CFBundleVersion`).
2. Build + sign the Outdoor target.
3. Notarize via notarytool.
4. Wrap in a DMG.
5. Publish DMG as a GitHub Release on `mochiexists/catty-3d`
   (the site's /download page links to `/releases/latest`).
6. Update Sparkle `appcast.xml` on `mochiexists/catty3d-site` (served
   at `catty3d.com/appcast.xml`).
7. Update Homebrew cask in `mochiexists/homebrew-catty3d`.
8. Auto-promote `outdoor-cat` → `main` so the Indoor pipeline (Xcode
   Cloud) picks up the same SHA on next push.

The Indoor side is Xcode Cloud, configured via App Store Connect to
build on push to `main`. Submission to review remains a manual step in
the App Store Connect web UI for the first several releases.

---

## Common failure modes (preempting future tears)

- **`xcodegen generate` fails on CI: "Local.xcconfig not found"**
  → CI must `cp Local.example.xcconfig Local.xcconfig` first OR inject
  a real one from a base64 secret. See `.github/workflows/ci.yml`
  bootstrap step.

- **`upload_to_app_store` fails with "no eligible build found"**
  → The build was uploaded but App Store Connect hasn't finished
  processing it. Wait 5–10 min then re-run with `force: true`.

- **Notarization stuck "in progress" for >30 minutes**
  → Apple's queue is sometimes slow; check status manually with
  `xcrun notarytool history --keychain-profile catty-notary`.

- **CFBundleVersion lower than previous release**
  → `release-direct.yml`'s monotonic-N validator will refuse the
  build. Always increase the build number on each tag push.
