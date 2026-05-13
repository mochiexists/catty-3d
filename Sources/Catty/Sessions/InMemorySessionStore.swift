// In-memory session store — Layer 2 reference implementation
//
// Default `CattySessionStore` impl. Useful for:
//   • Tests that need a working store without disk I/O.
//   • Apps that don't want session persistence (live-only sessions, no
//     resume-after-quit).
//   • A starting point contributors can copy from when building disk-backed
//     or remote-backed stores.
//
// Status: working. Doesn't persist across process restarts.

#if os(macOS)
import Foundation

/// Trivial `CattySessionStore` that keeps everything in RAM. Observation
/// fires synchronously after every mutation.
@MainActor
public final class InMemorySessionStore: CattySessionStore {
    private var sessions: [UUID: CattySession] = [:]
    private var observers: [UUID: @MainActor ([CattySession]) -> Void] = [:]

    public init(seed: [CattySession] = []) {
        for s in seed {
            sessions[s.id] = s
        }
    }

    public func load() async throws -> [CattySession] {
        sortedSnapshot()
    }

    public func save(_ session: CattySession) async throws {
        sessions[session.id] = session
        notify()
    }

    public func delete(_ id: UUID) async throws {
        sessions.removeValue(forKey: id)
        notify()
    }

    public func observe(_ handler: @escaping @MainActor ([CattySession]) -> Void) -> CattySessionStoreObservation {
        let token = UUID()
        observers[token] = handler
        // Fire once immediately so the consumer starts with current state.
        handler(sortedSnapshot())
        return CattySessionStoreObservation { [weak self] in
            Task { @MainActor [weak self] in self?.observers.removeValue(forKey: token) }
        }
    }

    // MARK: - Internal

    private func sortedSnapshot() -> [CattySession] {
        sessions.values.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    private func notify() {
        let snapshot = sortedSnapshot()
        for handler in observers.values {
            handler(snapshot)
        }
    }
}
#endif
