// swift-tools-version: 6.0
//
// Catty — a 3D terminal experience for macOS (and SSH-only on iOS),
// shipped as a Swift package plus a standalone macOS app.
//
// This repo is the source of truth for both:
//   • the `Catty` library product (the package — RealityKit scene,
//     SwiftTerm-backed terminal view, Citadel-backed SSH transport)
//   • the `CattyApp` executable target (the standalone app — launcher
//     view, SSH connect sheet, root view with session state machine)
//
// Other apps (notably Local AI Chat) depend on the `Catty` library
// product via a `path:` SPM reference today; once this repo lives at
// `mochiexists/catty` the dep flips to a `url:` reference pinned to a
// tagged version. The library itself never changes shape across that
// flip — only the LAIC manifest does.
//
// Platforms differ in surface:
//   • macOS — full 3D terminal experience + SSH transport.
//   • iOS — `SSHTransport`, `CattySSHContext`, `CattyConnectionState`
//     and the `CattySSHTransporting` protocol are usable. The
//     RealityKit / AppKit / SwiftTerm-NSView pieces are
//     `#if os(macOS)`-gated and don't compile on iOS. iOS consumers
//     bring their own terminal view (e.g. SwiftTerm's UIKit view) and
//     pipe bytes through `SSHTransport`.
//

import PackageDescription

let package = Package(
    name: "Catty",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        // Library — consumed by Local AI Chat and any other app that
        // wants Catty in a window of its own choosing.
        .library(
            name: "Catty",
            targets: ["Catty"]
        ),
        // Executable — the standalone Catty app. macOS-only (the App/
        // sources call SwiftUI APIs that depend on the macOS-only
        // half of the package).
        .executable(
            name: "CattyApp",
            targets: ["CattyApp"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/migueldeicaza/SwiftTerm.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/orlandos-nl/Citadel.git",
            exact: "0.12.1"
        )
    ],
    targets: [
        // Library target — package sources.
        .target(
            name: "Catty",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Citadel", package: "Citadel")
            ],
            path: "Sources/Catty",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                // SSHTransport's Citadel withPTY closure captures
                // TTYOutput/TTYStdinWriter into a TaskGroup — Swift 6's
                // sending diagnostics flag this as a data-race risk.
                // The code is correct (the closure runs serially), but
                // compiling in Swift 5 mode silences the diagnostic
                // until we refactor the session pump to be strict-
                // concurrency clean.
                .swiftLanguageMode(.v5)
            ]
        ),
        // Executable target — standalone macOS app sources.
        .executableTarget(
            name: "CattyApp",
            dependencies: ["Catty"],
            path: "App"
        )
    ]
)
