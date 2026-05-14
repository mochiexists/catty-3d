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

@MainActor
final class CattyUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Cold-start launcher with the two cards visible over the live scene.
    func test01Launcher() {
        let app = launch(preset: "launcher")
        _ = app.staticTexts["Catty 3D"].waitForExistence(timeout: 5)
        capture(app: app, name: "01_launcher")
    }

    /// Single terminal pane at default zoom — Maxwell + rat orbiting,
    /// the prompt visible. The hero shot.
    func test02TerminalIn3D() {
        let app = launch(preset: "terminal-3d")
        sleep(3)
        capture(app: app, name: "02_terminal_in_3d")
    }

    /// Multi-pane cross with spawn squares ready to expand.
    func test03MultiPane() {
        let app = launch(preset: "multi-pane")
        sleep(3)
        capture(app: app, name: "03_multi_pane")
    }

    /// Ridiculous amount of terminals arranged in a cat silhouette.
    func test04CatShape() {
        let app = launch(preset: "cat-shape")
        sleep(4)
        capture(app: app, name: "04_cat_shape")
    }

    /// Same idea with a rat silhouette.
    func test05RatShape() {
        let app = launch(preset: "rat-shape")
        sleep(4)
        capture(app: app, name: "05_rat_shape")
    }

    // MARK: - Helpers

    private func launch(preset: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["CATTY_DETERMINISTIC_RENDER"] = "1"
        app.launchArguments += ["--catty-preset=\(preset)"]
        app.launch()
        return app
    }

    /// Capture the front window and write to a path the macOS UI-test
    /// sandbox can actually access. Mirrors Mochi Records' proven
    /// pattern: TCC blocks writes into ~/Documents from the runner, so
    /// we land PNGs in ~/Library/Caches/tools.fastlane/screenshots-macos
    /// (or the sandbox-redirected container variant) and let the lane
    /// shovel them into fastlane/screenshots/<locale>/.
    private func capture(app: XCUIApplication, name: String) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15),
                      "no window present to capture for \(name)")
        let data = window.screenshot().pngRepresentation
        XCTAssertFalse(data.isEmpty, "empty pngRepresentation for \(name)")

        let fm = FileManager.default
        let envDir = ProcessInfo.processInfo.environment["SNAPSHOT_MAC_OUTPUT_DIR"]
        let cacheBase = envDir.flatMap { URL(fileURLWithPath: $0) }
            ?? fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/tools.fastlane/screenshots-macos")
        do {
            try fm.createDirectory(at: cacheBase, withIntermediateDirectories: true)
            let outURL = cacheBase.appendingPathComponent("\(name).png")
            try data.write(to: outURL, options: .atomic)
            print("[CattyUITests] wrote \(outURL.path)")
        } catch {
            XCTFail("Failed to write \(name).png: \(error)")
        }
    }
}
