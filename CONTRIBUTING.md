# Contributing to Catty

Catty is a 3D terminal experience for macOS — your shell rendered as a
textured plane in a RealityKit scene, with a small cat watching over
your shoulder. The project is MIT-licensed and welcomes outside
contributions.

If you're reading this from a fork: thank you. Here's how to send
something back.

## Quick setup

```sh
# 1. Set your signing identifiers without leaking them into git.
cp Local.example.xcconfig Local.xcconfig
$EDITOR Local.xcconfig          # fill in DEVELOPMENT_TEAM + BUNDLE_ID_PREFIX

# 2. Install build deps once.
brew install xcodegen swiftlint

# 3. Generate the project + run.
xcodegen generate
open Catty.xcodeproj
# Then ⌘R in Xcode. The `Catty` scheme is Outdoor (unsandboxed);
# `Catty (App Store)` is Indoor (sandboxed).
```

For a quick CLI iteration loop without a real `.app` bundle:

```sh
swift build && swift run CattyApp
```

## Project layout

```
catty-app/
├── Package.swift               – SwiftPM manifest (Catty library + CattyApp exec)
├── Sources/Catty/              – The package source of truth.
│   ├── Terminal3DSceneView.swift
│   ├── Terminal3DRealityScene.swift
│   ├── TerminalLiveTextureSource.swift
│   ├── SSHTransport.swift
│   ├── CattySSH.swift, PaneSlot.swift, PersistedLayout.swift, …
│   ├── Sessions/               – Layer 2 scaffolds (CattySession, store)
│   └── Composed/               – Layer 3 scaffolds (multi-session, history)
├── App/                        – Standalone Catty.app source (small).
│   ├── CattyApp.swift, RootView.swift, LauncherView.swift, SSHConnectSheet.swift
├── Entitlements/, Assets.xcassets/, UITests/, fastlane/, scripts/
├── project.yml                 – XcodeGen project (Outdoor + Indoor + UITests targets)
└── .github/workflows/ci.yml    – Lint + build matrix
```

Local AI Chat consumes the `Catty` library via a local-path SPM
dependency today; once this repo lives at `mochiexists/catty` it'll
flip to a version-pinned remote URL. Either way, the **same code**
ships in both the standalone app and embedded inside Local AI Chat —
any improvement here lands in both.

## Architecture: the three layers

| Layer | Lives in | Stability |
|---|---|---|
| **1 – Single-session primitive** | `Terminal3DSceneView`, `TerminalLiveTextureSource`, `Terminal3DRealityScene`, `OrbitConfigState`, camera + surface modes | **Frozen.** Local AI Chat depends on the public API here — breaking changes need a major version bump + coordinated migration. |
| **2 – Data models + protocols** | `CattySession`, `CattySessionStore`, `CattySSHTransporting`, `PersistedLayout`, `PaneSlot` | Design-stabilising. Ship at v0.2+; mark experimental until v1.0. |
| **3 – Composed views** | `CattyMultiSessionView`, `CattySessionHistoryView` (in `Sources/Catty/Composed/`) | Contributor playground. New layouts, history visualisers, theming. Pure additive. |

New features should pick the lowest layer that fits — if your change
doesn't have to touch Layer 1, don't.

## Code style

- SwiftLint runs on every commit (`scripts/pre-commit` installs the
  hook; `./scripts/setup-hooks.sh` wires it). CI fails on any
  SwiftLint error.
- `swiftLanguageMode(.v5)` for the Catty target because the Citadel
  withPTY task group triggers Swift 6's sending diagnostics. Refactors
  toward strict concurrency are welcome.
- Match the surrounding code's comment density, naming, and idiom
  — Catty's existing files lean toward "why" comments around the
  RealityKit + camera math because the geometry isn't self-evident.

## How to send a PR

1. Fork + branch off `main`.
2. `cp Local.example.xcconfig Local.xcconfig` and fill in your own
   identifiers — **never commit your `Local.xcconfig`**.
3. Make your change. Keep commits conventional
   (`feat:` / `fix:` / `refactor:` / `docs:` / `test:` / `chore:`).
4. Verify: `swiftlint`, `swift build`, and `xcodebuild -scheme Catty
   -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` all
   green.
5. Open a PR with a one-paragraph rationale + screenshot if it
   touches anything visible.

## The wishlist (good first contributions)

These are open and would make Catty meaningfully better. Pick one,
open an issue first if you want a sanity check on direction, then
send a PR.

### 🥽 visionOS port

Catty was always going to make sense in space. The natural endpoint
of multi-pane + spatial layout is **terminals floating freely around
you in a passthrough ImmersiveSpace** — codex on your left, claude
on your right, claude-cli running tail-f overhead. Some of the work:

- Swap the AppKit-only `TerminalSourceEmbed` for the visionOS
  equivalent (UIKit-based hosting + cross-platform `RealityView`).
- Port the orbit camera math to head-tracked perspective; gesture
  mapping for pinch + drag (HandTracking on Vision Pro).
- Reuse `PaneSlot` but extend it to true 3D positions (north + south
  + east + west + up + down + freely-placed).
- A visionOS-specific scheme + entitlements (`com.apple.developer.vr`).

> 👉👈 If you happen to have a spare Apple Vision Pro lying around
> and would like to donate one to make this happen faster, that
> would be very cool 💜. (Otherwise: ports from contributors who
> already own one are *extremely* welcome.)

### Other open work

- **Sessions persistence** beyond layout: SwiftTerm scrollback,
  PWD tracking, named tab labels. Layer 2 `CattySession` is the
  starting point.
- **Theming**: colour-palette + font-size knobs that flow into the
  SwiftTerm view's options.
- **More surfaces**: dome, scroll, holographic projection. Drop
  another case into `TerminalSurfaceMode` + a new `make…Mesh`.
- **Per-pane SSH spawn**: today the "Add terminal" arrows always
  spawn `.local` panes. SSH-from-arrow would need a credential
  prompt before the new pane spins up.
- **Window position memory**: `NSWindow` frame autosave.
- **iOS port of the SwiftTerm capture pipeline**: SSH-only on iOS
  is the natural path (sandbox forbids spawn). Catty's iOS surface
  is currently SSH-only by gating, but the RealityKit scene doesn't
  compile on iOS yet.
- **Maxwell rigging**: cursor cat blinks / yawns / occasionally
  bats at the rat. Right now he just spins.

If you don't see your idea here, that's an even better reason to
file an issue and propose it.

## Asset contributions

Replacing or adding 3D assets? Drop them in `Sources/Catty/Resources/`
and document their licence in `ATTRIBUTION.md`. Catty's bundled
Maxwell USDZ is CC-BY-4.0; the rat is MIT via Orhun's
[Ratty](https://github.com/orhun/ratty) repo. Whatever you bring
needs a permissive licence too.

## Saying hi

Open an issue or PR. Catty is small and friendly; reviews land
quickly. Thanks for being here.
