# Catty — OSS Refactor & Performance Plan

Status: **plan only** (this document). The testing/lint foundation
(Phase −1) is **done**; everything else is sequenced but not executed.

Derived from a three-lens review (performance, architecture/DRY,
health). Each phase compiles, preserves behavior, and is independently
shippable. Effort: S = <½ day · M = ~1 day · L = 2–3 days.

---

## Phase −1 — Measurement foundation ✅ DONE

- `CattyTests` SPM test target (`swift test`).
- Perf baseline suite (`TerminalCapturePerformanceTests`) — drives the
  capture hot path under 4 workloads; the yardstick for all perf work.
- Regression unit tests: `PaneSlotTests` (locks the grid-spacing magic
  numbers pre-extraction), `ConnectionStateMappingTests` (locks the
  transport-neutral SSH state map).
- SwiftLint scoped to `App` + `Tests` + `UITests` (0 violations).

### Captured baseline (`swift test`, this machine, debug)

| Scenario | Clock (avg) | Peak mem |
|---|---|---|
| **End-to-end production capture** (full-screen churn) | **~50 ms** | — |
| Raster-only — idle prompt | ~17 ms | 171 MB |
| Raster-only — 5k-line scrollback | ~17 ms | 166 MB |
| Raster-only — full-screen churn | ~10 ms | 169 MB |
| Raster-only — SSH-like small chunks | ~18 ms | 180 MB |

High relative std-dev (CPU timing under `swift test`); compare averages
before/after each perf change. The ~50 ms end-to-end vs ~10–18 ms
raster confirms raster + `TextureResource.replace` is the heavy path.

---

## Performance track (highest user-visible value)

### P0 — Stop full-view rasterizing on a fixed timer (S–M, 1–2 files)
`TerminalLiveTextureSource.swift:259,281-283` re-rasterizes every glyph
(~14 ms main) at up to 30 Hz during *any* output, starving the
RealityKit tick → orbit stutter.

- Replace the `1/30` `Timer` with a **coalesced, rate-capped (~20 Hz)**
  trigger off the existing `onDirty` signal. Call `captureFrame()`
  directly from the main-thread timer (drop the `Task { @MainActor }`
  hop, `:260`).
- Drop the redundant `view.needsDisplay = true` (`:221`).
- Coalesce SSH chunks in `SSHTransport.runSession` (`:201`) into ~8–16 ms
  windows before feeding (one main-actor hop per window, not per TCP
  segment).
- **Design the coalescer as a pure, unit-testable type** (`input: dirty
  timestamps → output: capture decisions`); add `CoalescerTests`
  asserting ≤ N captures/sec. This makes the P0 win provable
  independently of the timing-noisy perf suite.

### P1 — Kill per-frame steady-state work (S–M)
- `Terminal3DRealityScene.swift:423` builds a new `UnlitMaterial` every
  texture version; build it **once per pane**, store on
  `TerminalPlaneRef`. `TextureResource.replace` mutates in place, so a
  stable material shows fresh pixels with zero reassignment.
- Gate the 6 per-frame sweeps in the `RealityView` update closure
  (`:142-154`) behind change-detection (camera tuple, pane set,
  surface-mode). Keep only orbit + cursor-cat bob per-frame.
- `StarfieldView` (`Terminal3DSceneView.swift:1296`) redraws 160 static
  ellipses 60×/s — render them once into a cached layer; keep only
  shooting stars in the `TimelineView`.

### P2 — Lower-impact (L, optional)
Dirty-rect capture from SwiftTerm's `invalidRect`; reuse one
`NSBitmapImageRep` across captures (`:281`); avoid per-chunk
`Array`↔`ArraySlice` round-trips.

---

## Architecture / DRY / modularization track

### Phase 0 — Zero-risk warm-ups (S)
- Extract `StarfieldView` + stores → `Scene/Starfield.swift` (fully
  isolated; also unblocks P1 starfield fix).
- Verify `ScrollWheelCatcher` (`Terminal3DSceneView.swift:1239-1275`) is
  dead (replaced by the app-level monitor) → delete if confirmed.
- Fix the dead `docs/planning/catty-extraction-brief.md` references
  (CONTRIBUTING.md + `MultiSessionView.swift:13` +
  `SessionHistoryView.swift:49`) — point them at this file or a tracking
  issue.

### Phase 1 — Centralize load-bearing duplication (S–M)
The single highest-value behavior-preserving change; prerequisite for
the module split.
- `enum SceneMetrics` — plane `1.6 × 1.05`, gap `0.05`, glow
  `1.72 × 1.13`, capture `880 × 566`. Replace ~20 literal sites
  (`PaneSlot.swift:53-55`, `TerminalLiveTextureSource.swift:83`,
  `Terminal3DRealityScene.swift`, `Terminal3DSceneView.swift:649`,
  `OrbitDebugMinimap.swift:70`). `PaneSlotTests` already locks the
  resulting positions.
- `ZoomCurve.radius(for:)` — the zoom→camera-radius math copy-pasted in
  `Terminal3DRealityScene.swift:170`, `Terminal3DSceneView.swift:634`,
  `OrbitDebugMinimap.swift:87`. Divergence silently mis-places click
  targets vs rendered panes. Add `ZoomCurveTests` at the endpoints.

### Phase 2 — Decompose `Terminal3DRealityScene.swift` (1262 → ~350) (M–L)
Pure, behavior-preserving extractions (none touch `@State`):
`TerminalSurfaceMesh`, `ProceduralTextures`, `ProceduralRat`,
`OrbiterRegistry` (rename from misnamed `OrbitState` — docs already call
it this), `SceneEntityRefs`, `FrameWatchdog`, `CameraRig`. Then a
`PaneEntityFactory` to collapse the ~120-line duplicated pane-entity
construction between `buildScene` and `spawnPaneEntities` (DRY D2/D8) and
retire the legacy single-pane special-casing.

### Phase 3 — Tests + lint the package (S–M)
- `Tests/CattyRenderingTests` (mesh vertex/index counts, texture dims,
  `ZoomCurve` endpoints) — enabled by Phase 2 extractions.
- Add `Sources/Catty` to `.swiftlint.yml included:` and clear the
  inventory below. (Deferred to here because it currently fails the
  build-phase lint and several fixes need the post-decomposition files.)

  **Current `Sources/Catty` debt — 61 violations (5 error-level):**
  - `ScreenshotPresets.swift:71,86` — line_length >200 (error)
  - `Terminal3DSceneView.swift:1113` — line_length 253 (error)
  - `Terminal3DRealityScene.swift:694` — `g_alpha` identifier_name (error)
  - `OrbitDebugMinimap.swift:138` — 9-param function (error; needs a
    small struct/param-object or a scoped rule exception)
  - ~56 warnings (mixed)
- Re-enable `file_length` as **warning** post-split to prevent
  regression (keep `type_body_length`/`function_body_length` judged).
- Update CONTRIBUTING.md layout diagram + mirror the documented layers
  in the directory tree (`SingleSession/`, `Rendering/`, `Debug/`).

### Phase 4 — Decompose `Terminal3DSceneView.swift` via extensions (M)
Split chrome/gestures/projection/pane-controller into
`Terminal3DSceneView+*.swift` (same type, shared state — navigability,
not an MVVM rewrite). Move `TerminalSurfaceMode`/`CameraMode` enums to
own files (→ `CattyCore`). Extract a `darkPanelBackground()` modifier
(DRY D7). **Do NOT** do a view-model rewrite — Layer-1 is the frozen
public surface per CONTRIBUTING.md; that needs a major bump + LAIC
migration.

### Phase 5 — SPM module split (L, build-system risk only)
Targets: **CattySSH** (`SSHTransport`, `CattySSH` — the iOS-compilable
seam) → **CattyCore** (pure value types, persistence, `OrbitConfig`) →
**CattyRendering** (Phase-2 extractions) → **Catty** (SwiftUI surface,
unchanged product name). `@_exported import` the lower modules so
`import Catty` and LAIC's path stay byte-stable. Promote `CattyCore` to
Swift 6 language mode (isolates the strict-concurrency debt). Update
`project.yml` package wiring. Do last — by now it's "move files +
imports," not "untangle code."

---

## Do NOT change (working, low value / high risk)

- `SSHTransport` / `CattySSH` transport-neutral design (the best part).
  The dual `ConnectionState` enums are a deliberate seam — guarded by
  `ConnectionStateMappingTests`, not collapsed.
- `TerminalLiveTextureSource` env-scrubbing logic — subtle, battle-
  tested; only touch it to consume `SceneMetrics`.
- The `.swiftLanguageMode(.v5)` deferral on Catty/SSH — separate, larger
  effort; CONTRIBUTING.md already invites it standalone.
- No MVVM extraction of `Terminal3DSceneView` (frozen Layer-1 API).
- `Composed/` + `Sessions/` scaffolds — intentional contributor
  playground; leave as stubs.

---

## Suggested execution order

`P0` → `Phase 0` → `Phase 1` → `P1` → `Phase 2` → `Phase 3` →
`Phase 4` → `P2` → `Phase 5`.

Rationale: ship the user-visible perf win first (it's measurable now via
Phase −1), then the cheap correctness/DRY fixes, then the structural
work that the tests + `SceneMetrics`/`ZoomCurve` make safe.
