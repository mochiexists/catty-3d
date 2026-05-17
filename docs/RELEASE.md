# Catty release pipeline

> Status: direct-download releases are live. The GitHub Actions pipeline
> builds, signs, notarizes, smoke-launches, packages a DMG, signs the
> Sparkle appcast, and uploads review artifacts. Cross-repo publication
> is automated when the optional GitHub App secrets are present; without
> them, publish the uploaded artifact manually to `catty3d-site` and bump
> `homebrew-catty3d`.

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

### Notarytool credentials

For local Outdoor notarization, set up a keychain profile on the build
machine:

```sh
xcrun notarytool store-credentials "catty-notary" \
  --apple-id "<your apple id>" \
  --team-id  "$DEVELOPMENT_TEAM" \
  --password "<app-specific password>"
```

The password is an app-specific one from appleid.apple.com → Sign-In
and Security → App-Specific Passwords.

In GitHub Actions the live workflow uses secrets instead:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

### Sparkle EdDSA keypair (for Outdoor auto-update)

Generate once with Sparkle's `generate_keys` tool or
`scripts/generate-sparkle-key.sh`. The **public** key goes in
`Local.xcconfig` (`SPARKLE_ED_PUBLIC_KEY`); the **private** key is
stored as the `SPARKLE_PRIVATE_KEY` GitHub Actions secret.

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

## Direct-download release flow

The release workflow is `.github/workflows/release-direct.yml`. It can be
run manually:

```sh
gh workflow run release-direct.yml \
  -f version=0.1.1 \
  -f build_number=11
```

It can also be triggered by a release tag pushed to `mochiexists/catty-3d`:

```
git tag release/v0.1.0+1
git push origin release/v0.1.0+1
```

The workflow:

1. Validate the build number is monotonically greater than the last
   successful release (Launch Services on macOS picks the highest
   `CFBundleVersion`).
2. Materialize `Local.xcconfig` from `LOCAL_XCCONFIG_BASE64` and derive
   the Sparkle public key from `SPARKLE_PRIVATE_KEY`.
3. Build the `Catty` Release archive and rename the shipped bundle to
   `Catty 3D.app`.
4. Sign nested Sparkle helper code, then sign the app with Developer ID.
5. Notarize and staple the app.
6. Smoke-launch the app on the macOS runner.
7. Build, sign, notarize, and staple `Catty-<version>.dmg`.
8. Generate a signed Sparkle `appcast.xml`.
9. Upload the DMG + appcast as the workflow artifact
   `direct-release-<version>-<build>`.
10. If `APP_ID` and `APP_PRIVATE_KEY` are set, publish the versioned DMG,
    stable `Catty.dmg`, and `appcast.xml` to
    `mochiexists/catty3d-site`, then bump
    `mochiexists/homebrew-catty3d`.

The current live release host is:

- `https://github.com/mochiexists/catty3d-site/releases/latest/download/Catty.dmg`
- `https://github.com/mochiexists/catty3d-site/releases/latest/download/appcast.xml`

The Homebrew tap installs `Catty 3D.app` from the versioned DMG in
`mochiexists/homebrew-catty3d`.

### Required GitHub Actions secrets

The public repo stores no secret values. Release-only material lives in
GitHub Actions secrets:

| Secret | Purpose |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | Developer ID Application `.p12`, base64 encoded |
| `APPLE_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `APPLE_SIGNING_IDENTITY` | Developer ID Application identity name |
| `APPLE_ID` | Apple ID email for notarization |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for `notarytool` |
| `SPARKLE_PRIVATE_KEY` | EdDSA key used to sign the Sparkle appcast |
| `LOCAL_XCCONFIG_BASE64` | Build settings, including team/bundle prefix/public Sparkle key |
| `APP_ID` | Optional GitHub App ID for cross-repo publishing |
| `APP_PRIVATE_KEY` | Optional GitHub App private key for cross-repo publishing |

Run `scripts/setup-github-secrets.sh` to upload or rotate these.

### OSS safety

Catty is public, so release secrets are isolated from untrusted code:

- `release-direct.yml` triggers only on `workflow_dispatch` and
  `push.tags: release/v*`; both require write access to the repo.
- The release workflow does not use `pull_request` or
  `pull_request_target`.
- Workflow permissions are limited to `contents: read` and
  `actions: read`; cross-repo writes require the optional GitHub App
  token and are skipped if it is missing.
- User-controlled workflow inputs are passed through `env:` and then
  shell-validated before use.
- Fork PR workflow approval is set to first-time contributors on the
  GitHub repo. Keep that setting enabled.

The Indoor side is Xcode Cloud, configured via App Store Connect to
build on push to `main`. Submission to review remains a manual step in
the App Store Connect web UI for the first several releases.

---

## Common failure modes (preempting future tears)

- **Workflow syntax fails around optional `secrets.APP_ID` checks**
  → Do not use `secrets.APP_ID != ''` directly in a step `if:`. The
  workflow exposes it as `env.GITHUB_APP_ID` and gates optional publish
  steps with `if: ${{ env.GITHUB_APP_ID != '' }}`.

- **Release workflow builds, but signing cannot find `Catty.app`**
  → Do not hard-code the archive product path. Resolve the `.app`
  inside the `.xcarchive` and export `APP_PATH`.

- **Archive contains dSYMs but no `.app` product**
  → The workflow is archiving the wrong scheme. Use scheme `Catty`, not
  target name `CattyApp`.

- **Notarization fails on Sparkle `Updater`, `Autoupdate`, or XPC
  services**
  → Sign nested Mach-O files and nested `.app` / `.xpc` /
  `.framework` bundles inside `Contents/Frameworks` before signing the
  outer app.

- **DMG installs `Catty.app` instead of `Catty 3D.app`**
  → The release workflow renames the archived bundle to `Catty 3D.app`
  before creating the DMG, and the Homebrew cask must use
  `app "Catty 3D.app"`.

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
