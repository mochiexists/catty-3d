//
//  CattyApp.swift
//
//  Standalone Catty app entry. Single window, borderless to match the
//  feel of Catty embedded inside Local AI Chat (no chrome competing
//  with the RealityKit scene).
//

import Catty
import SwiftUI

@main
struct CattyApp: App {
    init() {
        // Honour `--catty-preset=<name>` launch args from Fastlane /
        // UI tests so the cold-start scene matches the screenshot
        // composition. No-op when the arg isn't present.
        ScreenshotPresetLauncher.applyFromLaunchArgs()
    }

    var body: some Scene {
        WindowGroup("Catty 3D") {
            RootView()
                .frame(minWidth: 800, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
