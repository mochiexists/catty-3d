//
//  CattyUITests.swift
//
//  UI tests that drive Fastlane screenshot capture. Each test
//  launches Catty with a `--catty-preset=<name>` arg so the cold-
//  start scene matches the composition we want to ship to the App
//  Store. Fastlane writes the PNGs into
//  `fastlane/screenshots/macos/en-US/` for upload via
//  `fastlane mac upload_screenshots`.
//

import XCTest

final class CattyUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Cold-start launcher with the two cards visible over the live scene.
    func test01Launcher() {
        let app = launch(preset: "launcher")
        // Wait for the launcher's "Catty" header to render.
        _ = app.staticTexts["Catty"].waitForExistence(timeout: 5)
        snapshot("01_launcher")
    }

    /// Single terminal pane at default zoom — Maxwell + rat orbiting,
    /// the prompt visible. The hero shot.
    func test02TerminalIn3D() {
        let app = launch(preset: "terminal-3d")
        sleep(3)  // give the scene a moment to settle into orbit
        snapshot("02_terminal_in_3d", app: app)
    }

    /// Multi-pane cross with spawn squares ready to expand.
    func test03MultiPane() {
        let app = launch(preset: "multi-pane")
        sleep(3)
        snapshot("03_multi_pane", app: app)
    }

    /// Ridiculous amount of terminals arranged in a cat silhouette.
    /// Zoom out before snapping so the whole shape is in frame.
    func test04CatShape() {
        let app = launch(preset: "cat-shape")
        sleep(4)
        snapshot("04_cat_shape", app: app)
    }

    /// Same idea with a rat silhouette.
    func test05RatShape() {
        let app = launch(preset: "rat-shape")
        sleep(4)
        snapshot("05_rat_shape", app: app)
    }

    // MARK: - Helpers

    /// Launch Catty with screenshot capture enabled and a preset
    /// applied. The deterministic-render env vars match the pattern
    /// used in Local AI Chat's snapshot tests so output looks the
    /// same across machines.
    private func launch(preset: String) -> XCUIApplication {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchEnvironment["SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["CATTY_DETERMINISTIC_RENDER"] = "1"
        app.launchArguments += ["--catty-preset=\(preset)"]
        app.launch()
        return app
    }

    /// Convenience overload so the no-app version still compiles.
    private func snapshot(_ name: String, app: XCUIApplication? = nil) {
        // Fastlane's `snapshot()` is global — no need to pass app.
        Snapshot.snapshot(name)
    }
}
