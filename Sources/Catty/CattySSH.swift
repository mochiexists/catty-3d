// Transport-neutral SSH plumbing for the Catty package. The package
// itself does not link Citadel/NIO — the host app provides an object
// conforming to `CattySSHTransporting` and Catty drives it.
//
// Why: keeps the package's dependency surface small (just SwiftTerm),
// lets the host evolve its own SSH stack independently, and avoids
// pulling Apple's NIO transitively into anything that just wants the
// 3D terminal stage.

import Foundation

/// SSH connection lifecycle as observed by Catty's UI banner. Mirrors
/// the states a typical SSH session passes through; the host transport
/// drives these.
public enum CattyConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case authenticating
    case connected
    case disconnected(String?)
}

/// Minimal contract Catty needs from an SSH transport implementation.
///
/// All entry points are main-actor-isolated because the consuming side
/// (SwiftTerm's `TerminalView`, RealityKit material updates, SwiftUI
/// `@State`-bound banner) lives there.
@MainActor
public protocol CattySSHTransporting: AnyObject {
    /// Current lifecycle state. Reflected by `stateDidChange` whenever
    /// it transitions.
    var cattyState: CattyConnectionState { get }

    /// Fired on each state transition. Catty installs this to update the
    /// "connecting…" / "disconnected: …" banner. Idempotent on re-set.
    var cattyStateDidChange: ((CattyConnectionState) -> Void)? { get set }

    /// Open the session. Host is responsible for password auth, host-key
    /// validation policy, environment, etc.
    func cattyConnect(
        host: String,
        port: Int,
        username: String,
        password: String,
        initialCols: Int,
        initialRows: Int
    )

    /// Push bytes from the terminal view's keystroke pipeline to the
    /// remote stdin.
    func cattySend(_ bytes: [UInt8])

    /// Forward window-size changes to the remote PTY.
    func cattyResize(cols: Int, rows: Int)

    /// Tear down the session. Catty calls this when the source stops or
    /// the user closes the sheet.
    func cattyDisconnect()
}

/// SSH connection context passed to `.ssh` Catty mode. Cleartext password
/// is in-memory only; persistence is the host's responsibility (keychain).
public struct CattySSHContext: Equatable, Hashable, Codable, Sendable {
    public let host: String
    public let port: Int
    public let username: String
    public let password: String
    public let displayName: String

    public init(
        host: String,
        port: Int,
        username: String,
        password: String,
        displayName: String
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.displayName = displayName
    }
}

/// Factory the host provides so Catty can create a transport without
/// importing the host's SSH library. The closure is called once at
/// session start with an `onOutput` callback that pushes received bytes
/// to the SwiftTerm view.
public typealias CattySSHTransportFactory = @MainActor (
    _ onOutput: @escaping @MainActor @Sendable (ArraySlice<UInt8>) -> Void
) -> CattySSHTransporting
