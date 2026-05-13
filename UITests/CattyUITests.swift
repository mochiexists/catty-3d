//
//  CattyUITests.swift
//
//  UI test target that drives Fastlane screenshot capture. Mirrors the
//  pattern used in Local AI Chat's `Local AI ChatUITests/SnapshotUITests.swift`:
//  each `snapshot(...)` call writes a PNG into Fastlane's screenshots
//  directory for later upload to App Store Connect.
//
//  Initial coverage: launcher screen only. Multi-session, settings, and
//  in-progress SSH state screenshots come later when those views exist.
//

import XCTest

final class CattyUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Captures the cold-start launcher screen. Fastlane picks the PNG
    /// up from `~/Library/Developer/Xcode/DerivedData/.../Logs/Test`
    /// and copies it into `fastlane/screenshots/macos/`.
    func testLauncherScreenshot() {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()

        // Give SwiftUI a moment to lay out the launcher's two cards
        // before the screenshot fires. Without this beat we sometimes
        // catch the window mid-resize.
        _ = app.staticTexts["Catty"].waitForExistence(timeout: 5)
        snapshot("01_launcher")
    }
}
