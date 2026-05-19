# catty-app — Claude Code notes

<!-- PENDING-MIGRATION:START — remove this whole block once verified (see instructions) -->
## ⏳ Pending verification: release-pipeline deprecation migration

Two GitHub Actions deprecations in `.github/workflows/release-direct.yml` were
migrated but **not yet exercised by a real release**:

- **Node 24 runtime** — `actions/cache@v4 → v5`, `actions/upload-artifact@v4 → v7`
  (commit `54881b2`).
- **`create-github-app-token` `app-id` → `client-id`** — both invocations now
  pass the public Client ID `Iv23liBQMAQrOZ0NCnQi` (App ID `3761926`); the
  numeric App ID stays in `secrets.APP_ID` and still drives the
  `env.GITHUB_APP_ID` presence guards (commit `ebebe0a`).

**On the next successful `release-direct.yml` run, verify ALL of:**
1. Run conclusion is `success` with **no deprecation annotations**
   (no "Node.js 20" warning, no "Input 'app-id' has been deprecated").
2. The cross-repo token minted: "Publish to catty3d-site" and
   "Update Homebrew cask" steps ran (proves `client-id` auth works — these
   skip silently if token minting fails).
3. The "Verify release alignment (script + brew + dmg)" gate is green.

**Then:** delete this entire `PENDING-MIGRATION` block, and report back
confirming the migration succeeded (cite the run ID + version). If the run
fails on token minting, the likely cause is the `client-id` value — revert
commit `ebebe0a` to restore `app-id: ${{ env.GITHUB_APP_ID }}` and investigate.
<!-- PENDING-MIGRATION:END -->

## Release verification

`scripts/verify-release.sh [VERSION]` checks that the GitHub release, DMG,
Homebrew cask, Sparkle appcast, and `install.sh` all agree on
version/checksum/size/bundle-name. It also runs as a post-publish gate inside
`release-direct.yml`. Pass an explicit `build_number` strictly greater than the
highest build ever shipped (the auto-compute only scans `release/v*+*` tags and
can regress `CFBundleVersion` — v0.1.1 shipped build 10; v1.0.0 shipped build 12).
