// Research: the RealityKit scene that sits BEHIND the SwiftUI terminal
// overlay in Terminal3DSceneView. Hosts Maxwell + a rat that orbit the
// terminal's footprint. Maxwell chases the rat by lagging its angle.
//
// When the terminal is zoomed in, the SwiftUI overlay covers most of this
// scene — Maxwell and the rat live around the edges. When zoomed out, the
// chase becomes the centerpiece.
//
// macOS-only (Outdoor). Requires macOS 15+ for SwiftUI `RealityView`.

#if os(macOS)
import SwiftUI
import RealityKit

public struct Terminal3DRealityScene: View {
    /// Every active terminal pane, keyed by spatial slot. Centre is
    /// always present (the initial session); cardinals are added
    /// when the user spawns from `Terminal3DSceneView`'s add-terminals
    /// mode. All panes live coplanar at z = 0 — the scene renders
    /// one textured plane per entry, all in the same RealityKit
    /// content.
    public let panes: [PaneSlot: TerminalLiveTextureSource]

    /// Convenience: the centre pane's source. Used by the per-frame
    /// texture/cursor-cat updates that historically operated on the
    /// single terminal. Always non-nil — centre is required.
    private var centreSource: TerminalLiveTextureSource {
        // swiftlint:disable:next force_unwrapping
        panes[.origin]!
    }

    /// Live-tunable orbit parameters. Owned by the parent so the debug
    /// slider panel and this scene share one source of truth.
    public let config: OrbitConfigState

    /// 1.0 = fully zoomed in (camera tight on the terminal plane, fills
    /// the frame, scene hidden); 0.3 = pulled all the way back (orbit
    /// fully visible). Driven by the parent's zoom state.
    public let zoom: Double

    /// User-driven camera look angles (radians). ⌥-drag in the parent
    /// view updates these. Applied as a head-turn on top of the
    /// zoom-driven camera position — so the user can look up, down, or
    /// even spin all the way around and watch the orbit pass behind them.
    public let lookYaw: Float
    public let lookPitch: Float

    /// World-space camera pan offset. In FPV mode this translates the
    /// camera laterally; in orbit mode it translates the focal point
    /// (so the camera still orbits, just around a shifted centre).
    public let panOffset: SIMD3<Float>

    /// Which interpretation of yaw/pitch/pan to use when placing the
    /// camera. Both modes share the same input state — the math differs.
    public let cameraMode: CameraMode

    /// Surface mesh per pane. Each terminal can sit on a different
    /// shape (flat / curved / Möbius). Mesh is rebuilt per-pane by
    /// `applySurfaceMode()` when the value for a slot changes.
    public let surfaceModes: [PaneSlot: TerminalSurfaceMode]

    /// Currently-selected pane. Drives the purple selection glow
    /// behind that pane's plane. `nil` hides every glow.
    public let activeSlot: PaneSlot?

    /// When true, Maxwell + rat orbit motion + cursor-cat bob/spin
    /// all freeze. Used by `iconComposeMode` in the host scene view
    /// so the user can stage a clean frame for the app icon
    /// screenshot.
    public let freezeOrbiters: Bool

    /// Legacy single-mode accessor for code paths still expecting
    /// one canonical surface (the cursor-cat positioning uses this
    /// for centre-pane bobbing). Returns the centre's mode.
    private var surfaceMode: TerminalSurfaceMode {
        surfaceModes[.origin] ?? .flat
    }

    public init(
        panes: [PaneSlot: TerminalLiveTextureSource],
        config: OrbitConfigState,
        zoom: Double,
        lookYaw: Float,
        lookPitch: Float,
        panOffset: SIMD3<Float>,
        cameraMode: CameraMode,
        surfaceModes: [PaneSlot: TerminalSurfaceMode],
        activeSlot: PaneSlot? = nil,
        freezeOrbiters: Bool = false
    ) {
        self.panes = panes
        self.config = config
        self.zoom = zoom
        self.lookYaw = lookYaw
        self.lookPitch = lookPitch
        self.panOffset = panOffset
        self.cameraMode = cameraMode
        self.surfaceModes = surfaceModes
        self.activeSlot = activeSlot
        self.freezeOrbiters = freezeOrbiters
    }

    @State private var orbiters = OrbitState()
    /// Per-slot plane entity refs. Centre is created in `make`, the
    /// cardinals are created lazily in `update` as the user spawns
    /// new panes. Each slot tracks its front + back plane separately
    /// — the back face shows a procedural grid pattern when the
    /// camera orbits behind.
    @State private var paneRefs = MultiPanePlaneRefs()
    @State private var terminalPlaneRef = TerminalPlaneRef()
    @State private var terminalPlaneBackRef = TerminalPlaneRef()
    @State private var cameraRef = CameraRef()
    /// One tiny spinning Maxwell per pane, parked at that pane's
    /// text cursor (à la ratty). Cats for empty slots stay hidden.
    @State private var cursorCatRefs = MultiPaneCursorCatRefs()
    /// Legacy single-cat ref kept pointing at the centre pane so
    /// any code that grew up around `cursorCatRef` still works.
    @State private var cursorCatRef = CursorCatRef()
    // Scene-local clock origin. Keeps `elapsed` small + Double-precision so
    // orbit/spin angles don't quantize on Float→radian conversion.
    // See `OrbiterRegistry.tick` for the underlying ULP discussion.
    @State private var startTime = Date()
    /// Frame-delta watchdog state. We track the previous tick's wall clock
    /// so we can log when SwiftUI hands us a frame > ~22 ms after the last
    /// (i.e. > 1 frame slip at 60 Hz). Mutated only inside the TimelineView
    /// closure on the main actor; intentionally not @State so updating it
    /// doesn't invalidate the body.
    @State private var frameWatchdog = FrameWatchdog()

    public var body: some View {
        // Back to `.animation` (display refresh — 60Hz on most Macs)
        // for buttery orbit motion. The 60Hz layout cost we saw on
        // the earlier `sample` was dominated by the duplicate-SSH
        // bug (5+ parallel Citadel sessions thrashing main); with
        // that fixed and the texture/material dirty-tracking in
        // place, the per-tick budget is well within frame.
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            let _ = frameWatchdog.tick(now: context.date)
            RealityView { content in
                buildScene(into: &content)
            } update: { content in
                ensurePaneEntities(into: &content)
                if !freezeOrbiters {
                    orbiters.tick(elapsed: elapsed, config: config)
                }
                syncPaneVisibility()
                applyTerminalTexture()
                applyCameraZoom()
                applySurfaceMode()
                if !freezeOrbiters {
                    updateCursorCat(elapsed: elapsed)
                }
            }
        }
    }

    @MainActor
    private func applyCameraZoom() {
        guard let camera = cameraRef.entity else { return }
        // Camera radius interpolates across three regimes so the
        // existing [0.3, 1.0] feel is preserved AND zoom can keep
        // pushing past 0.3 toward a comical-far distance. The user
        // can slide all the way to zoom=0.01 to see the cluster as
        // a tiny postage stamp inside the orbit + star backdrop.
        //
        //   zoom = 1.0  → radius 0.94  (terminal fills the frame)
        //   zoom = 0.3  → radius 2.4   (cluster + orbit visible)
        //   zoom = 0.01 → radius 22    (cluster is a dot)
        let nearR: Float = 0.94
        let midR: Float = 2.4
        let farR: Float = 22
        let radius: Float
        if zoom >= 0.3 {
            let t = Float(max(0, min(1, (zoom - 0.3) / 0.7)))
            radius = midR * (1 - t) + nearR * t
        } else {
            let t = Float(max(0, min(1, (0.3 - zoom) / 0.29)))
            radius = midR + (farR - midR) * t
        }
        // Retain `mix` for downstream FPV interpolation that still
        // expects the legacy 0..1 zoom-norm signal.
        let zoomNorm = max(0, min(1, (zoom - 0.3) / 0.7))
        let mix = Float(1 - zoomNorm)

        switch cameraMode {
        case .orbit:
            // Turntable: camera lives on a sphere around `focus`, always
            // pointing at it. yaw/pitch rotate the camera AROUND the
            // terminal; panOffset shifts the focal point (so you can
            // re-centre on something off-axis without losing the
            // terminal as the visual anchor). Radius comes from the
            // three-regime interpolation above.
            _ = mix  // unused in orbit; see FPV branches
            let focus = SIMD3<Float>(0, 0, 0) + panOffset
            let cosP = cos(lookPitch)
            let sinP = sin(lookPitch)
            let position = focus + SIMD3<Float>(
                cosP * sin(lookYaw) * radius,
                sinP * radius,
                cosP * cos(lookYaw) * radius
            )
            camera.position = position
            camera.look(at: focus, from: position, relativeTo: nil)

        case .ratPOV:
            // Chase-from-behind: camera sits behind the rat looking over
            // its back, tail in the foreground. Tried "drone above head"
            // — clipped into the body silhouette at this scale.
            applyRideAlongCamera(
                camera: camera,
                kind: .rat,
                eyeHeight: 0.03,
                // Rat is `faceTangent` — its orientation rotates [0,0,1] to
                // tangent, so the model's local forward is +Z.
                modelForward: SIMD3<Float>(0, 0, 1),
                forwardOffset: -0.08
            )
            return
        case .catPOV:
            // Top-of-head POV: camera sits right at the crown of the cat's
            // head and looks forward along his facing direction. Pirouettes
            // with him because we read his orientation each frame.
            applyRideAlongCamera(
                camera: camera,
                kind: .maxwell,
                eyeHeight: 0.22,
                // Maxwell's USDZ faces -Z in model space; freeSpin rotates
                // that around Y so the camera pirouettes with him.
                modelForward: SIMD3<Float>(0, 0, -1),
                forwardOffset: 0.0
            )
            return
        }
        // Restore the orbit-mode field of view (POV modes widen it).
        camera.camera.fieldOfViewInDegrees = 60
    }

    /// Ride-along camera for `.ratPOV` / `.catPOV`. Uses the orbiter
    /// entity's current world orientation as the truth (so the rat looks
    /// along the orbit tangent and the cat pirouettes), positions the
    /// camera slightly above + forward of the model centre so the head
    /// doesn't clip into frame, then applies user lookYaw/lookPitch as a
    /// natural head-turn relative to forward. FOV widens to 80° so the
    /// terminal stays comfortably in view.
    @MainActor
    private func applyRideAlongCamera(
        camera: PerspectiveCamera,
        kind: OrbitState.Kind,
        eyeHeight: Float,
        modelForward: SIMD3<Float>,
        forwardOffset: Float
    ) {
        guard let orbiter = orbiters.entity(for: kind) else {
            camera.position = [0, 0.2, 0]
            camera.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            return
        }
        let pos = orbiter.position(relativeTo: nil)
        let orient = orbiter.orientation(relativeTo: nil)
        // World-space forward direction of the entity.
        let forward = simd_normalize(orient.act(modelForward))
        // Eye position: top-of-head, with a small nudge forward so the
        // back-of-head geometry doesn't intrude into the frame.
        let eye = pos + SIMD3<Float>(0, eyeHeight, 0) + forward * forwardOffset
        let target = eye + forward
        camera.look(at: target, from: eye, relativeTo: nil)
        // User head-turn on top of the entity's facing direction.
        let yawQuat = simd_quatf(angle: lookYaw, axis: [0, 1, 0])
        let pitchQuat = simd_quatf(angle: lookPitch, axis: [1, 0, 0])
        camera.orientation = camera.orientation * yawQuat * pitchQuat
        // Wider FOV than the orbit camera so the terminal stays in view
        // even when we're orbiting close to it from a rider's seat.
        camera.camera.fieldOfViewInDegrees = 80
    }

    /// Allocate the per-pane entities (front plane, back plane,
    /// glow plane, cursor-cat companion) for every coord in `panes`
    /// that doesn't already have refs. Cheap when the set is stable
    /// — the loop is skipped after the first pass. Despawned coords
    /// have their entities yanked from the scene to free up GPU
    /// resources.
    @MainActor
    private func ensurePaneEntities(into content: inout RealityViewCameraContent) {
        // Add entities for newly-spawned panes.
        for slot in panes.keys where paneRefs.fronts[slot] == nil {
            spawnPaneEntities(at: slot, into: &content)
        }
        // Remove entities for panes that have since been torn down.
        for slot in Array(paneRefs.fronts.keys) where panes[slot] == nil {
            despawnPaneEntities(at: slot)
        }
    }

    @MainActor
    private func spawnPaneEntities(at slot: PaneSlot, into content: inout RealityViewCameraContent) {
        // Back-grid texture is shared across panes — regenerated each
        // time we add a new pane, which is cheap enough relative to
        // how rarely it happens.
        var sharedBackMaterial = UnlitMaterial(color: .init(white: 0.07, alpha: 1))
        if let backGrid = makeTerminalBackGridTexture() {
            sharedBackMaterial = UnlitMaterial()
            sharedBackMaterial.color = .init(tint: .white, texture: .init(backGrid))
        }

        let plane = ModelEntity(
            mesh: .generatePlane(width: 1.6, height: 1.05, cornerRadius: 0),
            materials: [UnlitMaterial(color: .black)]
        )
        plane.position = slot.worldPosition
        content.add(plane)

        let back = ModelEntity(
            mesh: .generatePlane(width: 1.6, height: 1.05, cornerRadius: 0),
            materials: [sharedBackMaterial]
        )
        back.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        back.position = slot.worldPosition + [0, 0, -0.001]
        content.add(back)

        let frontRef = TerminalPlaneRef()
        frontRef.entity = plane
        paneRefs.fronts[slot] = frontRef
        let backRef = TerminalPlaneRef()
        backRef.entity = back
        paneRefs.backs[slot] = backRef

        if let glowTexture = makeSelectionGlowTexture() {
            var glowMaterial = UnlitMaterial()
            glowMaterial.color = .init(tint: .white, texture: .init(glowTexture))
            glowMaterial.blending = .transparent(opacity: .init(floatLiteral: 1.0))
            glowMaterial.faceCulling = .none
            let glow = ModelEntity(
                mesh: .generatePlane(width: 1.72, height: 1.13, cornerRadius: 0),
                materials: [glowMaterial]
            )
            glow.position = slot.worldPosition + [0, 0, -0.002]
            glow.isEnabled = false
            content.add(glow)
            paneRefs.glows[slot] = glow
        }

        // Cursor-cat companion for this pane.
        let cursorCat = Entity()
        cursorCat.name = "cursorCat-\(slot.rawValue)"
        var cursorCatModel: Entity?
        if let model = try? Entity.load(named: "maxwell-the-cat", in: .module) {
            cursorCat.addChild(model)
            cursorCatModel = model
        } else {
            let placeholder = ModelEntity(
                mesh: .generateSphere(radius: 0.5),
                materials: [SimpleMaterial(color: .systemPink, isMetallic: false)]
            )
            cursorCat.addChild(placeholder)
            cursorCatModel = placeholder
        }
        if let model = cursorCatModel {
            let scale: Float = 0.00009
            model.scale = [scale, scale, scale]
        }
        content.add(cursorCat)
        let catRef = CursorCatRef()
        catRef.entity = cursorCat
        catRef.model = cursorCatModel
        cursorCatRefs.cats[slot] = catRef

        // Update legacy single-pane refs when the origin is spawned.
        if slot == .origin {
            terminalPlaneRef.entity = plane
            terminalPlaneBackRef.entity = back
            cursorCatRef.entity = cursorCat
            cursorCatRef.model = cursorCatModel
        }
    }

    @MainActor
    private func despawnPaneEntities(at slot: PaneSlot) {
        paneRefs.fronts[slot]?.entity?.removeFromParent()
        paneRefs.fronts.removeValue(forKey: slot)
        paneRefs.backs[slot]?.entity?.removeFromParent()
        paneRefs.backs.removeValue(forKey: slot)
        paneRefs.glows[slot]?.removeFromParent()
        paneRefs.glows.removeValue(forKey: slot)
        cursorCatRefs.cats[slot]?.entity?.removeFromParent()
        cursorCatRefs.cats.removeValue(forKey: slot)
    }

    /// Toggle each pane's front + back entity `isEnabled` based on
    /// whether the user has spawned into that slot. Cheap (just sets
    /// a Bool on the entity) so we can run it every frame.
    @MainActor
    private func syncPaneVisibility() {
        for slot in panes.keys {
            let active = panes[slot] != nil
            paneRefs.fronts[slot]?.entity?.isEnabled = active
            paneRefs.backs[slot]?.entity?.isEnabled = active
            // Selection glow: only enabled when this slot has a pane
            // AND the slot matches the currently-active selection.
            paneRefs.glows[slot]?.isEnabled = active && (slot == activeSlot)
        }
    }

    @MainActor
    private func applyTerminalTexture() {
        // Iterate every active pane. The cardinal panes are
        // pre-created with `isEnabled = false`; they're toggled on by
        // `syncPaneVisibility()` when the user spawns into a slot.
        // Texture refresh is keyed per-pane on the same monotonic
        // version counter used by the original single-pane code path,
        // so non-centre panes get the same skip-when-clean fast path.
        let alpha = max(0, min(1, config.terminalOpacity))
        for slot in panes.keys {
            guard let source = panes[slot],
                  let ref = paneRefs.fronts[slot],
                  let plane = ref.entity,
                  let texture = source.currentTexture else { continue }
            let version = source.textureVersion
            if ref.appliedTextureVersion == version,
               abs(ref.appliedAlpha - alpha) < 0.001 {
                continue
            }
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            if alpha < 0.999 {
                material.blending = .transparent(opacity: .init(floatLiteral: alpha))
            }
            plane.model?.materials = [material]
            ref.appliedTextureVersion = version
            ref.appliedAlpha = alpha
        }
    }

    /// Rebuilds the terminal mesh when the surface mode changes. Cheap —
    /// each mesh is ≤200 verts — but we only do it on actual transitions
    /// to avoid wasted GPU uploads. Keeps the back-plane mesh in sync so
    /// the grid follows curved geometry.
    @MainActor
    private func applySurfaceMode() {
        // Iterate every active pane, applying that slot's surface
        // mode to its plane. Back plane is hidden for Möbius (a
        // one-sided surface — front material's faceCulling = .none
        // handles double-sided rendering).
        for slot in panes.keys {
            let mode = surfaceModes[slot] ?? .flat
            guard let ref = paneRefs.fronts[slot],
                  let plane = ref.entity,
                  ref.appliedMode != mode else { continue }
            let mesh = makeTerminalMesh(for: mode)
            plane.model?.mesh = mesh
            ref.appliedMode = mode

            if let backRef = paneRefs.backs[slot], let back = backRef.entity {
                back.model?.mesh = mesh
                back.isEnabled = (mode != .mobius) && (panes[slot] != nil)
                backRef.appliedMode = mode
            }
        }
    }

    /// Centre-bulge warp à la ratty's vertex distortion. The plane is
    /// finely tessellated and each vertex's Z is offset by a Gaussian
    /// of its distance from the centre — so the middle pokes toward
    /// the camera and the corners stay flat. Reads as a pillow / CRT
    /// dome.
    private func makeWarpMesh() -> MeshResource {
        let width: Float = 1.6
        let height: Float = 1.05
        let segX = 40
        let segY = 28
        let maxBulge: Float = 0.32

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        for j in 0...segY {
            let vNorm = Float(j) / Float(segY)
            let y = (0.5 - vNorm) * height
            for i in 0...segX {
                let uNorm = Float(i) / Float(segX)
                let x = (uNorm - 0.5) * width
                let dx = (uNorm - 0.5) * 2
                let dy = (vNorm - 0.5) * 2
                let r2 = dx * dx + dy * dy
                // Gaussian dome — peak at centre, ~0 at the corners.
                let z = maxBulge * exp(-r2 * 1.8)
                positions.append(SIMD3<Float>(x, y, z))
                // Approximate normal — points outward toward camera
                // with a slight tilt from the bulge gradient. Good
                // enough for UnlitMaterial (which ignores lighting).
                normals.append(SIMD3<Float>(0, 0, 1))
                // Flip v to match RealityKit's flat-plane convention
                // (top-of-mesh = v=1). Without this flip the bulge
                // renders the texture upside-down — j=0 is top y
                // here but v=0 is bottom-of-texture in flat plane,
                // so a literal `vNorm` reads the texture inverted.
                uvs.append(SIMD2<Float>(uNorm, 1 - vNorm))
            }
        }

        var indices: [UInt32] = []
        let cols = segX + 1
        for j in 0..<segY {
            for i in 0..<segX {
                let a = UInt32(j * cols + i)
                let b = UInt32(j * cols + i + 1)
                let c = UInt32((j + 1) * cols + i)
                let d = UInt32((j + 1) * cols + i + 1)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        return buildMesh(positions: positions, normals: normals,
                         uvs: uvs, indices: indices)
    }

    /// Builds the textured terminal surface for a given mode.
    /// - Flat: rounded-corner plane (current default).
    /// - Curved: concave cinemascope arc (~60° of sweep). UVs are linear
    ///   in u so terminal columns stay vertical despite the curve.
    /// - Möbius: parametric strip with a single half-twist. Texture
    ///   wraps once around the loop — text bends impressively but is
    ///   only legible in patches, which is the point.
    private func makeTerminalMesh(for mode: TerminalSurfaceMode) -> MeshResource {
        switch mode {
        case .flat:
            return .generatePlane(width: 1.6, height: 1.05, cornerRadius: 0)
        case .curved:
            return makeCurvedMesh()
        case .mobius:
            return makeMobiusMesh()
        case .warp:
            return makeWarpMesh()
        }
    }

    /// Concave wrap. Same overall plane dims (1.6 × 1.05), bent around
    /// a cylinder so the edges curve toward the camera (+Z). Built as a
    /// strip of quads along X with a single height step along Y.
    private func makeCurvedMesh() -> MeshResource {
        let width: Float = 1.6
        let height: Float = 1.05
        let arc: Float = .pi / 3   // 60° total sweep
        let radius: Float = width / arc
        let segments = 48           // along the curve

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        for i in 0...segments {
            let u = Float(i) / Float(segments)
            let theta = (u - 0.5) * arc
            // Cylinder centred at (0, 0, +radius): point on arc closest
            // to camera. At theta=0 → (0, _, 0) = plane centre;
            // |theta|=arc/2 → small +Z bump → edge curves toward camera.
            let x = radius * sin(theta)
            let z = radius * (1 - cos(theta))
            // Inward-facing normal (pointing at the camera).
            let normal = SIMD3<Float>(-sin(theta), 0, -cos(theta))
            for vIndex in 0...1 {
                let v = Float(vIndex)              // 0 = top, 1 = bottom
                let y = height * 0.5 - v * height
                positions.append(SIMD3<Float>(x, y, z))
                normals.append(normal)
                // RealityKit's `.generatePlane` puts v=1 at the top of
                // the mesh and v=0 at the bottom — so the curved mesh
                // (which iterates vIndex=0 at top) needs v inverted
                // to match. u is NOT flipped — geometry x increases
                // left-to-right as the camera sees it (theta from
                // -arc/2 → +arc/2), which already matches the texture
                // column ordering.
                uvs.append(SIMD2<Float>(u, 1 - v))
            }
        }

        var indices: [UInt32] = []
        for i in 0..<segments {
            let topLeft = UInt32(i * 2)
            let bottomLeft = topLeft + 1
            let topRight = UInt32((i + 1) * 2)
            let bottomRight = topRight + 1
            indices.append(contentsOf: [topLeft, bottomLeft, topRight,
                                        topRight, bottomLeft, bottomRight])
        }

        return buildMesh(positions: positions, normals: normals,
                         uvs: uvs, indices: indices)
    }

    /// Möbius strip. Standard parametrisation: loop param `u ∈ [0, 2π)`
    /// wraps around the central axis, cross param `v ∈ [-w/2, +w/2]`
    /// runs across the strip width. The (u/2) factor on the cross-axis
    /// rotation gives the half-twist that makes it a Möbius.
    private func makeMobiusMesh() -> MeshResource {
        let bigR: Float = 0.55     // loop radius
        let stripWidth: Float = 0.3
        let loopSegments = 128      // around the loop — high for a smooth twist
        let crossSegments = 8       // across the strip — multiple quads so
                                    // the twist warps the texture visibly
                                    // instead of just stretching one quad
                                    // around the loop

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        for i in 0...loopSegments {
            let uNorm = Float(i) / Float(loopSegments)
            let u = uNorm * 2 * .pi
            for j in 0...crossSegments {
                let vNorm = Float(j) / Float(crossSegments)
                let v = (vNorm - 0.5) * stripWidth
                let halfU = u / 2
                let r = bigR + v * cos(halfU)
                let x = r * cos(u)
                let y = v * sin(halfU)
                let z = r * sin(u)
                positions.append(SIMD3<Float>(x, y, z))
                // Approximate normal via partial derivatives (cheap, good
                // enough for an UnlitMaterial that ignores them anyway).
                let n = SIMD3<Float>(cos(halfU) * cos(u), sin(halfU), cos(halfU) * sin(u))
                normals.append(simd_normalize(n))
                uvs.append(SIMD2<Float>(uNorm, vNorm))
            }
        }

        var indices: [UInt32] = []
        let cols = crossSegments + 1
        for i in 0..<loopSegments {
            for j in 0..<crossSegments {
                let a = UInt32(i * cols + j)
                let b = UInt32(i * cols + j + 1)
                let c = UInt32((i + 1) * cols + j)
                let d = UInt32((i + 1) * cols + j + 1)
                // Front-facing winding…
                indices.append(contentsOf: [a, c, b, b, c, d])
                // …plus reversed-winding duplicates so the strip
                // renders on both sides. Möbius is a one-sided surface
                // topologically, but a one-sided MESH would be invisible
                // when the camera orbits to the "other" face. Cheap fix:
                // double the triangles, no material magic needed.
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }

        return buildMesh(positions: positions, normals: normals,
                         uvs: uvs, indices: indices)
    }

    /// Procedural selection-glow texture: transparent middle, purple
    /// outer ring that softens toward the edge. Lives behind the
    /// terminal plane on the active slot's glow entity, so it reads
    /// as a halo around the pane regardless of camera angle.
    private func makeSelectionGlowTexture() -> TextureResource? {
        let width = 1024
        let height = 696
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        // Soft purple — same colour family as the SwiftUI halo we
        // had previously, just baked into a texture so it can ride
        // the RealityKit transform.
        let r: Double = 160.0
        let g: Double = 95.0
        let b: Double = 215.0

        // Texture coords map to a plane slightly larger than the
        // terminal pane (1.6 × 1.05). The portion of the glow that
        // would sit *inside* the pane is hidden by the terminal
        // plane in front of it, so we just need a soft outward
        // falloff from the pane edge.
        //
        // Texture plane is (textureW × textureH) world-units below.
        let textureW: Double = 1.72        // pane width  + small halo room
        let textureH: Double = 1.13        // pane height + small halo room
        let paneW: Double = 1.6
        let paneH: Double = 1.05
        let sigma: Double = 0.018          // tight halo — falls off fast
        let maxAlpha: Double = 0.28        // gentle, never pure-purple

        for y in 0..<height {
            for x in 0..<width {
                let nx = Double(x) / Double(width - 1)
                let ny = Double(y) / Double(height - 1)
                // Convert pixel to a world-space offset from the
                // texture centre.
                let tx = (nx - 0.5) * textureW
                let ty = (0.5 - ny) * textureH
                // Distance outward from the nearest pane edge.
                // 0 anywhere inside the pane footprint, positive
                // outside (Euclidean for the corners).
                let dx = max(0, abs(tx) - paneW / 2)
                let dy = max(0, abs(ty) - paneH / 2)
                let dOut = sqrt(dx * dx + dy * dy)
                // Gaussian halo: brightest right at the edge, fades
                // smoothly as we move outward into space.
                let g_alpha = exp(-(dOut * dOut) / (sigma * sigma))
                let alpha = maxAlpha * g_alpha
                let idx = (y * width + x) * 4
                pixels[idx + 0] = UInt8(r)
                pixels[idx + 1] = UInt8(g)
                pixels[idx + 2] = UInt8(b)
                pixels[idx + 3] = UInt8(max(0, min(255, alpha * 255)))
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        guard let cgImage = context.makeImage() else { return nil }
        let options = TextureResource.CreateOptions(semantic: .color)
        return try? TextureResource(image: cgImage, options: options)
    }

    /// Procedural texture for the back of the terminal: a grid of cells
    /// suggesting "this is where text would be" without rendering the
    /// live text. Generated once at scene-build time; cell opacity
    /// varies via a stable hash so it doesn't look perfectly uniform.
    private func makeTerminalBackGridTexture() -> TextureResource? {
        let width = 880
        let height = 566
        let cols = 80
        let rows = 25
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Background — slightly cooler than the terminal black so the
        // back reads as "machine chassis" rather than "void".
        context.setFillColor(NSColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let cellW = CGFloat(width) / CGFloat(cols)
        let cellH = CGFloat(height) / CGFloat(rows)
        let inset: CGFloat = 1
        for row in 0..<rows {
            for col in 0..<cols {
                // Stable hash → "active cell" opacity. Looks vaguely
                // like terminal text fill patterns without being
                // recognisable letters.
                let seed = (row &* 73 &+ col &* 131) % 17
                let isActive = seed > 11
                let alpha = isActive ? 0.18 : (0.04 + Double(seed) * 0.008)
                context.setFillColor(NSColor(white: 0.85, alpha: alpha).cgColor)
                context.fill(CGRect(
                    x: CGFloat(col) * cellW + inset,
                    y: CGFloat(row) * cellH + inset,
                    width: cellW - inset * 2,
                    height: cellH - inset * 2
                ))
            }
        }

        guard let cgImage = context.makeImage() else { return nil }
        let options = TextureResource.CreateOptions(semantic: .color)
        return try? TextureResource(image: cgImage, options: options)
    }

    private func buildMesh(
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        uvs: [SIMD2<Float>],
        indices: [UInt32]
    ) -> MeshResource {
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        // Fallback to a flat plane if the descriptor fails — should
        // never happen for static geometry like this.
        return (try? MeshResource.generate(from: [descriptor]))
            ?? .generatePlane(width: 1.6, height: 1.05)
    }

    // MARK: - Scene setup

    @MainActor
    private func buildScene(into content: inout RealityViewCameraContent) {
        // Explicit camera positioned ABOVE the orbit plane so the XZ ring
        // reads as an ellipse (Saturn-style) rather than edge-on. Higher
        // Y gives more downward tilt → more of the back arc of the orbit
        // appears ABOVE the terminal in screen space rather than behind it.
        let camera = PerspectiveCamera()
        camera.position = [0, 0.0, 1.05]  // initial tight zoom; applyCameraZoom() refines per frame
        camera.look(at: [0, 0, 0], from: camera.position, relativeTo: nil)
        content.add(camera)
        cameraRef.entity = camera

        // The terminal: a depth-culling black plane at world origin. This
        // is the FIX for "Maxwell stays below the terminal" — by putting
        // an actual entity at world Z=0, RealityKit can depth-test the
        // orbiting characters against it. When Maxwell is at world z < 0
        // (behind the plane from camera POV), he disappears behind it;
        // when at z > 0, he renders in front.
        //
        // The SwiftUI terminal overlay sits on TOP of this plane in screen
        // space (live & typeable), but the plane provides the depth wall
        // RealityKit needs. Future iteration: replace the SwiftUI overlay
        // entirely by texturing this plane with live NSView snapshots.
        // Plane is in the XY plane (vertical), facing +Z toward the camera.
        // Starts black; the per-frame `applyTerminalTexture()` swaps in the
        // live NSView snapshot once the texture pipeline is warm.
        //
        // Plane size deliberately overshoots the camera's visible viewport
        // at zoom=1.0 so no starfield bleeds through around the edges.
        // The texture itself has black padding (TerminalLiveTextureSource)
        // so the actual terminal text stays inside the visible area while
        // the dark edges spill outside.
        // Pre-create planes for every cardinal slot so spawning a new
        // pane is just a visibility toggle in the update closure (no
        // mid-scene entity creation). Centre is always enabled; the
        // four cardinals start `isEnabled = false` and turn on when
        // `panes[slot]` becomes non-nil.
        var sharedBackMaterial = UnlitMaterial(color: .init(white: 0.07, alpha: 1))
        if let backGrid = makeTerminalBackGridTexture() {
            sharedBackMaterial = UnlitMaterial()
            sharedBackMaterial.color = .init(tint: .white, texture: .init(backGrid))
        }

        for slot in panes.keys {
            let plane = ModelEntity(
                mesh: .generatePlane(width: 1.6, height: 1.05, cornerRadius: 0),
                materials: [UnlitMaterial(color: .black)]
            )
            plane.position = slot.worldPosition
            plane.isEnabled = (slot == .origin)
            content.add(plane)

            let back = ModelEntity(
                mesh: .generatePlane(width: 1.6, height: 1.05, cornerRadius: 0),
                materials: [sharedBackMaterial]
            )
            back.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            // Tiny -Z offset prevents z-fighting with the front plane.
            back.position = slot.worldPosition + [0, 0, -0.001]
            back.isEnabled = (slot == .origin)
            content.add(back)

            let frontRef = TerminalPlaneRef()
            frontRef.entity = plane
            paneRefs.fronts[slot] = frontRef

            let backRef = TerminalPlaneRef()
            backRef.entity = back
            paneRefs.backs[slot] = backRef

            if slot == .origin {
                // Preserve the legacy single-pane refs so the existing
                // texture/surface-mode update paths keep operating on
                // the centre plane without rewrites.
                terminalPlaneRef.entity = plane
                terminalPlaneBackRef.entity = back
            }

            // Selection-glow plane: slightly larger than the
            // terminal plane, parked just behind it, textured with a
            // purple edge-only outline. Enabled per-frame for the
            // active slot only — by living in the RealityKit scene
            // it inherits the camera's view transform, so the glow
            // tracks the pane as the user orbits.
            if let glowTexture = makeSelectionGlowTexture() {
                var glowMaterial = UnlitMaterial()
                glowMaterial.color = .init(tint: .white, texture: .init(glowTexture))
                glowMaterial.blending = .transparent(opacity: .init(floatLiteral: 1.0))
                glowMaterial.faceCulling = .none
                // Glow plane footprint matches the texture's
                // generation extents so each texel maps to the
                // world-position it was rendered for. Just enough
                // bigger than the pane to contain the falloff.
                let glow = ModelEntity(
                    mesh: .generatePlane(width: 1.72, height: 1.13, cornerRadius: 0),
                    materials: [glowMaterial]
                )
                // Just behind the front plane so the texture's
                // transparent middle reveals the terminal underneath.
                // Slightly larger so the purple ring extends past
                // the pane edges.
                glow.position = slot.worldPosition + [0, 0, -0.002]
                glow.isEnabled = false
                content.add(glow)
                paneRefs.glows[slot] = glow
            }
        }

        // Soft directional fill so the cat/rat don't render as silhouettes.
        let light = DirectionalLight()
        light.light.intensity = 4000
        light.light.color = .white
        light.orientation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])
        content.add(light)

        // Maxwell — loads from the package bundle (Sources/Catty/Resources/maxwell-the-cat.usdz).
        let maxwell = Entity()
        maxwell.name = "maxwell"
        var maxwellModel: Entity?
        do {
            let model = try Entity.load(named: "maxwell-the-cat", in: .module)
            // Scale is applied per-tick by OrbitState from the live config.
            maxwell.addChild(model)
            maxwellModel = model
            print("✅ Loaded Maxwell USDZ")
        } catch {
            let placeholder = ModelEntity(
                mesh: .generateBox(size: 0.18),
                materials: [SimpleMaterial(color: .orange, isMetallic: false)]
            )
            maxwell.addChild(placeholder)
            maxwellModel = placeholder
            print("❌ Maxwell USDZ load failed: \(error.localizedDescription) — using orange-box placeholder")
        }
        content.add(maxwell)
        orbiters.register(entity: maxwell, model: maxwellModel, kind: .maxwell, spinMode: .freeSpin)

        // Rat — converted from ratty's CairoSpinyMouse.obj via Model I/O
        // (`MDLAsset` → .usdc → zipped to .usdz so XcodeGen ships it).
        // Falls back to a procedural rat if the asset didn't ship.
        let rat = Entity()
        rat.name = "rat"
        var ratModel: Entity?
        do {
            let model = try Entity.load(named: "rat", in: .module)
            rat.addChild(model)
            ratModel = model
            print("✅ Loaded rat USDZ (CairoSpinyMouse)")
        } catch {
            let fallback = buildProceduralRat()
            rat.addChild(fallback)
            ratModel = fallback
            print("❌ rat USDZ load failed: \(error.localizedDescription) — using procedural")
        }
        content.add(rat)
        orbiters.register(entity: rat, model: ratModel, kind: .rat, spinMode: .faceTangent)

        // Cursor companions — one tiny spinning Maxwell per pane,
        // parked at that pane's text cursor (à la ratty). Separate
        // USDZ instances from the orbiter; positioned per-frame by
        // `updateCursorCat`. Cardinals start hidden and become
        // visible when the user spawns into the slot.
        for slot in panes.keys {
            let cursorCat = Entity()
            cursorCat.name = "cursorCat-\(slot.rawValue)"
            var cursorCatModel: Entity?
            if let model = try? Entity.load(named: "maxwell-the-cat", in: .module) {
                cursorCat.addChild(model)
                cursorCatModel = model
            } else {
                let placeholder = ModelEntity(
                    mesh: .generateSphere(radius: 0.5),
                    materials: [SimpleMaterial(color: .systemPink, isMetallic: false)]
                )
                cursorCat.addChild(placeholder)
                cursorCatModel = placeholder
            }
            // ~3 terminal cells tall. The orbiter Maxwell uses ~0.0004;
            // the cursor copy wants to be a fraction of that so it reads
            // as a glyph-sized companion rather than a co-star.
            if let model = cursorCatModel {
                let scale: Float = 0.00009
                model.scale = [scale, scale, scale]
            }
            cursorCat.isEnabled = (slot == .origin)
            content.add(cursorCat)

            let ref = CursorCatRef()
            ref.entity = cursorCat
            ref.model = cursorCatModel
            cursorCatRefs.cats[slot] = ref

            if slot == .origin {
                // Keep the legacy single-cat ref in sync so any code
                // that still references it operates on the centre cat.
                cursorCatRef.entity = cursorCat
                cursorCatRef.model = cursorCatModel
            }
        }
    }

    /// Park each pane's cursor companion at that pane's text-cursor
    /// cell on the textured plane (flat surface only). Spins on Y
    /// and bobs on a sine, mirroring ratty's cursor-model animation.
    @MainActor
    private func updateCursorCat(elapsed: TimeInterval) {
        for slot in panes.keys {
            updateCursorCat(elapsed: elapsed, slot: slot)
        }
    }

    @MainActor
    private func updateCursorCat(elapsed: TimeInterval, slot: PaneSlot) {
        guard let cat = cursorCatRefs.cats[slot]?.entity else { return }
        // Empty slot → hide and bail.
        guard let source = panes[slot] else {
            cat.isEnabled = false
            return
        }
        // Curved / Möbius would need the surface-warp math; skip for now.
        guard surfaceMode == .flat else {
            cat.isEnabled = false
            return
        }
        cat.isEnabled = true

        let (cols, rows) = source.terminalGridSize
        let (col, row) = source.cursorCell
        // Plane is 1.6 × 1.05, centred on the slot's worldPosition.
        let planeW: Float = 1.6
        let planeH: Float = 1.05
        let uvx = (Float(col) + 0.5) / Float(cols)
        let uvy = (Float(row) + 0.5) / Float(rows)
        let cellW = planeW / Float(cols)
        let cellH = planeH / Float(rows)
        let bob = Float(sin(elapsed * 2.2)) * cellH * 0.18
        // Park Maxwell one cell-width to the right of the trailing
        // character (ratty's "after the cursor" pose). His USDZ pivot
        // is at his feet, so without a downward shift he renders ~3
        // cells *above* the text. Drop by 1.6 cellH so the feet land
        // on the cursor row baseline — that puts him standing right
        // next to the trailing character at the same visual line.
        let localX = (uvx - 0.5) * planeW + cellW * 1.2
        let localY = (0.5 - uvy) * planeH + bob - cellH * 1.6
        // Sit slightly in front of the plane so the cat occludes the glyph
        // it's parked on rather than z-fighting with it. Offset is added
        // to the slot's world position so each pane's cat lives at the
        // correct cluster location.
        cat.position = slot.worldPosition + [localX, localY, 0.03]

        // Spin around Y at ~1.4 rad/s, tilted -0.25 on X (ratty's pose).
        // Wrap the angle in Double before the Float cast — same ULP guard
        // as the orbiters.
        let spin = Float((elapsed * 1.4).truncatingRemainder(dividingBy: 2 * .pi))
        cat.orientation = simd_quatf(angle: spin, axis: [0, 1, 0])
            * simd_quatf(angle: -0.25, axis: [1, 0, 0])
    }
}

// MARK: - Entity reference holders
//
// Reference types so the `make` closure can stash entities for the
// `update` closure to find later (per-frame texture refresh, per-frame
// camera zoom, etc.) without rebuilding the scene every tick.

@MainActor
final class MultiPanePlaneRefs {
    /// Plane entity refs keyed by slot. Centre is added in `make`,
    /// cardinals are added in `update` as they spawn.
    var fronts: [PaneSlot: TerminalPlaneRef] = [:]
    var backs: [PaneSlot: TerminalPlaneRef] = [:]
    /// Per-slot purple selection glow planes parented just behind
    /// the front plane. Only one is `isEnabled = true` at a time —
    /// the one matching the currently-active slot.
    var glows: [PaneSlot: ModelEntity] = [:]
    /// Anchor parent for every pane in this scene, so adding /
    /// removing planes happens by parenting to a single node rather
    /// than walking `content` for ad-hoc additions.
    weak var anchor: Entity?
}

@MainActor
final class MultiPaneCursorCatRefs {
    /// Per-slot Maxwell-at-the-cursor refs. Created upfront in
    /// `buildScene` so per-frame positioning is a cheap entity
    /// transform without re-loading USDZ.
    var cats: [PaneSlot: CursorCatRef] = [:]
}

@MainActor
final class TerminalPlaneRef {
    weak var entity: ModelEntity?
    /// Tracks which surface mode the current `entity.model.mesh` was
    /// built for, so the update closure can short-circuit when nothing
    /// has changed. `nil` until first applied.
    var appliedMode: TerminalSurfaceMode?
    /// Version of the last applied texture frame (matches
    /// `TerminalLiveTextureSource.textureVersion`). Lets the update
    /// closure skip material rebuilds when the capture loop hasn't
    /// produced new pixels since the previous tick.
    var appliedTextureVersion: Int = -1
    /// Last applied alpha — combined with appliedTextureVersion into a
    /// cheap dirty check.
    var appliedAlpha: Float = 1.0
}

@MainActor
private final class CameraRef {
    weak var entity: PerspectiveCamera?
}

@MainActor
final class CursorCatRef {
    /// Root entity positioned at the terminal cursor cell.
    weak var entity: Entity?
    /// Inner USDZ model — for the one-time scale on load.
    weak var model: Entity?
}


// MARK: - Procedural rat

@MainActor
private func buildProceduralRat() -> Entity {
    let rat = Entity()
    rat.name = "rat"

    let furColor = SimpleMaterial(
        color: .init(red: 0.55, green: 0.45, blue: 0.4, alpha: 1),
        roughness: 0.9,
        isMetallic: false
    )
    let earPink = SimpleMaterial(
        color: .init(red: 0.85, green: 0.55, blue: 0.6, alpha: 1),
        roughness: 0.6,
        isMetallic: false
    )

    // Body — slightly stretched along Z (forward direction).
    let body = ModelEntity(
        mesh: .generateSphere(radius: 0.06),
        materials: [furColor]
    )
    body.scale = [1.0, 0.8, 1.6]  // squash + stretch into "rat-shaped lozenge"
    rat.addChild(body)

    // Head — smaller sphere pushed forward.
    let head = ModelEntity(
        mesh: .generateSphere(radius: 0.045),
        materials: [furColor]
    )
    head.position = [0, 0.01, 0.08]
    rat.addChild(head)

    // Ears — two small pink discs angled outward on top of the head.
    for sign: Float in [-1, 1] {
        let ear = ModelEntity(
            mesh: .generateSphere(radius: 0.018),
            materials: [earPink]
        )
        ear.scale = [1, 1, 0.4]
        ear.position = [sign * 0.025, 0.04, 0.085]
        rat.addChild(ear)
    }

    // Tail — long thin box trailing behind, slightly raised.
    let tail = ModelEntity(
        mesh: .generateBox(size: [0.01, 0.01, 0.16], cornerRadius: 0.004),
        materials: [furColor]
    )
    tail.position = [0, 0.015, -0.12]
    rat.addChild(tail)

    return rat
}

// MARK: - Orbit state holder

@MainActor
@Observable
private final class OrbitState {
    enum Kind { case maxwell, rat }

    enum SpinMode {
        /// Continuously spin around the Y axis (Maxwell — pirouetting cat).
        case freeSpin
        /// Face the direction of travel (rat running along the orbit path).
        case faceTangent
    }

    struct Orbiter {
        weak var entity: Entity?
        weak var model: Entity?    // the inner USDZ model — for per-tick scale updates
        let kind: Kind
        let spinMode: SpinMode
    }

    private var orbiters: [Orbiter] = []

    /// Look up the live entity for a kind so the camera can ride along
    /// in `.ratPOV` / `.catPOV` modes. Returns nil before the orbiter is
    /// registered or after its entity has been released.
    func entity(for kind: Kind) -> Entity? {
        orbiters.first(where: { $0.kind == kind })?.entity
    }

    func register(entity: Entity, model: Entity?, kind: Kind, spinMode: SpinMode) {
        orbiters.append(Orbiter(entity: entity, model: model, kind: kind, spinMode: spinMode))
    }

    func tick(elapsed: TimeInterval, config: OrbitConfigState) {
        // Do the time × rate math in Double, then wrap to [0, 2π) and only
        // cast the small bounded result to Float. The previous Float-clock
        // path stuttered visibly because at magnitudes near the
        // `truncatingRemainder(1_000_000)` ceiling, Float ULP reaches
        // ~62 ms — multiple display frames see the same `t` and then jump
        // to the next representable value.
        let twoPiD: Double = 2 * .pi
        for orbiter in orbiters {
            guard let entity = orbiter.entity else { continue }
            let phase: Double = Double(orbiter.kind == .maxwell ? config.maxwellPhase : config.ratPhase)
            let angleD = (elapsed * Double(config.rate) + phase)
                .truncatingRemainder(dividingBy: twoPiD)
            let angle = Float(angleD)
            entity.position = [
                cos(angle) * config.radius,
                0,
                sin(angle) * config.radius
            ]
            switch orbiter.spinMode {
            case .freeSpin:
                let spinD = (elapsed * Double(config.maxwellSpinRate))
                    .truncatingRemainder(dividingBy: twoPiD)
                entity.orientation = simd_quatf(angle: Float(spinD), axis: [0, 1, 0])
            case .faceTangent:
                let tangent = SIMD3<Float>(-sin(angle), 0, cos(angle))
                entity.orientation = simd_quatf(from: [0, 0, 1], to: tangent)
            }
            // Live scale updates so the debug sliders affect the running scene.
            if let model = orbiter.model {
                let scale: Float = orbiter.kind == .maxwell ? config.maxwellScale : config.ratScale
                model.scale = [scale, scale, scale]
            }
        }
    }
}

/// Lightweight frame-delta logger for the Terminal 3D TimelineView. Emits
/// a single `⏱️ frame slip` line (DEBUG only) whenever SwiftUI hands us a
/// tick > 22 ms after the previous one (1.3× a 60 Hz frame), rate-limited
/// so a sustained drop doesn't flood the console. In release builds it's
/// a no-op — the `tick` body compiles away entirely.
@MainActor
final class FrameWatchdog {
    #if DEBUG
    private var lastTick: Date?
    private var lastLogged: Date = .distantPast
    private let slipThreshold: TimeInterval = 0.022
    private let logCooldown: TimeInterval = 0.5
    #endif

    func tick(now: Date) {
        #if DEBUG
        defer { lastTick = now }
        guard let last = lastTick else { return }
        let delta = now.timeIntervalSince(last)
        guard delta > slipThreshold else { return }
        guard now.timeIntervalSince(lastLogged) > logCooldown else { return }
        lastLogged = now
        let ms = String(format: "%.1f", delta * 1000)
        print("⏱️ frame slip: \(ms)ms since last tick (target ~16.7ms)")
        #endif
    }
}
#endif
