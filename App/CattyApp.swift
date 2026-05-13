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
    var body: some Scene {
        WindowGroup("Catty") {
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
