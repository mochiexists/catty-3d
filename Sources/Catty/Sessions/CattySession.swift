// Session — Layer 2 data model
//
// Represents one logical Catty terminal session (a single `Terminal3DSceneView`
// + the user-visible state around it). Pure value type, Codable, host-agnostic.
//
// Status: scaffold. The fields below describe the intended shape; downstream
// features (multi-session, persistence, history) build on this. The schema is
// experimental until v1.0 — adding fields is fine; renaming/removing is a
// breaking change.

#if os(macOS)
import Foundation
import SwiftUI

/// One Catty session: identity, transport mode, display metadata, and the
/// state needed to resume it later (camera pose, terminal buffer snapshot).
///
/// Designed to be persisted via `CattySessionStore` and rendered by either a
/// single-session view (`Terminal3DSceneView`) or a multi-session composed view.
public struct CattySession: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public var mode: CattyTerminalSourceModeDescriptor
    public var title: String
    public var createdAt: Date
    public var lastActiveAt: Date

    /// Optional camera pose, captured on session save so resuming restores the
    /// view the user left things in. Nil → use defaults.
    public var cameraSnapshot: CattyCameraSnapshot?

    /// Optional serialized terminal buffer (cells + cursor + scrollback) so
    /// resume can replay history into a fresh `TerminalView`. Format is
    /// `CattyTerminalBufferSnapshot` JSON-encoded. Nil → start with an empty
    /// terminal. See `CattyTerminalBufferSnapshot` for the format contract.
    ///
    /// TODO(v0.3): wire serialization in `TerminalLiveTextureSource.snapshot()`
    /// and deserialization in `start(replaying:)`. SwiftTerm doesn't ship
    /// Codable buffer APIs out of the box; we read `terminal.buffer` cells +
    /// `terminal.buffer.cursor` into our own structure.
    public var bufferSnapshot: Data?

    public init(
        id: UUID = UUID(),
        mode: CattyTerminalSourceModeDescriptor,
        title: String,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        cameraSnapshot: CattyCameraSnapshot? = nil,
        bufferSnapshot: Data? = nil
    ) {
        self.id = id
        self.mode = mode
        self.title = title
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.cameraSnapshot = cameraSnapshot
        self.bufferSnapshot = bufferSnapshot
    }
}

/// Codable mirror of `CattyTerminalSourceMode`. We can't make `CattyTerminalSourceMode`
/// itself Codable because its `.ssh` case carries a non-Codable transport-factory
/// closure. Instead, persist the *descriptor* (just the data needed to recreate
/// the mode) and rebuild the closure at restore time from the host's transport
/// factory.
public enum CattyTerminalSourceModeDescriptor: Codable, Hashable, Sendable {
    case local(workingDirectory: URL?)
    case ssh(CattySSHContext)
}

/// Camera pose snapshot for resume. All values are radians / world units in
/// the same coordinate system the scene uses internally.
public struct CattyCameraSnapshot: Codable, Hashable, Sendable {
    public var zoom: Double
    public var yaw: Float
    public var pitch: Float
    public var panX: Float
    public var panY: Float
    public var panZ: Float
    public var cameraMode: String   // raw value of `CameraMode` enum
    public var surfaceMode: String  // raw value of `TerminalSurfaceMode` enum

    public init(
        zoom: Double,
        yaw: Float,
        pitch: Float,
        panX: Float,
        panY: Float,
        panZ: Float,
        cameraMode: String,
        surfaceMode: String
    ) {
        self.zoom = zoom
        self.yaw = yaw
        self.pitch = pitch
        self.panX = panX
        self.panY = panY
        self.panZ = panZ
        self.cameraMode = cameraMode
        self.surfaceMode = surfaceMode
    }
}

/// Format for `CattySession.bufferSnapshot`. Versioned envelope so we can
/// migrate the on-disk format without breaking old data.
///
/// TODO(v0.3): finalize the cell representation. SwiftTerm uses
/// `(rune: UInt32, style: CharacterStyleAttribute)` per cell; we need to
/// preserve enough to round-trip glyph + color + bold/underline/inverse.
public struct CattyTerminalBufferSnapshot: Codable, Sendable {
    public let version: Int   // schema version, bump on breaking changes
    public let cols: Int
    public let rows: Int
    public let cursorRow: Int
    public let cursorCol: Int
    public let cells: Data    // packed cell representation, format-versioned

    public init(version: Int, cols: Int, rows: Int, cursorRow: Int, cursorCol: Int, cells: Data) {
        self.version = version
        self.cols = cols
        self.rows = rows
        self.cursorRow = cursorRow
        self.cursorCol = cursorCol
        self.cells = cells
    }
}
#endif
