// Multi-session view — Layer 3, opt-in
//
// Renders multiple Catty sessions in 3D space. Today it's a thin pass-through
// (one session = one Terminal3DSceneView, anything beyond falls back to a
// tabs layout that shows the most-recently-active one). The interesting
// layouts (.row3D, .carousel3D, .grid3D) are scaffolded with TODO bodies for
// contributors to flesh out.
//
// This is the "contributor playground" surface: adding a new layout is pure
// additive work — no Layer 1 changes needed, no Layer 2 protocol changes.
// Once a layout reads good in playtest, it ships in the next minor version.
//
// Status: scaffold. .single + .tabs work; the 3D layouts are TODOs.

#if os(macOS)
import SwiftUI

/// How to arrange N session planes in the scene.
public enum CattyMultiSessionLayout: Equatable, Sendable {
    /// Show the active session only. Other sessions exist in the store but
    /// aren't rendered. Picker bar (managed by the host) switches active.
    case single

    /// Show active session as the main plane, plus a horizontal picker bar
    /// at the top. Inactive sessions don't render at all. Cheap on GPU.
    case tabs

    /// All sessions as planes in a horizontal row, equally spaced. Camera
    /// flies between them. `spacing` is the world-space gap between plane
    /// centers (planes are 1.6 wide today, so `spacing: 2.0` leaves a small
    /// gap).
    ///
    /// TODO(v0.3): implement. Needs:
    ///   • per-session world position computed from index + spacing
    ///   • camera dolly + look-at animation when active changes
    ///   • inactive sessions: pause their capture loop (visibility-gated)
    case row3D(spacing: Float)

    /// Sessions arranged on a ring around the user. Camera rotates to face
    /// the active one. `radius` is the ring's world-space radius.
    ///
    /// TODO(v0.3): implement. The orbiter math from `OrbiterRegistry.tick`
    /// is a good starting point — same parametrization (cos/sin around the
    /// Y axis), different consumer.
    case carousel3D(radius: Float)

    /// Sessions in a grid of `cols` columns. Wraps to additional rows above
    /// the first as needed. Camera defaults to a back-pulled overview pose.
    ///
    /// TODO(v0.4): implement. Likely needs a separate camera controller
    /// since the existing one is single-plane-centric.
    case grid3D(cols: Int)
}

/// Renders the sessions in a `CattySessionStore` according to `layout`.
///
/// Typical usage (standalone Catty.app):
///
/// ```swift
/// @StateObject var store = FileBackedSessionStore()
/// var body: some View {
///     CattyMultiSessionView(store: store, layout: .tabs)
/// }
/// ```
///
/// Local AI Chat doesn't use this today (single-session UX); a future
/// "Recent terminals library" feature could opt in.
public struct CattyMultiSessionView<Store: CattySessionStore>: View {
    public let store: Store
    public let layout: CattyMultiSessionLayout
    public let sshTransportFactory: CattySSHTransportFactory?

    @State private var sessions: [CattySession] = []
    @State private var activeID: UUID?
    @State private var observation: CattySessionStoreObservation?

    public init(
        store: Store,
        layout: CattyMultiSessionLayout = .tabs,
        sshTransportFactory: CattySSHTransportFactory? = nil
    ) {
        self.store = store
        self.layout = layout
        self.sshTransportFactory = sshTransportFactory
    }

    public var body: some View {
        Group {
            switch layout {
            case .single, .tabs:
                singleActiveBody  // .tabs differs only by a picker bar overlay (TODO)
            case .row3D, .carousel3D, .grid3D:
                // TODO(v0.3+): implement these. For now fall back to .single
                // so the API exists and consumers can opt in early. Render
                // an overlay banner so it's obvious the layout is unbuilt.
                ZStack(alignment: .top) {
                    singleActiveBody
                    Text("Layout \(String(describing: layout)) not yet implemented — showing active session only")
                        .font(.caption)
                        .padding(6)
                        .background(.yellow.opacity(0.85), in: Capsule())
                        .padding(.top, 8)
                }
            }
        }
        .task {
            observation = store.observe { newSessions in
                Task { @MainActor in
                    sessions = newSessions
                    if activeID == nil { activeID = newSessions.first?.id }
                }
            }
        }
    }

    @ViewBuilder
    private var singleActiveBody: some View {
        if let session = activeSession {
            Terminal3DSceneView(mode: resolvedMode(for: session))
        } else {
            EmptyStateView()
        }
    }

    private var activeSession: CattySession? {
        guard let id = activeID else { return sessions.first }
        return sessions.first(where: { $0.id == id })
    }

    private func resolvedMode(for session: CattySession) -> CattyTerminalSourceMode {
        switch session.mode {
        case .local(let cwd):
            // workingDirectory propagation happens via the Terminal3DSceneView
            // init parameter rather than the mode — Layer 1's existing surface.
            // TODO(v0.2): once Terminal3DSceneView accepts a session-scoped
            // working directory cleanly, plumb it through here.
            _ = cwd
            return .local
        case .ssh(let ctx):
            guard let factory = sshTransportFactory else {
                // Without a transport factory we can't open SSH. Surface
                // this as an error state rather than silently falling back
                // to local — that'd be confusing.
                // TODO(v0.2): replace with a proper error view + retry path.
                return .local
            }
            return .ssh(ctx, transportFactory: factory)
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("🐀")
                .font(.system(size: 48))
            Text("No sessions yet")
                .font(.title3)
            Text("Open a local terminal or connect via SSH to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
#endif
