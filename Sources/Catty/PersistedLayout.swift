//
//  PersistedLayout.swift
//
//  Lightweight snapshot of the multi-pane layout that survives an
//  app restart. The user expects to relaunch and see the same five
//  terminals they left running last time — so we persist the slot →
//  working-directory map to UserDefaults on every spawn and rehydrate
//  it the next time `Terminal3DSceneView` is created.
//
//  SSH sessions are intentionally NOT persisted: re-establishing a
//  remote shell requires re-asking for credentials, which is a UX
//  flow that doesn't belong in cold-launch. Only `.local` panes
//  round-trip. Cold-launch with an SSH centre falls back to the
//  caller's `init` parameters.
//

import Foundation

#if os(macOS)

/// Encoded snapshot of one pane. We persist the mode + working dir
/// per slot; the centre pane is always re-created from the
/// `Terminal3DSceneView` `init` parameters, but its working dir is
/// remembered so the user picks up where they left off.
public struct PersistedPane: Codable, Sendable {
    /// Reverse-DNS string of the pane slot so the encoding is
    /// stable across PaneSlot renames in the package.
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

/// UserDefaults-backed persistence for the pane layout. Kept as a
/// stateless namespace because the read+write paths are called
/// from SwiftUI views that don't want an injected dependency.
public enum CattyLayoutStore {
    /// Default key. Override via `key:` to scope per-window or
    /// per-document if Catty ever gains those.
    public static let defaultKey = "catty.layout.v1"

    public static func load(key: String = defaultKey) -> PersistedLayout? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedLayout.self, from: data)
    }

    public static func save(_ layout: PersistedLayout, key: String = defaultKey) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Convenience: rebuild a layout from a live `[PaneSlot: URL?]`
    /// dictionary and persist it.
    public static func save(panes: [PaneSlot: URL?], key: String = defaultKey) {
        let persisted = panes.map { slot, url in
            PersistedPane(slot: slot.rawValue, workingDirectory: url?.path)
        }
        save(PersistedLayout(panes: persisted), key: key)
    }
}

#endif
