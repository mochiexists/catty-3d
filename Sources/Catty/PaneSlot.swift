//
//  PaneSlot.swift
//
//  Spatial identity for a terminal pane within Catty's multi-pane
//  layout. Centre is always populated (the original session);
//  cardinals are optional spawn slots in the same coplanar 2-D
//  plane (z = 0) so the user gets up to five terminals laid out
//  in a cross.
//
//  Public so consumers can persist + restore sessions keyed by
//  slot (Layer 2 work — see `CattySession`).
//

import Foundation

#if os(macOS)

public enum PaneSlot: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
    case centre, north, south, east, west

    public var id: String { rawValue }

    /// World-space position of this pane's centre. Plane size is
    /// 1.6 wide × 1.05 tall; a small gap separates adjacent panes.
    /// All five slots share z = 0 so they're literally coplanar —
    /// the camera frames the whole cluster from in front.
    public var worldPosition: SIMD3<Float> {
        let planeW: Float = 1.6
        let planeH: Float = 1.05
        let gap: Float = 0.05
        switch self {
        case .centre: return [0, 0, 0]
        case .east:   return [ (planeW + gap), 0, 0]
        case .west:   return [-(planeW + gap), 0, 0]
        case .north:  return [0,  (planeH + gap), 0]
        case .south:  return [0, -(planeH + gap), 0]
        }
    }

    /// Direction the spawn arrow for this slot points. Used by the
    /// SwiftUI overlay that renders "+" arrows around the centre
    /// pane when the user is in add-terminals mode.
    public var arrowSystemName: String {
        switch self {
        case .centre: return "circle"
        case .north:  return "arrow.up.circle.fill"
        case .south:  return "arrow.down.circle.fill"
        case .east:   return "arrow.right.circle.fill"
        case .west:   return "arrow.left.circle.fill"
        }
    }
}

#endif
