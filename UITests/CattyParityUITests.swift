//
//  CattyParityUITests.swift
//
//  Deterministic screenshot matrix for before/after VISUAL PARITY.
//  Every test launches with `CATTY_DETERMINISTIC_RENDER=1` so the
//  scene is frozen + starless + fed a fixed terminal fixture — the
//  capture is byte-stable across runs, so `Scripts/visual-parity.sh`
//  can diff baseline vs working-tree and a difference means the
//  rendering ACTUALLY changed (the safety net for the Phase-2
//  renderer decomposition in docs/planning/oss-refactor-plan.md).
//
//  Matrix: camera (default / zoom-in / zoom-out), surface mesh
//  (flat / curved / möbius / warp), and layout (single / multi-pane).
//  PNGs are written as `parity_<name>.png` so the diff script can
//  glob them apart from the App Store `NN_*` marketing shots.
//

import XCTest

@MainActor
final class CattyParityUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testParityTerminalDefault() {
        capture(launchParity(preset: "terminal-3d"), "parity_terminal_default")
    }

    func testParityTerminalZoomIn() {
        capture(launchParity(preset: "terminal-3d", zoom: 2.2), "parity_terminal_zoom_in")
    }

    func testParityTerminalZoomOut() {
        capture(launchParity(preset: "terminal-3d", zoom: 0.4), "parity_terminal_zoom_out")
    }

    func testParitySurfaceCurved() {
        capture(launchParity(preset: "terminal-3d", surface: "curved"), "parity_surface_curved")
    }

    func testParitySurfaceMobius() {
        capture(launchParity(preset: "terminal-3d", surface: "mobius"), "parity_surface_mobius")
    }

    func testParitySurfaceWarp() {
        capture(launchParity(preset: "terminal-3d", surface: "warp"), "parity_surface_warp")
    }

    func testParityMultiPane() {
        capture(launchParity(preset: "multi-pane"), "parity_multi_pane")
    }

    // MARK: - Helpers

    private func launchParity(preset: String,
                              zoom: Double? = nil,
                              surface: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CATTY_DETERMINISTIC_RENDER"] = "1"
        app.launchArguments += ["--catty-preset=\(preset)"]
        if let zoom { app.launchArguments += ["--catty-zoom=\(zoom)"] }
        if let surface { app.launchArguments += ["--catty-surface=\(surface)"] }
        app.launch()
        return app
    }

    /// Capture the front window. Lets the frozen scene settle a beat
    /// (texture capture + RealityView build are async) then writes the
    /// PNG to `$SNAPSHOT_MAC_OUTPUT_DIR` (set per-run by the parity
    /// script) or the sandbox-safe fastlane cache dir. Mirrors the
    /// path workaround in CattyUITests.capture.
    private func capture(_ app: XCUIApplication, _ name: String) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15),
                      "no window to capture for \(name)")
        // Deterministic, but the first texture capture + scene build
        // still need a moment to land before the frame is stable.
        sleep(3)
        let data = window.screenshot().pngRepresentation
        XCTAssertFalse(data.isEmpty, "empty pngRepresentation for \(name)")

        let fm = FileManager.default
        let envDir = ProcessInfo.processInfo.environment["SNAPSHOT_MAC_OUTPUT_DIR"]
        let base = envDir.flatMap { URL(fileURLWithPath: $0) }
            ?? fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/tools.fastlane/screenshots-macos")
        do {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            let out = base.appendingPathComponent("\(name).png")
            try data.write(to: out, options: .atomic)
            print("[CattyParityUITests] wrote \(out.path)")
        } catch {
            XCTFail("Failed to write \(name).png: \(error)")
        }
    }
}
