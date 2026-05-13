// Top-down 2D view of the orbit scene so we can debug positions without
// guessing from the 3D render. Uses the same OrbitConfigState math as
// Terminal3DRealityScene, advanced by the same TimelineView clock.
//
// Coordinate convention (matches Terminal3DRealityScene):
//   world +X → screen right
//   world +Z → screen DOWN (toward the viewer in the 3D scene)
//   world origin (0,0,0) → centre of the minimap (= where the terminal is)
//
// Camera position + yaw are read live from the parent so the map reflects
// what's actually on-screen rather than hardcoded assumptions.

#if os(macOS)
import SwiftUI

struct OrbitDebugMinimap: View {
    let config: OrbitConfigState
    /// 1.0 = camera tight, 0.3 = camera pulled back. Mirrors the scene.
    let zoom: Double
    /// Camera yaw in radians (⌥-drag in the parent updates this).
    let lookYaw: Float

    /// Approximate horizontal FOV (radians). RealityView's default
    /// PerspectiveCamera is ~60° vertical; this is the visual indicator,
    /// not a pixel-accurate frustum.
    private let cameraFOV: Float = .pi / 3

    /// View-local clock origin so `elapsed` stays small + Double-precision.
    @State private var startTime = Date()

    var body: some View {
        TimelineView(.animation) { context in
            // Keep the clock in Double so dot positions advance one frame
            // at a time. See `OrbiterRegistry.tick` for the Float ULP
            // discussion driving this.
            let elapsed = context.date.timeIntervalSince(startTime)

            Canvas { ctx, size in
                draw(ctx: ctx, size: size, elapsed: elapsed)
            }
        }
        .frame(width: 200, height: 200)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func draw(ctx: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        // World→minimap scale: leave headroom for the camera dot when pulled back.
        let maxWorldExtent: Double = 3.0  // a bit beyond the zoomed-out camera Z=2.6
        let scale = Double(min(size.width, size.height) * 0.42) / maxWorldExtent

        // 1. Orbit ring (uses live config.radius)
        let r = CGFloat(Double(config.radius) * scale)
        let orbitRect = CGRect(
            x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2
        )
        ctx.stroke(
            Path(ellipseIn: orbitRect),
            with: .color(.white.opacity(0.3)),
            lineWidth: 1
        )

        // 2. Terminal plane — world size 1.4 × 0.9 (matches the
        // ModelEntity plane in Terminal3DRealityScene). Top-down it's a
        // thin slab because the plane has no Z depth.
        let termPxWidth: CGFloat = CGFloat(1.4 * scale)
        let termPxThickness: CGFloat = 4
        ctx.fill(
            Path(CGRect(
                x: centre.x - termPxWidth / 2,
                y: centre.y - termPxThickness / 2,
                width: termPxWidth,
                height: termPxThickness
            )),
            with: .color(.white.opacity(0.85))
        )
        ctx.draw(
            Text("Terminal").font(.system(size: 9)).foregroundColor(.white.opacity(0.7)),
            at: CGPoint(x: centre.x, y: centre.y - 14)
        )

        // 3. Camera + FOV cone — actual position from the zoom interp.
        let zoomNorm = max(0, min(1, (zoom - 0.3) / 0.7))
        let mix = 1 - zoomNorm
        let camZ = 1.05 * (1 - mix) + 2.6 * mix
        let camPoint = CGPoint(
            x: centre.x,
            y: centre.y + CGFloat(camZ * scale)
        )
        // Default cone direction: up the map (toward the terminal at origin),
        // i.e. screen-Y = -1. lookYaw rotates the cone CCW (positive Y
        // rotation in world space = looking right of forward in screen).
        let halfFOV = cameraFOV / 2
        let fovReach = CGFloat((camZ + Double(config.radius)) * scale)
        let baseAngle = Float.pi / 2 + Float(lookYaw)  // up + yaw offset
        let leftAngle = baseAngle + halfFOV
        let rightAngle = baseAngle - halfFOV
        // In screen coords y is DOWN, so the cone fanning "up" the map
        // = negative-Y direction = -sin/cos pattern below.
        let leftRay = CGPoint(
            x: camPoint.x + cos(CGFloat(leftAngle)) * fovReach,
            y: camPoint.y - sin(CGFloat(leftAngle)) * fovReach
        )
        let rightRay = CGPoint(
            x: camPoint.x + cos(CGFloat(rightAngle)) * fovReach,
            y: camPoint.y - sin(CGFloat(rightAngle)) * fovReach
        )
        var conePath = Path()
        conePath.move(to: camPoint)
        conePath.addLine(to: leftRay)
        conePath.move(to: camPoint)
        conePath.addLine(to: rightRay)
        ctx.stroke(conePath, with: .color(.cyan.opacity(0.5)), lineWidth: 1)
        ctx.fill(
            Path(ellipseIn: CGRect(x: camPoint.x - 3, y: camPoint.y - 3, width: 6, height: 6)),
            with: .color(.cyan)
        )

        // 4. Rat dot — leads the chase.
        plotDot(
            ctx: ctx, centre: centre, scale: scale,
            phase: config.ratPhase, elapsed: elapsed, rate: config.rate, radius: config.radius,
            color: .systemPink, label: "R"
        )

        // 5. Maxwell dot — trails the rat.
        plotDot(
            ctx: ctx, centre: centre, scale: scale,
            phase: config.maxwellPhase, elapsed: elapsed, rate: config.rate, radius: config.radius,
            color: .orange, label: "C"
        )
    }

    private func plotDot(
        ctx: GraphicsContext,
        centre: CGPoint,
        scale: Double,
        phase: Float,
        elapsed: TimeInterval,
        rate: Float,
        radius: Float,
        color: SwiftUI.Color,
        label: String
    ) {
        // Same Float ULP fix as the 3D scene: keep the multiply in Double,
        // wrap into [0, 2π), then cast.
        let twoPiD: Double = 2 * .pi
        let angleD = (elapsed * Double(rate) + Double(phase))
            .truncatingRemainder(dividingBy: twoPiD)
        let angle = Float(angleD)
        let worldX = cos(angle) * radius
        let worldZ = sin(angle) * radius
        let p = CGPoint(
            x: centre.x + CGFloat(Double(worldX) * scale),
            y: centre.y + CGFloat(Double(worldZ) * scale)
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
            with: .color(color)
        )
        ctx.draw(
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(.white),
            at: CGPoint(x: p.x, y: p.y - 12)
        )
    }
}

private extension SwiftUI.Color {
    static var systemPink: SwiftUI.Color { SwiftUI.Color(red: 1, green: 0.4, blue: 0.6) }
}
#endif
