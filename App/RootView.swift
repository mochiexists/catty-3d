//
//  RootView.swift
//
//  Top-level window content. The 3D RealityKit scene is ALWAYS
//  present — Maxwell + rat + stars are spinning from the moment the
//  app launches. The launcher screen is just an overlay on top of
//  that scene, so when the user picks a session shape the overlay
//  fades and they're already looking at a live scene with their
//  terminal pane mounted on the textured plane.
//
//  No multi-session, no history, no settings yet — that's Layer 3
//  work in the Catty package, and we'll wire it through once the
//  scaffolds (`CattyMultiSessionView`, `CattySessionHistoryView`)
//  have working bodies.
//

import Catty
import SwiftUI

struct RootView: View {
    /// Working directory for the local-mode session. Defaults to
    /// `~/Documents`. Surfaced via `@AppStorage` so LauncherView can
    /// drive it via the inline path picker.
    @AppStorage("catty.local.workingDirectory") private var localWorkingDirectoryPath: String = ""

    /// What the user is doing right now. `.launcher` is the default
    /// state where the launcher cards float over the live local scene.
    /// `.session` means the cards are dismissed and the user is
    /// interacting with whichever terminal they chose.
    @State private var phase: Phase = .launcher

    /// SSH connection request from the launcher. When non-nil and
    /// phase is `.session(.ssh)`, the scene rebuilds with SSH transport.
    @State private var sshContext: CattySSHContext?

    private var localWorkingDirectory: URL {
        if localWorkingDirectoryPath.isEmpty {
            return URL(fileURLWithPath: NSHomeDirectory() + "/Documents", isDirectory: true)
        }
        return URL(fileURLWithPath: localWorkingDirectoryPath, isDirectory: true)
    }

    var body: some View {
        ZStack {
            // Always-present scene. The `.id(…)` keys force a fresh
            // `Terminal3DSceneView` (= a fresh shell or SSH session)
            // whenever the underlying mode changes. The package's own
            // top-left close button is suppressed — the standalone app
            // owns navigation at the window level.
            sessionScene
                .ignoresSafeArea()

            if case .launcher = phase {
                LauncherView(workingDirectory: $localWorkingDirectoryPath) { intent in
                    switch intent {
                    case .openLocal:
                        phase = .session(.local)

                    case .openSSH(let context):
                        sshContext = context
                        phase = .session(.ssh)
                    }
                }
                // Soft scrim so the cards read against the busy scene.
                .background(.thinMaterial.opacity(0.85))
                .transition(.opacity)
            }
        }
        // Back button as a top-leading overlay so it doesn't compete
        // with the ZStack's centring. `.ignoresSafeArea(edges: .top)`
        // lets it sit alongside the traffic lights — with hiddenTitleBar
        // SwiftUI still reserves a safe-area inset at the top that we
        // need to override here.
        .overlay(alignment: .topLeading) {
            if case .session = phase {
                Button {
                    phase = .launcher
                    sshContext = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Return to launcher")
                // Right of the traffic lights, same vertical line.
                .padding(.leading, 78)
                .padding(.top, 10)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea(edges: .top)
        .animation(.easeInOut(duration: 0.25), value: phase)
    }

    /// The currently-active terminal scene. Multi-pane spawning is
    /// handled inside `Terminal3DSceneView` at the package level —
    /// a single shared RealityKit scene hosts up to five coplanar
    /// terminal panes, with the right-rail toggle showing/hiding
    /// the spawn arrows around the centre pane.
    @ViewBuilder
    private var sessionScene: some View {
        switch phase {
        case .launcher, .session(.local):
            Terminal3DSceneView(
                mode: .local,
                workingDirectory: localWorkingDirectory,
                showsCloseButton: false
            )
            // Re-create the scene when the user picks a different
            // working directory at the launcher — the underlying
            // shell process needs to spawn there.
            .id(localWorkingDirectory.path)

        case .session(.ssh):
            if let sshContext {
                Terminal3DSceneView(
                    mode: .ssh(
                        sshContext,
                        transportFactory: { onOutput in
                            SSHTransport(onOutput: onOutput)
                        }
                    ),
                    showsCloseButton: false
                )
                .id(sshContext)
            } else {
                Color.black
            }
        }
    }

}

/// Drives the state-machine in `RootView`. Local sessions don't carry
/// a payload because the working directory lives in `@AppStorage`;
/// SSH sessions stash their `CattySSHContext` in `RootView.sshContext`.
extension RootView {
    enum Phase: Equatable {
        case launcher
        case session(SessionVariant)
    }

    enum SessionVariant: Equatable {
        case local
        case ssh
    }
}
