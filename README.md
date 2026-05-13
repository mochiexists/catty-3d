# Catty

A 3D terminal experience for macOS (and soon iOS). Your shell, but framed
inside a RealityKit scene with orbiting companions. Open-source, MIT.

> Status: pre-release scaffolding. The Catty SwiftPM package lives in-tree
> at `local-ai-cat/Local-AI-Chat:Local AI Chat/Features/Compute/Terminal3D/CattyPackage/`
> until it's ready to extract to `mochiexists/catty`. This repo is the
> staging ground for the standalone app that ships alongside the package.

## Run locally (developer-only, today)

```sh
# First-time setup: copy the xcconfig template and fill in your Team ID
# + bundle ID prefix. This file is .gitignored so your identifiers stay
# out of forks/PRs.
cp Local.example.xcconfig Local.xcconfig
$EDITOR Local.xcconfig

# Build + run via SwiftPM (quick iteration, no .app bundle):
swift build
swift run CattyApp

# Or via XcodeGen + Xcode (real .app bundle, what ships):
brew install xcodegen
xcodegen generate
open Catty.xcodeproj
# Then ⌘R in Xcode (Catty scheme = Outdoor, Catty (App Store) = Indoor)
```

## Sensitive identifiers

Personal Apple Developer Team ID and bundle-ID prefix never live in
`project.yml`. They flow in via `Local.xcconfig` (gitignored) which
overrides:

- `DEVELOPMENT_TEAM`  — your Apple Developer Team ID
- `BUNDLE_ID_PREFIX`  — reverse-DNS namespace you own; used as
  `$(BUNDLE_ID_PREFIX).Catty`, `$(BUNDLE_ID_PREFIX).Catty.AppStore`, etc.
- `SPARKLE_ED_PUBLIC_KEY` — public half of the Sparkle update key
  (private half lives only in macOS Keychain on the release runner)

CI passes these via env vars / secrets, not from `Local.xcconfig`.

The `Package.swift` here depends on the Catty package via a relative path
into a sibling checkout of `local-ai-cat/Local-AI-Chat`. Once Catty extracts
to its own repo, this dep flips to a version-pinned remote URL.

## Repo layout

```
catty-app/
├── App/                # SwiftUI app entry + root view (this repo)
├── Package.swift       # SwiftPM manifest, depends on Catty
└── project.yml         # XcodeGen project (added in Phase 4)
```

## License

MIT. See `LICENSE`. Bundled USDZ assets carry their own attribution —
see `ATTRIBUTION.md`.

## Where contributions go

| Want to add… | Lives in |
|---|---|
| New 3D camera mode, terminal shader, surface geometry | `mochiexists/catty` (Layer 1 of the SwiftPM package) |
| New session store, multi-session layout, history view | `mochiexists/catty` (Layer 2/3) |
| Catty-app-specific UI (menus, settings, preferences) | this repo |
| SSH transport, credential UI | this repo (transport plugs into the package's `CattySSHTransporting` protocol) |
