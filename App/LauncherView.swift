//
//  LauncherView.swift
//
//  The launcher cards. RootView already renders a live
//  `Terminal3DSceneView` behind us, so we don't draw a background or
//  a hero image — Maxwell is right there spinning. We just show two
//  cards (Local / SSH) over a translucent scrim, plus a path picker
//  inline on the Local card.
//
//  On the Indoor (Mac App Store) build the Local card is replaced by
//  a "needs the Outdoor build" CTA — sandboxed apps can't spawn the
//  user's shell, so the local terminal path is Outdoor-only. SSH
//  works on both Indoor and Outdoor because Citadel only needs the
//  `network.client` entitlement.
//
//  Working-directory picker (Outdoor only) mirrors Local AI Chat's
//  pattern: default is `~/Documents` (or whatever was last chosen,
//  persisted via the `@AppStorage` binding the parent owns), with an
//  inline link to change it via `NSOpenPanel` rather than blocking
//  the user with a modal file picker on every fresh launch.
//

import AppKit
import Catty
import SwiftUI

struct LauncherView: View {
    /// Two-way binding to the persisted local working-directory path.
    /// Empty means "use ~/Documents".
    @Binding var workingDirectory: String

    /// Fired when the user has chosen a session shape and is ready to
    /// open it.
    let onStart: (Intent) -> Void

    @State private var showingSSHSheet = false

    /// What LauncherView is telling RootView to do next.
    enum Intent {
        case openLocal
        case openSSH(CattySSHContext)
    }

    /// Where to send Indoor users who need a local terminal. The
    /// /download page handles arch detection + brew tap snippet.
    private let outdoorDownloadURL = URL(string: "https://catty3d.com/download")!

    /// Shared card dimensions so the two cards line up regardless of
    /// internal content. Tweak together if the layout needs more or
    /// less vertical breathing room.
    private let cardWidth: CGFloat = 280
    private let cardHeight: CGFloat = 300

    private var resolvedWorkingDirectory: URL {
        if workingDirectory.isEmpty {
            return URL(fileURLWithPath: NSHomeDirectory() + "/Documents", isDirectory: true)
        }
        return URL(fileURLWithPath: workingDirectory, isDirectory: true)
    }

    private var workingDirectoryDisplay: String {
        let path = workingDirectory.isEmpty
            ? NSHomeDirectory() + "/Documents"
            : workingDirectory
        return (path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        VStack(spacing: 32) {
            header

            HStack(alignment: .top, spacing: 24) {
                localCard
                sshCard
            }

            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingSSHSheet) {
            SSHConnectSheet { context in
                showingSSHSheet = false
                onStart(.openSSH(context))
            } onCancel: {
                showingSSHSheet = false
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Catty 3D")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text("A terminal that lives in 3D space.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 32)
    }

    // MARK: - Local card (build-variant-aware)

    @ViewBuilder
    private var localCard: some View {
        #if APPSTORE_BUILD
        indoorLocalCard
        #else
        outdoorLocalCard
        #endif
    }

    /// Outdoor variant — fully functional local session card.
    private var outdoorLocalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 32))
                .foregroundStyle(.tint)

            Text("New Local Session")
                .font(.headline)

            Text("Your default shell starts in the folder below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(workingDirectoryDisplay) { pickWorkingDirectory() }
                    .buttonStyle(.link)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !workingDirectory.isEmpty {
                    Button {
                        workingDirectory = ""
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to ~/Documents")
                }
            }

            Spacer(minLength: 0)

            Button {
                onStart(.openLocal)
            } label: {
                Text("Open")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    /// Indoor variant — local sessions disabled, points at the
    /// Outdoor download. Sandbox forbids spawning the user's shell.
    private var indoorLocalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("Local Terminal")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Local sessions need the Outdoor build of Catty — the App Store version can't spawn your shell from inside its sandbox.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Link(destination: outdoorDownloadURL) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                    Text("Download Outdoor")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - SSH card

    private var sshCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 32))
                .foregroundStyle(.tint)

            Text("New SSH Session")
                .font(.headline)

            Text("Connect to a remote host over SSH.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                showingSSHSheet = true
            } label: {
                Text("Connect…")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
    }

    /// AppKit open panel for choosing the local-terminal start dir.
    /// Same pattern Local AI Chat uses: defaults to `~/Documents`,
    /// persists choice across launches (via the parent's @AppStorage).
    private func pickWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder Catty's local terminal opens in."
        panel.directoryURL = resolvedWorkingDirectory
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }
}
