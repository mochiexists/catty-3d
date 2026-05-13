// Live-tunable config for the Maxwell + rat orbit. Used by both the
// RealityKit scene and the debug minimap/sliders so a value tweaked at
// runtime updates everything in lockstep.
//
// Coordinate system: world XZ plane is the floor. +X is right, +Z is
// toward the viewer. Origin (0,0,0) is where the terminal sits.

#if os(macOS)
import Foundation
import Observation

@MainActor
@Observable
public final class OrbitConfigState {
    /// Radius of the orbit ring around the terminal, in scene units.
    /// Must be wider than the depth-culling terminal plane (1.4 × 0.9)
    /// for the orbit to clear the plane's edges visibly.
    public var radius: Float = 1.6

    /// Master orbit rate (radians/sec). Same for both entities so the
    /// phase gap between them stays constant — that's what makes the
    /// chase read.
    public var rate: Float = 0.6

    /// Rat's starting phase. Acts as the "lead" of the chase.
    public var ratPhase: Float = 0

    /// Maxwell's starting phase. Negative = trailing the rat.
    /// ~0.4 rad ≈ 23° behind reads as "actively chasing".
    public var maxwellPhase: Float = -0.4

    /// Maxwell's self-spin rate (Y-axis pirouette, radians/sec).
    public var maxwellSpinRate: Float = 2.2

    /// Maxwell's model scale. Sketchfab Maxwell ships in some absurd
    /// unit so this lands very small (~0.0004 baseline).
    public var maxwellScale: Float = 0.0004

    /// Rat's model scale. CairoSpinyMouse is in metres-ish.
    public var ratScale: Float = 0.05

    /// Terminal opacity. 1.0 = fully opaque (current default); below
    /// that the terminal blends with what's behind it — useful for
    /// seeing Maxwell + rat orbit through it. Drops to 0 = invisible.
    public var terminalOpacity: Float = 1.0

    public init() {}
}
#endif
