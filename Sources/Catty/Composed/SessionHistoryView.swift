// Session history view — Layer 3, opt-in, scaffolded
//
// Separate concept from `CattyMultiSessionView`:
//   • MultiSessionView = "show me the sessions I have right now"
//   • SessionHistoryView = "show me sessions I've had over time, let me search /
//     replay / star them"
//
// History potentially shares the same `CattySessionStore` backing or could
// use a richer store with structured transcript data — design decision still
// open. See the brief at docs/planning/catty-extraction-brief.md §6.
//
// Status: empty scaffold, design open. Don't depend on this signature yet.

#if os(macOS)
import SwiftUI

/// Browseable history of past Catty sessions. Lets the user search, preview,
/// star, delete, and resume sessions from before.
///
/// TODO(v0.5+): design + implement. Open questions:
///   • Does this use the same `CattySessionStore` as live sessions, or a
///     richer "transcript store" with terminal-output indexing?
///   • Search: substring across titles only, or full-text on terminal
///     output? Full-text needs a separate index — bigger lift.
///   • Resume semantics: open a new live session preloaded with the old
///     buffer, or read-only replay mode? Probably both, user toggles.
///   • Privacy: terminal output may contain secrets (passwords, tokens
///     pasted in). Sensible default = local-only, no iCloud sync, opt-in
///     export.
///
/// For now this is a placeholder so the API surface exists at v0.1 and we
/// can flesh it out without breaking import paths later.
public struct CattySessionHistoryView<Store: CattySessionStore>: View {
    public let store: Store
    public let onResume: (CattySession) -> Void

    public init(store: Store, onResume: @escaping (CattySession) -> Void) {
        self.store = store
        self.onResume = onResume
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text("📜")
                .font(.system(size: 48))
            Text("Session history coming soon")
                .font(.title3)
            Text("Tracking issue: see catty repo / docs/planning/catty-extraction-brief.md §6")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.8))
    }
}
#endif
