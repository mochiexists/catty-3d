//
//  ScreenshotPresets.swift
//
//  Launch-arg-driven scene presets for Fastlane / UI-test screenshot
//  capture. Read on app start by `Terminal3DSceneView.init` and used to
//  pre-populate the persisted layout under `CattyLayoutStore`'s key —
//  so the cold-start scene is whatever shape the screenshot needs.
//
//  Usage:
//
//    swift run CattyApp -- --catty-preset=cat-shape
//    open ~/Library/Developer/Xcode/.../Catty.app --args --catty-preset=launcher
//    XCUIApplication().launchArguments += ["--catty-preset=multi-pane"]
//
//  Recognised presets:
//
//    launcher      — clean cold start, just the launcher cards.
//    terminal-3d   — single pane at default zoom; Maxwell + rat
//                    visible orbiting.
//    multi-pane    — five-pane cross with spawn squares ready.
//    cat-shape     — ~20 panes arranged in a rough cat silhouette.
//                    For "ridiculous amount of terminals" hero shot.
//    rat-shape     — ~18 panes arranged in a rough rat silhouette.
//
//  Each preset writes into `CattyLayoutStore` so `Terminal3DSceneView`
//  picks the layout up via its normal init path. Presets clear out
//  any existing persisted state first — they're meant for fresh
//  capture runs, not user state preservation.
//

import Foundation

#if os(macOS)

public enum ScreenshotPreset: String, CaseIterable {
    case launcher
    case terminal3d = "terminal-3d"
    case multiPane = "multi-pane"
    case catShape = "cat-shape"
    case ratShape = "rat-shape"

    /// Pane coordinates this preset wants populated. Empty array
    /// means "single origin pane only" (centre is always present).
    public var paneCoords: [PaneSlot] {
        switch self {
        case .launcher, .terminal3d:
            return []
        case .multiPane:
            return [
                PaneSlot(row:  1, column:  0),
                PaneSlot(row: -1, column:  0),
                PaneSlot(row:  0, column:  1),
                PaneSlot(row:  0, column: -1)
            ]
        case .catShape:
            return Self.catSilhouette
        case .ratShape:
            return Self.ratSilhouette
        }
    }

    /// Rough cat-head + body silhouette in (row, column) coords.
    /// Origin (0,0) is the centre of the face. Positive row is up,
    /// positive column is right. Designed to read as a cat at low
    /// zoom (each pane becomes a "pixel" of the silhouette).
    private static let catSilhouette: [PaneSlot] = [
        // Ears (triangles)
                                          PaneSlot(row: 4, column: -3), PaneSlot(row: 4, column: 3),
                       PaneSlot(row: 3, column: -3), PaneSlot(row: 3, column: -2),                                              PaneSlot(row: 3, column: 2), PaneSlot(row: 3, column: 3),
        // Head
        PaneSlot(row: 2, column: -3), PaneSlot(row: 2, column: -2), PaneSlot(row: 2, column: -1), PaneSlot(row: 2, column: 0), PaneSlot(row: 2, column: 1), PaneSlot(row: 2, column: 2), PaneSlot(row: 2, column: 3),
        PaneSlot(row: 1, column: -3), PaneSlot(row: 1, column: -2),                                                            PaneSlot(row: 1, column: 2), PaneSlot(row: 1, column: 3),
        // Eyes line (origin row)
                                      PaneSlot(row: 0, column: -2),                                                            PaneSlot(row: 0, column: 2),
        // Cheeks / chin
        PaneSlot(row: -1, column: -2), PaneSlot(row: -1, column: -1),                              PaneSlot(row: -1, column: 1), PaneSlot(row: -1, column: 2),
        // Body
        PaneSlot(row: -2, column: -2), PaneSlot(row: -2, column: -1), PaneSlot(row: -2, column: 0), PaneSlot(row: -2, column: 1), PaneSlot(row: -2, column: 2),
        PaneSlot(row: -3, column: -1), PaneSlot(row: -3, column: 0), PaneSlot(row: -3, column: 1)
    ]

    /// Rat silhouette: long body, pointed nose, tail trailing right.
    private static let ratSilhouette: [PaneSlot] = [
        // Nose / face
                                                                                                                              PaneSlot(row: 0, column: 4),
        PaneSlot(row: 0, column: -3), PaneSlot(row: 0, column: -2), PaneSlot(row: 0, column: -1), PaneSlot(row: 0, column: 0), PaneSlot(row: 0, column: 1), PaneSlot(row: 0, column: 2), PaneSlot(row: 0, column: 3),
        // Back
        PaneSlot(row: 1, column: -3), PaneSlot(row: 1, column: -2), PaneSlot(row: 1, column: -1), PaneSlot(row: 1, column: 0), PaneSlot(row: 1, column: 1), PaneSlot(row: 1, column: 2),
        // Ear
        PaneSlot(row: 2, column: 0),
        // Belly
        PaneSlot(row: -1, column: -2), PaneSlot(row: -1, column: 1),
        // Tail trail (off to the left/down)
        PaneSlot(row: -1, column: -4), PaneSlot(row: -1, column: -3),
        PaneSlot(row: -2, column: -5)
    ]
}

public enum ScreenshotPresetLauncher {
    /// Initial camera zoom from `--catty-zoom=<double>` (orthogonal to
    /// the layout preset). Consulted by `Terminal3DSceneView`'s
    /// `@State zoom` default. `nil` → the normal 1.0 default.
    public static private(set) var initialZoom: Double?

    /// Initial origin-pane surface from `--catty-surface=<mode>`
    /// (`flat`/`curved`/`mobius`/`warp`). Consulted by the
    /// `@State surfaceModes` default. `nil` → flat.
    public static private(set) var initialSurfaceModes: [PaneSlot: TerminalSurfaceMode]?

    /// Read the current process's launch args and apply any
    /// `--catty-preset=<name>`, `--catty-zoom=<double>`, and
    /// `--catty-surface=<mode>` directives. Called from CattyApp's
    /// init() so layout/zoom/surface are in place before
    /// Terminal3DSceneView reads them. The three are independent so a
    /// parity-capture matrix can vary them orthogonally.
    public static func applyFromLaunchArgs() {
        let args = ProcessInfo.processInfo.arguments

        if let zoomArg = args.first(where: { $0.hasPrefix("--catty-zoom=") }),
           let value = Double(zoomArg.dropFirst("--catty-zoom=".count)) {
            initialZoom = value
            print("📸 Screenshot zoom: \(value)")
        }

        if let surfArg = args.first(where: { $0.hasPrefix("--catty-surface=") }) {
            let name = String(surfArg.dropFirst("--catty-surface=".count))
            if let mode = TerminalSurfaceMode(rawValue: name) {
                initialSurfaceModes = [.origin: mode]
                print("📸 Screenshot surface: \(mode.rawValue)")
            } else {
                print("⚠️ Unknown screenshot surface: \(name)")
            }
        }

        guard let arg = args.first(where: { $0.hasPrefix("--catty-preset=") }) else {
            return
        }
        let name = String(arg.dropFirst("--catty-preset=".count))
        guard let preset = ScreenshotPreset(rawValue: name) else {
            print("⚠️ Unknown screenshot preset: \(name)")
            return
        }
        apply(preset)
    }

    public static func apply(_ preset: ScreenshotPreset) {
        // Wipe any prior layout so the preset is the only thing
        // restored on cold start.
        UserDefaults.standard.removeObject(forKey: CattyLayoutStore.defaultKey)
        let workingDir = NSHomeDirectory() + "/Documents"
        var snapshot: [PaneSlot: URL?] = [:]
        snapshot[.origin] = URL(fileURLWithPath: workingDir, isDirectory: true)
        for coord in preset.paneCoords {
            snapshot[coord] = URL(fileURLWithPath: workingDir, isDirectory: true)
        }
        CattyLayoutStore.save(panes: snapshot)
        print("📸 Applied screenshot preset: \(preset.rawValue) (\(snapshot.count) panes)")
    }
}

#endif
