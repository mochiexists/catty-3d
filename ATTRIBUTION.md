# Catty — Acknowledgements

Catty stands on a stack of generous open-source work. The list below
covers everything Catty bundles, depends on, or directly drew
inspiration from. The Swift code in this repo is MIT-licensed (see
[`LICENSE`](LICENSE)); third-party licenses are preserved verbatim
inside each dependency's source tree under `.build/checkouts/` after
`swift package resolve`.

## Open-source dependencies (SwiftPM)

The direct dependencies declared in `Package.swift`. Each retains
its upstream license — these are credits, not relicensings. The
transitive graph (NIO family, swift-crypto, BigInt, etc.) is
pulled in by Citadel; their license texts ship alongside their
source under `.build/checkouts/<package>/LICENSE` after
`swift package resolve`.

| Package | License | Author / Upstream |
|---|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | MIT | Miguel de Icaza |
| [Citadel](https://github.com/orlandos-nl/Citadel) | MIT | Joannis Orlandos / Orlandos NL |

## Bundled assets

Live under `Sources/Catty/Resources/` and ship inside the binary.
The Swift code is MIT but these assets retain their original
upstream licenses.

### Maxwell the cat (Dingus)

- File: `Sources/Catty/Resources/maxwell-the-cat.usdz`
- Source: <https://skfb.ly/oJrFP>
- Author: bean (alwayshasbean)
- License: [Creative Commons Attribution 4.0 International (CC-BY 4.0)](https://creativecommons.org/licenses/by/4.0/)
- Modifications: re-exported to USDZ for RealityKit; runtime scale
  tuned in `OrbitConfigState` and `Terminal3DRealityScene`.

Per CC-BY 4.0 §3(a)(1), redistribution must keep this attribution
intact and indicate that changes were made. Don't strip this file
when vendoring the package.

### Cairo Spiny Mouse (the rat)

- File: `Sources/Catty/Resources/rat.usdz`
- Source: bundled in [orhun/ratty](https://github.com/orhun/ratty) at
  `assets/objects/CairoSpinyMouse.obj` (the ratty repository is
  MIT-licensed).
- Modifications: converted from `.obj` to USDZ via Model I/O
  (`MDLAsset` → `.usdc` → zipped to `.usdz`).
- Notes: ratty bundles this asset without a separate per-asset
  attribution file. The original 3D-scan provenance is not
  documented upstream.

## Inspirations

### Terminal 3D

Catty's "terminal as a textured surface in a RealityKit scene"
direction was inspired by [Ratty](https://github.com/orhun/ratty), a
GPU-rendered terminal with inline 3D graphics by Orhun Parmaksız —
[MIT License](https://github.com/orhun/ratty/blob/main/LICENSE).
Their rat chases pixels in a terminal; our cat watches it happen
from RealityKit. Thanks for the spark.

---

If you replace either bundled asset with one you own outright (or
commission a permissively-licensed alternative), feel free to delete
the corresponding section here. The dependencies list above stays
required as long as those packages remain in `Package.swift`.

## See also

- [`LICENSE`](LICENSE) — Catty's own MIT license.
- [`Package.swift`](Package.swift) — full version-pinned dependency
  graph, source of truth for the dependencies table above.
- `~/.build/checkouts/<package>/LICENSE` — verbatim upstream license
  text for each dependency, available after `swift package resolve`.
