// Research: Terminal 3D (DEV). A live terminal floating in 3D space with
// Maxwell + a rat orbiting around it.
//
// Two camera modes:
//   • Orbit — turntable around the terminal (Blender/Sketchfab style).
//     Plain drag rotates around it, ⌥-drag re-centres, scroll zooms.
//     Right for "look at this thing"; terminal never leaves the frame.
//   • FPV — first-person flythrough (ratty / Unity scene-view style).
//     Plain drag slides the camera, ⌥-drag turns your head, scroll
//     dollies. Right for exploring a multi-terminal scene later.
//
// Both modes share yaw/pitch/pan state — only the camera math differs,
// so toggling never jumps the view.
//
// macOS-only.

#if os(macOS)
import AppKit
import SwiftUI

/// Which surface the terminal texture is mapped onto. The texture
/// pipeline is mesh-agnostic, so this is just a swap of the underlying
/// `MeshResource` — same live frames, different geometry.
public enum TerminalSurfaceMode: String, CaseIterable {
    /// Flat rectangle. The default.
    case flat
    /// Concave wrap (IMAX/cinemascope-style arc — edges curve toward viewer).
    case curved
    /// Möbius strip — terminal wraps around a half-twisted loop.
    case mobius
    /// Centre-bulge warp (à la ratty's vertex distortion). Pillow / CRT
    /// dome effect — the middle of the texture pokes toward the camera.
    case warp

    var displayName: String {
        switch self {
        case .flat: return String(localized: "Flat", bundle: .module)
        case .curved: return String(localized: "Curved", bundle: .module)
        case .mobius: return String(localized: "Möbius", bundle: .module)
        case .warp: return String(localized: "Warp", bundle: .module)
        }
    }

    var iconSystemName: String {
        switch self {
        case .flat: return "rectangle"
        case .curved: return "rectangle.portrait.arrowtriangle.2.inward"
        case .mobius: return "infinity"
        case .warp: return "circle.dotted"
        }
    }

    var helpText: String {
        switch self {
        case .flat: return String(localized: "Flat plane. Click to wrap onto a curved screen.", bundle: .module)
        case .curved: return String(localized: "Cinemascope curve. Click to wrap into a Möbius strip.", bundle: .module)
        case .mobius: return String(localized: "Möbius strip. Click for warp distortion.", bundle: .module)
        case .warp: return String(localized: "Centre-bulge warp. Click to return to flat.", bundle: .module)
        }
    }

    /// Cycle order for the toggle button.
    var next: TerminalSurfaceMode {
        switch self {
        case .flat: return .curved
        case .curved: return .mobius
        case .mobius: return .warp
        case .warp: return .flat
        }
    }
}

/// Camera interpretation. Shared input state (yaw/pitch/pan) maps to
/// fundamentally different camera placements per mode — see
/// `Terminal3DRealityScene.applyCameraZoom`.
public enum CameraMode: String, CaseIterable {
    case orbit
    /// Ride the rat: camera mounted on the rat orbiter, looking forward
    /// along its tangent. Drag still wiggles the head.
    case ratPOV
    /// Mounted on Maxwell's head, including his Y-axis spin so the view
    /// pirouettes with him.
    case catPOV

    var displayName: String {
        switch self {
        case .orbit: return String(localized: "Orbit", bundle: .module)
        case .ratPOV: return String(localized: "Rat POV", bundle: .module)
        case .catPOV: return String(localized: "Cat POV", bundle: .module)
        }
    }

    var iconSystemName: String {
        switch self {
        case .orbit: return "rotate.3d"
        case .ratPOV: return "hare"  // fallback; ratPOV prefers `iconEmoji`
        case .catPOV: return "cat"
        }
    }

    /// Optional emoji icon. Used when SF Symbols doesn't have an
    /// appropriate glyph — currently only the rat (SF ships `hare`, not
    /// rat). When non-nil, the toolbar renders this instead of `iconSystemName`.
    var iconEmoji: String? {
        switch self {
        case .ratPOV: return "🐀"
        default: return nil
        }
    }

    var helpText: String {
        switch self {
        case .orbit: return String(localized: "Orbit camera (turntable).", bundle: .module)
        case .ratPOV: return String(localized: "Ride along on the rat.", bundle: .module)
        case .catPOV: return String(localized: "See the world from Maxwell's POV (he pirouettes).", bundle: .module)
        }
    }

    var controlHint: String {
        switch self {
        case .orbit:
            return String(localized: "drag to orbit · ⌥-drag to pan · scroll to zoom", bundle: .module)
        case .ratPOV, .catPOV:
            return String(localized: "drag to look around · scroll to peek further", bundle: .module)
        }
    }
}

public struct Terminal3DSceneView: View {
    /// 1.0 = fully zoomed in (terminal looks flat and normal).
    /// 0.3 = fully zoomed out (orbit visible, terminal small in middle).
    @State private var zoom: Double = ScreenshotPresetLauncher.initialZoom ?? 1.0

    /// Default to orbit because it's the right UX for a single-subject
    /// scene (the terminal). FPV is a research toggle for the future
    /// "fleet of floating terminals" idea where flythrough makes sense.
    @State private var cameraMode: CameraMode = .orbit

    /// Which surface the terminal texture is mapped onto. Toggle
    /// cycles flat → curved → möbius → flat.
    /// Active-pane surface mode — kept for legacy code paths that
    /// expect a single value. Reads from `surfaceModes[activeSlot]`
    /// so the existing toggle button + display label still work,
    /// but the cycle action now updates only the active slot.
    private var surfaceMode: TerminalSurfaceMode {
        surfaceModes[activeSlot] ?? .flat
    }

    /// Whether the debug panel (minimap + sliders) is visible. Default
    /// off — the user reveals it via the settings button in the right
    /// panel once they've engaged with the 3D scene.
    @State private var showDebugPanel: Bool = false

    /// Whether the "About Catty" popover is showing. Surfaced from the
    /// info button at the bottom of the right rail.
    @State private var showAboutPopover: Bool = false

    /// Progressive disclosure: hide the camera-mode and surface-mode
    /// toggles in the default state. They appear once the user has
    /// engaged with the 3D scene (clicked the rat button to zoom out).
    /// Home reset returns to the default state.
    @State private var hasRatBeenPressed: Bool = false

    /// Source mode (local zsh vs SSH-into-remote). Defaults to local.
    /// The Compute section's main button uses `.local`; the per-profile
    /// 🐀 button passes `.ssh(...)` with the host's credentials.
    let mode: CattyTerminalSourceMode

    /// When this view is hosted inside a sheet (LAIC's usage), the
    /// package renders its own top-left ✕ close button so the user
    /// can dismiss without reaching for the system traffic-light.
    /// Standalone Catty.app owns navigation at the window level, so it
    /// passes `false` here — no package-side close affordance.
    let showsCloseButton: Bool

    /// When `true`, the scene's `.onDisappear` calls `.stop()` on every
    /// pane source so PTYs / SSH transports are torn down with the view.
    /// Default is `false` — keeps the existing standalone-Catty
    /// behaviour where the scene view tree is preserved across window
    /// hide/show and the shells keep running. Hosts that present the
    /// scene in a transient container (singleton SwiftUI `Window` that
    /// the user closes and re-opens, sheets, etc.) should pass `true`
    /// so a close means a real close.
    let stopsPanesOnDisappear: Bool

    /// Every active terminal pane, keyed by spatial slot. Centre is
    /// always populated (the initial session); cardinals get filled
    /// when the user spawns from the add-terminals mode. All five
    /// panes live coplanar at z = 0 in the same RealityKit scene.
    @State private var panes: [PaneSlot: TerminalLiveTextureSource]

    /// Working directory for any panes the user spawns from the
    /// centre. Captured at init so spawned local panes inherit the
    /// same root the user started in.
    private let initialWorkingDirectory: URL?

    /// When true the right-rail toggle has been flipped on and four
    /// directional spawn arrows are visible around the centre pane.
    @State private var addTerminalsMode: Bool = false

    /// Hidden "compose for icon" mode: hides every UI chrome element
    /// except the compose toggle, freezes Maxwell + rat orbit, and
    /// freezes the cursor cats. Lets the user pull the camera into a
    /// clean frame and take a window screenshot (⌘⇧4 → spacebar →
    /// click the Catty window) to use as the 1024×1024 icon source.
    @State private var iconComposeMode: Bool = false

    /// AppKit local-event monitor token for scroll-wheel zoom. Owned
    /// by `body`'s onAppear / onDisappear lifecycle. Installed at the
    /// app level (rather than as an in-tree NSView) so scroll always
    /// reaches us — even when a SwiftTerm pane has keyboard focus
    /// and would otherwise capture scroll events for scrollback.
    @State private var scrollMonitor: Any?

    /// Which pane the user is currently interacting with. Clicked
    /// via `paneFocusOverlay`; surfaces a blue selection outline
    /// and drives per-pane controls like surface mode. Defaults
    /// to centre on cold start.
    @State private var activeSlot: PaneSlot = .origin

    /// Per-pane surface mode. Cycle button applies to `activeSlot`
    /// only — different panes can sit on different shapes (flat
    /// next to curved next to mobius). Centre defaults to flat;
    /// new spawns inherit flat too.
    @State private var surfaceModes: [PaneSlot: TerminalSurfaceMode] =
        ScreenshotPresetLauncher.initialSurfaceModes ?? [.origin: .flat]

    /// Convenience: the centre pane's source. Always non-nil because
    /// centre is set in init and never removed.
    private var centreSource: TerminalLiveTextureSource {
        // swiftlint:disable:next force_unwrapping
        panes[.origin]!
    }

    /// Dismiss action — pulled from the surrounding sheet so the close
    /// button in the top-left actually shuts the scene down.
    @Environment(\.dismiss) private var dismiss

    public init(
        mode: CattyTerminalSourceMode = .local,
        workingDirectory: URL? = nil,
        showsCloseButton: Bool = true,
        stopsPanesOnDisappear: Bool = false
    ) {
        self.mode = mode
        self.showsCloseButton = showsCloseButton
        self.stopsPanesOnDisappear = stopsPanesOnDisappear
        self.initialWorkingDirectory = workingDirectory

        // Cold-start: rehydrate the user's last multi-pane layout if
        // there is one. The centre slot's source is built from the
        // caller's init args (mode / workingDirectory) — those win
        // over whatever was persisted so the launcher's working-dir
        // picker doesn't get silently overridden by stale state.
        // Cardinals come from the persisted layout (.local only).
        var initial: [PaneSlot: TerminalLiveTextureSource] = [
            .origin: TerminalLiveTextureSource(mode: mode, workingDirectory: workingDirectory)
        ]
        if case .local = mode, let layout = CattyLayoutStore.load() {
            for persisted in layout.panes {
                guard let slot = PaneSlot(rawValue: persisted.slot),
                      slot != .origin else { continue }
                let url = persisted.workingDirectory.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                } ?? workingDirectory
                initial[slot] = TerminalLiveTextureSource(
                    mode: .local,
                    workingDirectory: url
                )
            }
        }
        _panes = State(initialValue: initial)
    }

    /// Spawn a fresh local pane in `slot` if it's empty. New panes
    /// inherit the centre's working directory; SSH-mode spawning
    /// from the rail is deferred — the user gets a local shell.
    /// Saves the updated layout to disk so the user picks up where
    /// they left off on next launch.
    private func spawnPane(at slot: PaneSlot) {
        guard slot != .origin, panes[slot] == nil else { return }
        let source = TerminalLiveTextureSource(
            mode: .local,
            workingDirectory: initialWorkingDirectory
        )
        source.start()
        withAnimation(.easeInOut(duration: 0.3)) {
            panes[slot] = source
            surfaceModes[slot] = .flat
            // Auto-focus the newly-spawned pane so the user can
            // immediately style it / type in it.
            activeSlot = slot
        }
        persistLayout()
    }

    /// Tear down a spawned pane. Centre is never removable (it's
    /// the always-present session). Stops the underlying source so
    /// the shell process exits cleanly, drops the surface-mode
    /// entry, and persists the layout. If the deleted slot was the
    /// active selection, focus falls back to centre.
    private func removePane(at slot: PaneSlot) {
        guard slot != .origin, let source = panes[slot] else { return }
        source.stop()
        withAnimation(.easeInOut(duration: 0.25)) {
            panes[slot] = nil
            surfaceModes[slot] = nil
            if activeSlot == slot {
                activeSlot = .origin
            }
        }
        persistLayout()
    }

    /// Snapshot the current panes dict into UserDefaults. Centre is
    /// always recorded with the working dir the caller passed at
    /// init; cardinals are local-mode panes rooted at the same dir.
    /// SSH panes are intentionally excluded — re-establishing a
    /// remote shell needs a credential prompt, not a silent restore.
    private func persistLayout() {
        var snapshot: [PaneSlot: URL?] = [:]
        for slot in panes.keys {
            snapshot[slot] = initialWorkingDirectory
        }
        CattyLayoutStore.save(panes: snapshot)
    }

    /// Deterministic ordering of panes for the offscreen embeds.
    /// Sort by row then column so SwiftUI's ForEach has a stable
    /// list — without this, re-renders could tear the embeds.
    private var activePaneOrder: [PaneSlot] {
        panes.keys.sorted { a, b in
            (a.row, a.column) < (b.row, b.column)
        }
    }

    /// Set of grid cells the user can spawn into right now — every
    /// empty cell that's a cardinal neighbour of at least one filled
    /// cell. Grows as the user spawns new panes.
    private var spawnCoords: [PaneSlot] {
        var seen = Set<PaneSlot>()
        var result: [PaneSlot] = []
        for coord in panes.keys {
            for neighbour in coord.neighbours() where panes[neighbour] == nil {
                if seen.insert(neighbour).inserted {
                    result.append(neighbour)
                }
            }
        }
        return result
    }

    /// Shared tunable orbit params. Driven by OrbitDebugSliders,
    /// consumed by Terminal3DRealityScene + OrbitDebugMinimap.
    @State private var orbitConfig = OrbitConfigState()

    /// Camera pan offset in world space. Plain drag updates this so the
    /// user can shift the view laterally without rotating. Reset by 🏠.
    @State private var panOffset: SIMD3<Float> = .zero
    @State private var panStart: SIMD3<Float> = .zero

    /// User-driven head-turn (⌥-drag). Yaw is unlimited; pitch clamped
    /// just shy of straight up / straight down.
    @State private var userYaw: Double = 0     // Y axis, radians
    @State private var userPitch: Double = 0   // X axis, radians

    @State private var dragStartYaw: Double = 0
    @State private var dragStartPitch: Double = 0

    // Comical zoom range: at the lower end the camera pulls way
    // back so the entire pane cluster collapses to a postage-stamp
    // and the user can survey the orbit + star background dominating
    // the frame. The applyCameraZoom math interpolates camera radius
    // smoothly across the whole range — see Terminal3DRealityScene.
    private let zoomMin: Double = 0.01
    private let zoomMax: Double = 1.0
    private let zoomStep: Double = 0.1
    /// How far the rat button moves the camera per click — 2 zoom steps.
    private let ratZoomOutDelta: Double = 0.2

    /// Extra top inset for the right-side rail so it clears the host
    /// window's native control band. When Catty is embedded in a
    /// `Window(id:)` scene (e.g. Local AI Chat) the macOS traffic-light /
    /// full-screen control and the window's rounded-corner mask occupy
    /// the top ~28pt; without this the rail collides with — and is
    /// clipped by — that chrome. Standalone Catty.app is unaffected
    /// visually (its rail simply starts a touch lower).
    private let windowChromeTopInset: CGFloat = 28

    public var body: some View {
        ZStack {
            spaceBackground
                // Plain drag — orbit (in orbit mode) or pan (in FPV mode).
                .gesture(backdropPrimaryGesture)
                // ⌥-drag — pan (in orbit mode) or look around (in FPV mode).
                .gesture(backdropSecondaryGesture)
                // Single click = focus the terminal for typing.
                .onTapGesture {
                    centreSource.focusTerminal()
                }
            // Invisible NSView that catches scroll-wheel events for zoom.
            // Sits in the same hit-area as the backdrop but uses
            // hitTest-by-currentEvent so mouse drags still fall through
            // to the SwiftUI gestures above.
            // ScrollWheelCatcher used to live here as an in-tree NSView
            // intercepting scrolls in its hit-area. That couldn't see
            // scrolls when a SwiftTerm pane was focused because the
            // pane's view consumed the wheel events. Now we install
            // an app-level NSEvent monitor (see onAppear below) so
            // regular scroll always zooms; ⌥-scroll falls through to
            // SwiftTerm for terminal scrollback.
            // Per-pane click-to-focus targets, only when multi-pane.
            // Each invisible zone maps the screen quadrant containing
            // that pane to a focus-this-pane action. Sits BENEATH the
            // chrome (close button / status banner / right rail /
            // spawn arrows) so those views consume clicks first; only
            // taps that miss the chrome fall through to focus a pane.
            if panes.count > 1 && !iconComposeMode {
                paneFocusOverlay
            }
            // Compose mode tucks every other chrome layer away so
            // the user can take a clean window screenshot for the
            // app icon. The compose toggle itself stays visible
            // (top-right, dimmed) so they can flip back out.
            if !iconComposeMode {
                // Top-left close button — dismisses the sheet. Hidden when
                // the host opts out (standalone Catty.app, where the window
                // owns navigation).
                if showsCloseButton {
                    closeButton
                }
                // SSH connection status — shown in the centre when waiting
                // for handshake / on failure. Hidden once a connection is
                // live (the live texture takes over).
                sshStatusBanner
                // Right-side controls: bare rat button at home view, full
                // panel once any user adjustment has been made. The panel
                // grows progressively (settings/orbit/flat) after rat press.
                controls
                if hasUserAdjustments {
                    controlHint
                }
                if hasRatBeenPressed && showDebugPanel {
                    debugMinimap
                }
            }
            // Compose-mode toggle. Always visible but dimmed when in
            // compose mode so the user has a way back out.
            composeToggle

            // Spawn arrows. Rendered as a SwiftUI overlay at fixed
            // screen offsets from the centre — the cardinal slots in
            // world space project onto roughly these screen positions
            // at the default camera angle, so the affordance reads as
            // "above / below / left / right of the centre pane". As
            // the user orbits the camera, the arrows stay
            // screen-aligned; we may refine this to project the world
            // positions if it feels off.
            if addTerminalsMode && !iconComposeMode {
                spawnArrowsOverlay
                    .transition(.opacity)
            }

            // Off-screen mount of every active pane's terminal NSView,
            // so SwiftTerm lives in the main NSWindow (and can become
            // first responder for keyboard input) while staying
            // visually invisible — the visible "terminal" is the
            // textured plane in the RealityKit scene.
            ForEach(activePaneOrder, id: \.self) { slot in
                if let source = panes[slot] {
                    TerminalSourceEmbed(source: source)
                        .frame(
                            width: source.captureSize.width,
                            height: source.captureSize.height
                        )
                        .offset(x: -20_000, y: -20_000)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 560)
        // Start shell / SSH only once, after the view is actually on
        // screen. SwiftUI re-instantiates view structs on every redraw,
        // so doing this in init() spawns N parallel processes /
        // connections — exactly what caused the SSH duplicate-connect
        // bug + the cat/rat lag.
        .onAppear {
            // Start every active pane, not just the centre. Restored
            // panes from `CattyLayoutStore` were getting created in
            // init but never woken up — relaunch would show their
            // textures still black because the underlying shell had
            // not been spawned.
            for source in panes.values {
                source.start()
            }
            // Give the SwiftUI sheet one runloop tick to mount the embed
            // and attach the terminal NSView to the window before asking
            // it to become first responder. Without the delay, the view
            // has no `.window` yet and focusTerminal silently no-ops.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                centreSource.focusTerminal()
            }
            installScrollMonitor()
        }
        .onDisappear {
            removeScrollMonitor()
            // Host-opt-in teardown: when the embedding window/sheet
            // closes, tear down every pane's PTY / SSH transport so a
            // re-open starts a real new session. Standalone Catty.app
            // leaves this false and lets shells outlive the view tree.
            if stopsPanesOnDisappear {
                for source in panes.values {
                    source.stop()
                }
            }
        }
    }

    /// Install an app-level scroll-wheel monitor so zoom works
    /// regardless of which view has keyboard focus.
    /// • Plain scroll  → consumed, drives camera zoom (default), OR
    ///   passed through to SwiftTerm for terminal scrollback when the
    ///   host app sets `compute.catty.trackpadScrollZoom` to `false`.
    /// • ⌥-scroll      → always passed through; SwiftTerm sees it and
    ///   uses it for terminal scrollback.
    ///
    /// The flag is read live (per event) from `UserDefaults.standard`
    /// so the host app's toggle takes effect without reinstalling the
    /// monitor. It defaults to `true` (scroll zooms) when unset, so
    /// existing behaviour is unchanged unless the host opts out.
    @MainActor
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // ⌥-scroll: terminal scrollback — let it bubble to SwiftTerm.
            if event.modifierFlags.contains(.option) {
                return event
            }
            // Host app opted plain scroll out of zoom: let it through to
            // SwiftTerm (scrollback). Zoom stays available via the
            // on-screen zoom bar.
            let defaults = UserDefaults.standard
            let scrollZoomKey = "compute.catty.trackpadScrollZoom"
            let scrollZooms = defaults.object(forKey: scrollZoomKey) == nil
                ? true
                : defaults.bool(forKey: scrollZoomKey)
            if !scrollZooms {
                return event
            }
            // Plain scroll: zoom. Same per-tick math as the old in-tree
            // ScrollWheelCatcher (small multiplicative factor, clamped
            // so a fast flick can't compound into a big jump).
            let raw = Double(event.scrollingDeltaY) * 0.0012
            let factor = max(0.85, min(1.18, 1 + raw))
            DispatchQueue.main.async {
                zoom = max(zoomMin, min(zoomMax, zoom * factor))
                if zoom < 0.85 {
                    hasRatBeenPressed = true
                }
            }
            return nil
        }
    }

    @MainActor
    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    /// Top-right compose-mode toggle. Always-on viewfinder icon
    /// that toggles `iconComposeMode`. In compose mode every other
    /// chrome layer hides, the orbit freezes, and the user can take
    /// a clean window screenshot for the app icon source.
    private var composeToggle: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        iconComposeMode.toggle()
                    }
                } label: {
                    Image(systemName: iconComposeMode
                          ? "viewfinder.circle.fill"
                          : "viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.black.opacity(iconComposeMode ? 0.25 : 0.55), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                        .opacity(iconComposeMode ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .help(iconComposeMode
                      ? String(localized: "Exit compose mode (⌘⇧I)", bundle: .module)
                      : String(localized: "Compose for icon — hides UI + freezes the orbit", bundle: .module))
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .padding(.trailing, 16)
                .padding(.top, 10)
            }
            Spacer()
        }
    }

    /// Click-targets over each pane's projected screen rect plus a
    /// blue selection outline tracking the *actual* plane size at
    /// the current camera distance. Tapping a zone focuses that
    /// pane's SwiftTerm NSView (so keystrokes route there) AND sets
    /// `activeSlot` so the surface-mode toggle applies to it.
    /// Drag/scroll fall through to the orbit + zoom gestures on the
    /// space backdrop underneath.
    private var paneFocusOverlay: some View {
        GeometryReader { geo in
            ForEach(activePaneOrder, id: \.self) { slot in
                let frame = projectedPaneFrame(for: slot, in: geo.size)
                // Selection glow now lives inside the RealityKit
                // scene (see Terminal3DRealityScene's per-pane glow
                // plane) so it follows the pane as the user orbits.
                // This overlay only carries the invisible click
                // target.
                Color.clear.contentShape(Rectangle())
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .onTapGesture {
                    panes[slot]?.focusTerminal()
                    activeSlot = slot
                }
            }
        }
        .allowsHitTesting(true)
    }

    /// Project the slot's world-space pane (1.6 × 1.05, centred on
    /// `slot.worldPosition`, z = 0) into screen coordinates given
    /// the current zoom-derived camera distance. Assumes the
    /// default camera angle (looking at origin from +Z) — yaw/pitch
    /// would require a full view-matrix transform we can add later
    /// if the user notices drift while orbiting.
    private func projectedPaneFrame(for slot: PaneSlot, in container: CGSize) -> CGRect {
        // Mirror the radius math from Terminal3DRealityScene.applyCameraZoom.
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
        // Vertical FOV ~60°; pixels per world-unit derived from
        // the screen-height-at-distance projection.
        let tanHalfFov: Float = tan(.pi / 6)            // 30°
        let pxPerWorld = Float(container.height) / (2 * radius * tanHalfFov)
        let planeW: Float = 1.6
        let planeH: Float = 1.05
        let world = slot.worldPosition
        let cx = CGFloat(Float(container.width) / 2 + world.x * pxPerWorld)
        // y flipped because screen-y grows downward.
        let cy = CGFloat(Float(container.height) / 2 - world.y * pxPerWorld)
        let w = CGFloat(planeW * pxPerWorld)
        let h = CGFloat(planeH * pxPerWorld)
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// SwiftUI overlay shown while `addTerminalsMode` is on.
    /// Empty cardinals get a `+ arrow` affordance to spawn a new
    /// pane in that direction; filled cardinals get an `✕` close
    /// chip parked on the pane itself for tear-down. Toggling the
    /// rail button off hides both.
    /// SwiftUI overlay shown while `addTerminalsMode` is on.
    /// • Empty grid cells adjacent to any filled pane get a small
    ///   translucent purple square at their projected screen
    ///   position; click to spawn into that cell. The new pane's
    ///   own empty neighbours then expose more spawn squares, so
    ///   the grid grows organically.
    /// • Filled non-origin panes get an ✕ close chip — click to
    ///   tear down (origin is permanent).
    private var spawnArrowsOverlay: some View {
        GeometryReader { geo in
            ForEach(spawnCoords, id: \.self) { coord in
                let frame = projectedPaneFrame(for: coord, in: geo.size)
                spawnSquare(for: coord)
                    .frame(width: frame.width * 0.85, height: frame.height * 0.85)
                    .position(x: frame.midX, y: frame.midY)
                    .transition(.scale.combined(with: .opacity))
            }
            ForEach(activePaneOrder, id: \.self) { coord in
                if coord != .origin {
                    let frame = projectedPaneFrame(for: coord, in: geo.size)
                    closeChip(for: coord)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .allowsHitTesting(true)
    }

    /// Translucent purple square the user taps to spawn a new pane
    /// at `coord`. Sized to roughly match the projected pane
    /// footprint so it reads as "a terminal would go here".
    private func spawnSquare(for coord: PaneSlot) -> some View {
        Button {
            spawnPane(at: coord)
        } label: {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.purple.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.purple.opacity(0.55), lineWidth: 2)
                )
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                )
        }
        .buttonStyle(.plain)
        .help(String(localized: "Spawn a new local terminal here", bundle: .module))
    }

    private func closeChip(for slot: PaneSlot) -> some View {
        Button {
            removePane(at: slot)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 44, height: 44)
                .background(.red.opacity(0.7), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(String(localized: "Remove this terminal", bundle: .module))
    }

    // offsetForArrow is no longer needed — spawn squares are
    // positioned by projecting the target coord's worldPosition
    // through the camera (see projectedPaneFrame).

    /// Plain drag. Always rotates — in orbit mode that's a turntable
    /// spin around the terminal; in FPV mode it's a fixed-position
    /// head-turn (camera stays put, view direction changes). Sign
    /// flipped per mode so each matches its platform convention.
    private var backdropPrimaryGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                switch cameraMode {
                case .orbit:
                    // Drag right → object rotates right toward you (Sketchfab).
                    applyRotateDrag(translation: value.translation, sign: +1)
                case .ratPOV, .catPOV:
                    // Drag right → head turns right (FPS convention).
                    applyRotateDrag(translation: value.translation, sign: -1)
                }
            }
            .onEnded { _ in
                dragStartYaw = userYaw
                dragStartPitch = userPitch
                panStart = panOffset
            }
    }

    /// ⌥-drag. Always pans — in orbit mode the focal point shifts; in
    /// FPV mode the camera body slides laterally without rotating.
    private var backdropSecondaryGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .modifiers(.option)
            .onChanged { value in
                applyPanDrag(translation: value.translation)
            }
            .onEnded { _ in
                panStart = panOffset
            }
    }

    /// Update yaw/pitch from a drag translation. `sign` flips the yaw
    /// direction per mode so each one matches the platform convention
    /// (orbit: drag-right rotates object right; FPV: drag-right turns
    /// the camera right, which makes the scene appear to slide left).
    private func applyRotateDrag(translation: CGSize, sign: Double) {
        let sensitivity = 0.005
        userYaw = dragStartYaw + sign * Double(translation.width) * sensitivity
        let pitchLimitRad: Double = .pi / 2 - 0.05
        userPitch = max(
            -pitchLimitRad,
            min(pitchLimitRad, dragStartPitch - Double(translation.height) * sensitivity)
        )
    }

    /// Update panOffset from a drag translation. The right vector is
    /// derived from current yaw so panning always tracks "what's on
    /// screen", regardless of which way the camera is facing.
    private func applyPanDrag(translation: CGSize) {
        let yaw = Float(userYaw)
        let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let up = SIMD3<Float>(0, 1, 0)
        let kx = Float(translation.width) * -0.003
        let ky = Float(translation.height) * 0.003
        panOffset = panStart + right * kx + up * ky
    }

    /// Top-left top-down map + live-tuning sliders.
    private var debugMinimap: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    OrbitDebugMinimap(
                        config: orbitConfig,
                        zoom: zoom,
                        lookYaw: Float(userYaw)
                    )
                    OrbitDebugSliders(config: orbitConfig)
                }
                .padding(16)
                Spacer()
            }
            Spacer()
        }
    }

    // MARK: - Background: RealityKit scene with Maxwell + rat orbit chase

    private var spaceBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.10),
                    Color(red: 0.08, green: 0.02, blue: 0.18),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // The starfield is random + animated; hide it in
            // deterministic mode so screenshot parity isn't defeated
            // by twinkling stars.
            .overlay {
                if !DeterministicRender.isOn {
                    StarfieldView()
                }
            }
            Terminal3DRealityScene(
                panes: panes,
                config: orbitConfig,
                zoom: zoom,
                lookYaw: Float(userYaw),
                lookPitch: Float(userPitch),
                panOffset: panOffset,
                cameraMode: cameraMode,
                surfaceModes: surfaceModes,
                activeSlot: (iconComposeMode || DeterministicRender.isOn) ? nil : activeSlot,
                freezeOrbiters: iconComposeMode || DeterministicRender.isOn
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Top-right controls (rat + conditional home)

    /// Right-side control area. Two modes:
    /// • Default (no adjustments): a single bare rat button — no panel,
    ///   no debug, just the prompt to "engage".
    /// • Engaged: a full panel where the rat slot has transformed into
    ///   the home button. After the rat has been pressed at least once,
    ///   settings/orbit/flat toggles appear below.
    private var controls: some View {
        VStack {
            HStack {
                Spacer()
                if hasUserAdjustments {
                    engagedPanel
                } else {
                    ratFloatingButton
                }
            }
            // Push the rail below the host window's native control band
            // (traffic lights / full-screen pill) and rounded-corner mask
            // so it isn't clipped when Catty is embedded in a Window scene.
            .padding(.top, windowChromeTopInset)
            Spacer()
        }
    }

    /// Close button — top-left corner, always visible. Dismisses the
    /// sheet so the SSH transport / local zsh process can be torn down.
    private var closeButton: some View {
        VStack {
            HStack {
                Button(action: dismissScene) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
                .help(String(localized: "Close Catty 3D", bundle: .module))
                .padding(16)
                Spacer()
            }
            Spacer()
        }
    }

    /// Status banner for SSH mode. Shown until the connection is live
    /// (so the user knows it's connecting / why nothing's rendering),
    /// and re-shown on failure with the error text.
    @ViewBuilder
    private var sshStatusBanner: some View {
        if case .ssh = mode {
            let state = centreSource.connectionState
            let message = sshStatusMessage(state)
            if !message.text.isEmpty {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: message.icon)
                            .foregroundStyle(message.tint)
                        Text(message.text)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.7), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                    .padding(.bottom, 60)
                    Spacer().frame(height: 0)
                }
            }
        }
    }

    private func sshStatusMessage(
        _ state: CattyConnectionState
    ) -> (text: String, icon: String, tint: Color) {
        switch state {
        case .idle:
            return ("Waiting…", "ellipsis", .secondary)
        case .connecting:
            return ("Connecting…", "network", .orange)
        case .authenticating:
            return ("Authenticating…", "lock", .orange)
        case .connected:
            // Don't draw anything once we're live — the terminal is
            // already on screen.
            return ("", "", .clear)
        case .disconnected(let reason):
            return (reason.map { "Disconnected — \($0)" } ?? "Disconnected", "xmark.octagon", .red)
        }
    }

    private func dismissScene() {
        // Tear down the SSH transport / capture timer before dropping
        // the sheet so we don't leak the Citadel session.
        centreSource.stop()
        dismiss()
    }

    /// The default "do something with this scene" affordance — a single
    /// rat button floating in the top-right. No surrounding panel,
    /// nothing else competing for attention.
    private var ratFloatingButton: some View {
        Button(action: sendMaxwellAfterRat) {
            Text("🐀")
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .help(String(localized: "Send Maxwell after the rat — zoom out to watch the chase", bundle: .module))
        .padding(16)
    }

    /// Panel shown once the user has adjusted the view in any way.
    /// The rat slot at the top has become the home button; everything
    /// below it is only present after the rat has actually been
    /// pressed (so just panning doesn't pollute the panel).
    private var engagedPanel: some View {
        VStack(spacing: 8) {
            // Rat transforms into Home — same slot, different meaning.
            iconButton(systemName: "house", action: resetView)
                .help(String(localized: "Return to default view (100% zoom, centred)", bundle: .module))
            Text(verbatim: "\(Int(zoom * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))

            // Compact zoom slider in the rail. Always reliable — when
            // a SwiftTerm pane has keyboard focus it consumes scroll
            // wheel events for its own scrollback, so the rail slider
            // is the user's escape hatch back to camera zoom.
            Slider(value: $zoom, in: zoomMin...zoomMax)
                .controlSize(.mini)
                .frame(width: 64)
                .tint(.white.opacity(0.55))
                .help(String(localized: "Drag to zoom (works even while a terminal is focused)", bundle: .module))

            // Settings / Orbit / Flat — progressive disclosure. They
            // appear only after the rat has been pressed, so the
            // "I just want home back" use case stays uncluttered.
            if hasRatBeenPressed {
                Divider().frame(width: 24).background(.white.opacity(0.15))
                iconButton(
                    systemName: showDebugPanel
                        ? "slider.horizontal.3"
                        : "slider.horizontal.3",
                    action: toggleDebugPanel
                )
                .help(showDebugPanel
                      ? String(localized: "Hide debug panel", bundle: .module)
                      : String(localized: "Show debug panel", bundle: .module))

                Divider().frame(width: 24).background(.white.opacity(0.15))
                Menu {
                    ForEach(CameraMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                cameraMode = mode
                            }
                        } label: {
                            if let emoji = mode.iconEmoji {
                                Label { Text(mode.displayName) } icon: { Text(emoji) }
                            } else {
                                Label(mode.displayName, systemImage: mode.iconSystemName)
                            }
                        }
                    }
                } label: {
                    Group {
                        if let emoji = cameraMode.iconEmoji {
                            // Rat POV uses the 🐀 emoji to match the
                            // first-press rat button, since SF Symbols
                            // ships a hare (rabbit) but no rat.
                            Text(emoji)
                                .font(.system(size: 16))
                        } else {
                            Image(systemName: cameraMode.iconSystemName)
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                } primaryAction: {
                    cycleCameraMode()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(localized: "\(cameraMode.helpText)  ·  Long-press for picker", bundle: .module))
                Text(cameraMode.displayName)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))

                Divider().frame(width: 24).background(.white.opacity(0.15))
                iconButton(systemName: surfaceMode.iconSystemName, action: cycleSurfaceMode)
                    .help(surfaceMode.helpText)
                Text(surfaceMode.displayName)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }

            // Add-terminals toggle. Lives outside the `hasRatBeenPressed`
            // gate so the user can split into a multi-pane layout
            // from a cold-start. When on, four directional arrows
            // render around the centre pane (see `spawnArrowsOverlay`)
            // and clicking one fills that cardinal slot.
            Divider().frame(width: 24).background(.white.opacity(0.15))
            iconButton(
                systemName: addTerminalsMode
                    ? "rectangle.split.2x2.fill"
                    : "rectangle.split.2x2",
                action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addTerminalsMode.toggle()
                    }
                }
            )
            .help(addTerminalsMode
                  ? "Hide spawn arrows"
                  : "Add terminals around this one")

            // Always-present at the foot of the rail. Tapping opens a
            // small popover with a Ratty shout-out + GitHub link.
            // Lives outside the `hasRatBeenPressed` gate so newcomers
            // can find the credit even before they've engaged with
            // the orbit controls.
            Divider().frame(width: 24).background(.white.opacity(0.15))
            iconButton(systemName: "info.circle", action: { showAboutPopover.toggle() })
                .help("About Catty — credits + inspiration")
                .popover(isPresented: $showAboutPopover, arrowEdge: .trailing) {
                    aboutPopover
                }
        }
        .padding(10)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .padding(16)
    }

    /// Content of the right-rail "About" popover. Short credit to
    /// Ratty (the inspiration + the rat USDZ) plus the GitHub link.
    /// Asset attribution is hosted in ATTRIBUTION.md alongside the
    /// package — this is just the live shout-out.
    private var aboutPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("🐀")
                    .font(.title2)
                Text("Inspired by Ratty", bundle: .module)
                    .font(.headline)
            }

            Text("The terminal-in-a-3D-scene idea behind Catty 3D comes from Ratty by Orhun Parmaksız — a GPU-rendered terminal with inline 3D graphics. Their rat chases pixels in a terminal; our cat watches it happen from RealityKit.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: URL(string: "https://github.com/orhun/ratty")!) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                    Text(verbatim: "github.com/orhun/ratty")
                        .font(.callout)
                }
            }

            Divider()

            Text("The rat 3D model in this scene also ships courtesy of Ratty (MIT). Maxwell the cat comes from bean (alwayshasbean) on Sketchfab under CC-BY 4.0.", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320)
    }

    /// Discoverable hint for the new interaction model. Fades out as
    /// soon as the user has actually used any of them.
    private var controlHint: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 11))
                    Text(cameraMode.controlHint)
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.4), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
                .padding(16)
                .opacity(hasUserAdjustments ? 0 : 1)
                .animation(.easeOut(duration: 0.3), value: hasUserAdjustments)
                Spacer()
            }
        }
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var hasUserAdjustments: Bool {
        abs(userYaw) > 0.01
            || abs(userPitch) > 0.01
            || zoom < zoomMax
            || panOffset != .zero
    }

    private func sendMaxwellAfterRat() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            zoom = max(zoomMin, zoom - ratZoomOutDelta)
            hasRatBeenPressed = true
        }
    }

    /// Click cycles Rat → Cat → Orbit → Rat. Long-press on the menu chip
    /// opens the full picker (handled by `Menu.primaryAction`).
    private func cycleCameraMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            let next: CameraMode
            switch cameraMode {
            case .ratPOV: next = .catPOV
            case .catPOV: next = .orbit
            case .orbit:  next = .ratPOV
            }
            // Entering a POV resets the head-turn state so the view starts
            // facing forward, not wherever the last orbit drag left things.
            if next == .ratPOV || next == .catPOV {
                userYaw = 0
                userPitch = 0
                dragStartYaw = 0
                dragStartPitch = 0
            }
            cameraMode = next
        }
    }

    private func cycleSurfaceMode() {
        let current = surfaceModes[activeSlot] ?? .flat
        withAnimation(.easeInOut(duration: 0.25)) {
            surfaceModes[activeSlot] = current.next
        }
    }

    private func toggleDebugPanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showDebugPanel.toggle()
        }
    }

    private func resetView() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            zoom = zoomMax
            userYaw = 0
            userPitch = 0
            dragStartYaw = 0
            dragStartPitch = 0
            panOffset = .zero
            panStart = .zero
            hasRatBeenPressed = false
        }
    }
}

// MARK: - Scroll-wheel catcher

/// NSView that catches scroll-wheel events but passes mouse clicks
/// through to whatever's behind it in the SwiftUI ZStack.
///
/// The hitTest trick: returns `self` only when AppKit is currently
/// routing a scroll-wheel event (so scroll lands here); returns `nil`
/// for everything else (mouseDown/up/dragged), letting SwiftUI
/// gestures on lower layers fire normally.
private struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = Catcher()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Catcher)?.onScroll = onScroll
    }

    final class Catcher: NSView {
        var onScroll: ((CGFloat) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            onScroll?(event.scrollingDeltaY)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            if NSApp.currentEvent?.type == .scrollWheel {
                return self
            }
            return nil
        }
    }
}

// MARK: - Starfield

/// Cheap procedural starfield. Static dots + occasional shooting stars
/// that streak diagonally across the sky and fade out.
private struct StarfieldView: View {
    private let stars: [Star] = (0..<160).map { _ in
        Star(
            x: .random(in: 0...1),
            y: .random(in: 0...1),
            size: .random(in: 0.6...2.2),
            opacity: .random(in: 0.25...0.9)
        )
    }

    /// Non-observable mutable store so animations + spawn timing don't
    /// invalidate the SwiftUI body each tick. TimelineView's Canvas
    /// callback is the only thing reading/writing this.
    @State private var shootingStars = ShootingStarStore()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                Canvas { ctx, size in
                    drawStatic(into: ctx, size: size)
                    drawShootingStars(into: ctx, size: size, now: context.date)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .allowsHitTesting(false)
        }
    }

    private func drawStatic(into ctx: GraphicsContext, size: CGSize) {
        for star in stars {
            let rect = CGRect(
                x: star.x * size.width,
                y: star.y * size.height,
                width: star.size,
                height: star.size
            )
            ctx.fill(
                Path(ellipseIn: rect),
                with: .color(.white.opacity(star.opacity))
            )
        }
    }

    private func drawShootingStars(into ctx: GraphicsContext, size: CGSize, now: Date) {
        // Spawn on demand. Base cadence is short-ish (0.8–4s) so stars
        // streak across reasonably often, and ~30% of the time we schedule
        // a "burst" follow-up (0.15–0.6s) so clusters of 2–3 stars come
        // through together. The mix of fast clusters and longer waits is
        // what makes it feel like a real meteor shower instead of a
        // metronome.
        if now.timeIntervalSince(shootingStars.nextSpawnAt) >= 0 {
            // Pick a random launch direction across a wide arc, not just
            // down-right. Stars can streak in any direction across the
            // viewport — angle in [-π, π), speed 280–460 px/s.
            let angle = Double.random(in: -.pi ... .pi)
            let speed = CGFloat.random(in: 280...460)
            shootingStars.list.append(ShootingStar(
                start: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height)
                ),
                velocity: CGVector(
                    dx: speed * CGFloat(cos(angle)),
                    dy: speed * CGFloat(sin(angle))
                ),
                spawnedAt: now,
                lifetime: TimeInterval.random(in: 0.7...1.4)
            ))
            // Sparse pacing — a star "every now and then" rather than a
            // steady stream. Occasional close pair (~10%) keeps the rhythm
            // from feeling metronomic.
            let nextGap: TimeInterval = Double.random(in: 0...1) < 0.1
                ? .random(in: 0.4...1.0)
                : .random(in: 5.0...12.0)
            shootingStars.nextSpawnAt = now.addingTimeInterval(nextGap)
        }
        // Cull dead.
        shootingStars.list.removeAll { now.timeIntervalSince($0.spawnedAt) > $0.lifetime }
        // Draw — head dot + fading trail line.
        for star in shootingStars.list {
            let elapsed = now.timeIntervalSince(star.spawnedAt)
            let progress = elapsed / star.lifetime
            let pos = CGPoint(
                x: star.start.x + star.velocity.dx * elapsed,
                y: star.start.y + star.velocity.dy * elapsed
            )
            // Trail = a short segment opposite to velocity, ~40px long.
            let speed = sqrt(star.velocity.dx * star.velocity.dx + star.velocity.dy * star.velocity.dy)
            let unit = CGVector(dx: star.velocity.dx / speed, dy: star.velocity.dy / speed)
            let trailEnd = CGPoint(
                x: pos.x - unit.dx * 42,
                y: pos.y - unit.dy * 42
            )
            let alpha = max(0, 1 - progress)
            var path = Path()
            path.move(to: pos)
            path.addLine(to: trailEnd)
            ctx.stroke(path, with: .color(.white.opacity(alpha * 0.85)), lineWidth: 1.4)
            ctx.fill(
                Path(ellipseIn: CGRect(x: pos.x - 1.5, y: pos.y - 1.5, width: 3, height: 3)),
                with: .color(.white.opacity(alpha))
            )
        }
    }

    private struct Star {
        let x: Double
        let y: Double
        let size: Double
        let opacity: Double
    }
}

/// Mutable, non-observable store for in-flight shooting stars.
/// Lives across TimelineView ticks without re-triggering SwiftUI body.
@MainActor
private final class ShootingStarStore {
    var list: [ShootingStar] = []
    /// When the next shooting star should spawn — set on each spawn so
    /// the gaps look irregular.
    var nextSpawnAt: Date = Date().addingTimeInterval(.random(in: 2...5))
}

private struct ShootingStar {
    let start: CGPoint
    let velocity: CGVector
    let spawnedAt: Date
    let lifetime: TimeInterval
}
#endif
