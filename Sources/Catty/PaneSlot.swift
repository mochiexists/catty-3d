//
//  PaneSlot.swift
//
//  Spatial identity for a terminal pane in Catty's grid layout. Each
//  pane lives at a (row, column) on a regular 2-D grid, with the
//  origin (0, 0) carrying the always-present centre session. Adjacent
//  cells are the spawn slots — flipping the "Add terminals" toggle
//  reveals a purple square on every empty neighbour of every filled
//  pane, so the layout can grow in any cardinal direction without an
//  imposed cap.
//
//  Public so consumers can persist and restore layouts keyed by
//  coord (see `PersistedLayout`).
//

import Foundation

#if os(macOS)

public struct PaneSlot: Hashable, Sendable, Codable, Identifiable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    /// The always-present centre pane.
    public static let origin = PaneSlot(row: 0, column: 0)

    public var id: String { "r\(row)c\(column)" }

    /// String representation used in persistence + debug logs.
    /// `r0c0`, `r1c0`, `r-1c2`, etc.
    public var rawValue: String { id }

    public init?(rawValue: String) {
        // Expect "r<int>c<int>". Lightweight parser — no regex.
        guard rawValue.first == "r",
              let cIndex = rawValue.firstIndex(of: "c") else { return nil }
        let rowPart = rawValue[rawValue.index(after: rawValue.startIndex)..<cIndex]
        let colPart = rawValue[rawValue.index(after: cIndex)...]
        guard let row = Int(rowPart), let column = Int(colPart) else { return nil }
        self.init(row: row, column: column)
    }

    /// World-space position of this pane's centre. Plane size is
    /// 1.6 wide × 1.05 tall; a small gap separates adjacent cells.
    /// Positive `row` is up (+Y), positive `column` is right (+X).
    /// All panes share z = 0 so the layout is coplanar.
    public var worldPosition: SIMD3<Float> {
        let planeW: Float = 1.6
        let planeH: Float = 1.05
        let gap: Float = 0.05
        return [
            Float(column) * (planeW + gap),
            Float(row) * (planeH + gap),
            0
        ]
    }

    /// The four cardinal neighbours. Used to compute the set of
    /// spawn slots (empty neighbours of any filled pane).
    public func neighbours() -> [PaneSlot] {
        [
            PaneSlot(row: row + 1, column: column),
            PaneSlot(row: row - 1, column: column),
            PaneSlot(row: row, column: column - 1),
            PaneSlot(row: row, column: column + 1)
        ]
    }
}

#endif
