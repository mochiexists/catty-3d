// Session store — Layer 2 protocol
//
// Catty doesn't ship a concrete persistence layer; storage is the embedding
// app's responsibility (Local AI Chat plugs into UnifiedMemoryManager;
// standalone Catty.app plugs into `FileBackedSessionStore`). The package only
// defines the contract.
//
// Status: scaffold. The protocol surface is experimental until v1.0 — observe
// will likely gain filtering options, save may split into save/upsert, etc.

#if os(macOS)
import Foundation

/// Persistence contract for `CattySession`. Implementations decide where
/// sessions live (JSON file, SwiftData, app-specific Core Data, in-memory)
/// and how change observation works.
///
/// All methods are `async throws` so implementations are free to back onto
/// disk, network, iCloud, or whatever — Catty doesn't care.
@MainActor
public protocol CattySessionStore: AnyObject, Sendable {
    /// All sessions known to the store, ordered however the impl prefers
    /// (typically lastActiveAt-descending). Catty's composed views re-sort
    /// for display.
    func load() async throws -> [CattySession]

    /// Insert or update by `id`. Bumps `lastActiveAt` is the impl's choice;
    /// Catty's composed views don't assume one way or the other.
    func save(_ session: CattySession) async throws

    /// Remove by id. No-op if not present.
    func delete(_ id: UUID) async throws

    /// Subscribe to "the session list changed" notifications. Called on the
    /// main actor with the new full list. Used by composed views to refresh
    /// when other parts of the app mutate the store. Returns a cancellation
    /// token; release it to stop observing.
    ///
    /// TODO(v0.2): consider switching to an `AsyncSequence` for more idiomatic
    /// Swift Concurrency. For now the closure API is simpler to implement.
    func observe(_ handler: @escaping @MainActor ([CattySession]) -> Void) -> CattySessionStoreObservation
}

/// Token returned by `CattySessionStore.observe`. Hold onto it as long as
/// you want updates; let it deinit to stop. Implementations release the
/// underlying subscription in deinit.
public final class CattySessionStoreObservation: Sendable {
    private let onCancel: @Sendable () -> Void

    public init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    deinit {
        onCancel()
    }
}
#endif
