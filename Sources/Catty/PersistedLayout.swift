//
//  PersistedLayout.swift
//
//  Snapshot of the multi-pane layout that survives an app restart.
//  Keyed by `PaneSlot` (row, column) so any pane the user spawned
//  anywhere on the grid round-trips. SSH panes are intentionally
//  excluded — re-establishing remote shells on cold-launch needs a
//  credential prompt, which doesn't belong in the launcher path.
//
//  Old format under `catty.layout.v1` used a 5-slot enum. v2 (this
//  file) uses the grid coord rawValue (`r0c0` / `r1c-2` / …). On
//  upgrade the v1 data is silently discarded — there are no shipped
//  users yet, so no migration step.
//

import Foundation

#if os(macOS)

public struct PersistedPane: Codable, Sendable {
    /// Rawvalue of the slot (`r0c0`, `r1c-2`, etc.) for stability
    /// across PaneSlot definition changes.
    public let slot: String
    /// Filesystem path the local shell was rooted at. Nil means
    /// "use the default (~/Documents)".
    public let workingDirectory: String?
}

public struct PersistedLayout: Codable, Sendable {
    public let panes: [PersistedPane]
    public let savedAt: Date

    public init(panes: [PersistedPane], savedAt: Date = .now) {
        self.panes = panes
        self.savedAt = savedAt
    }
}

public enum CattyLayoutStore {
    /// Grid-format key. Earlier `catty.layout.v1` is ignored on
    /// load because the rawValue parser refuses non-`rNcM` strings;
    /// no explicit clear needed.
    public static let defaultKey = "catty.layout.v2"

    public static func load(key: String = defaultKey) -> PersistedLayout? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedLayout.self, from: data)
    }

    public static func save(_ layout: PersistedLayout, key: String = defaultKey) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Convenience: snapshot a live `[PaneSlot: URL?]` dictionary
    /// and persist it under the grid-format key.
    public static func save(panes: [PaneSlot: URL?], key: String = defaultKey) {
        let persisted = panes.map { slot, url in
            PersistedPane(slot: slot.rawValue, workingDirectory: url?.path)
        }
        save(PersistedLayout(panes: persisted), key: key)
    }
}

#endif
