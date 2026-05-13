// Owns a single off-screen LocalProcessTerminalView, runs zsh inside it,
// and exposes its visual content as a periodically-updated TextureResource
// so the RealityKit scene can map it onto a ModelEntity plane.
//
// Why: the SwiftUI-overlay approach hits an unavoidable wall — anything in
// the RealityView gets pixel-overwritten by the SwiftUI layer above, so
// Maxwell can never visibly pass behind the terminal. By moving the
// terminal INTO RealityKit as a textured plane, depth testing works.
//
// macOS-only (Outdoor).

#if os(macOS)
import AppKit
import Foundation
import Observation
import RealityKit
import SwiftTerm
import SwiftUI

@MainActor
@Observable
public final class TerminalLiveTextureSource {
    /// The actual terminal NSView. Either a `LocalProcessTerminalView`
    /// (zsh) or a `CattySSHTerminalView` (SSH-fed). Both extend
    /// SwiftTerm's `TerminalView`, so the capture/feed pipeline is
    /// identical for both modes.
    let terminalView: TerminalView

    /// Latest captured frame as a TextureResource. The RealityKit scene
    /// observes this and re-applies it to the terminal plane's material.
    /// Reused via `TextureResource.replace(withImage:)` after first
    /// generation, so per-frame work avoids GPU allocation churn.
    private(set) var currentTexture: TextureResource?

    /// Monotonically incremented each time `currentTexture` gets new
    /// pixels (even when it's the same instance via in-place replace).
    /// `Terminal3DRealityScene.applyTerminalTexture` reads this to know
    /// it actually needs to re-bind the material, since `ObjectIdentifier`
    /// alone wouldn't catch in-place updates.
    private(set) var textureVersion: Int = 0

    /// Live connection state, mirrored from the underlying transport
    /// when the source is in `.ssh` mode. `.idle` for local mode.
    public private(set) var connectionState: CattyConnectionState = .idle

    /// Active mode — useful for the launcher to decide whether to show
    /// a "connecting…" overlay until handshake completes.
    public let mode: CattyTerminalSourceMode

    /// Terminal grid size (cols × rows). For callers that want to map a
    /// cell to a position on the textured plane.
    public var terminalGridSize: (cols: Int, rows: Int) {
        let term = terminalView.getTerminal()
        return (max(term.cols, 1), max(term.rows, 1))
    }

    /// Current text-cursor cell, clamped into the grid. Used by the 3D
    /// scene to park a little spinning Maxwell at the prompt (à la ratty).
    public var cursorCell: (col: Int, row: Int) {
        let term = terminalView.getTerminal()
        let loc = term.getCursorLocation()   // SwiftTerm: (x: col, y: row)
        let cols = max(term.cols, 1)
        let rows = max(term.rows, 1)
        return (min(max(loc.x, 0), cols - 1), min(max(loc.y, 0), rows - 1))
    }

    private var captureTimer: Timer?
    private var sshTransport: (any CattySSHTransporting)?
    /// Dirty flag set by the terminal view whenever it marks itself for
    /// redisplay. The capture timer reads + clears this each tick to
    /// skip work when nothing has changed (huge main-thread savings when
    /// the terminal is idle at a prompt). Initially `true` so the first
    /// capture always runs.
    private var needsCapture = true
    /// `start()` is idempotent — gated by this flag so the
    /// re-entrant inits SwiftUI does on view-struct rebuilds can't
    /// spawn multiple shell processes or parallel SSH connections.
    private var hasStarted = false

    /// Capture resolution. The aspect ratio MUST match the RealityKit
    /// plane (1.4 × 0.9 = 1.555:1) so the texture isn't squashed or
    /// the wrong edges clipped. 880 / 1.555 ≈ 566 → use 880×566.
    let captureSize = NSSize(width: 880, height: 566)

    /// Directory the local shell starts in. `nil` → `~/Documents`
    /// (falling back to `~` if that doesn't exist). Ignored for SSH mode.
    private let workingDirectory: URL?

    public convenience init() {
        self.init(mode: .local, workingDirectory: nil)
    }

    public init(mode: CattyTerminalSourceMode, workingDirectory: URL? = nil) {
        self.mode = mode
        self.workingDirectory = workingDirectory
        // NSView allocation only — no shell spawn, no SSH connect, no
        // timer. Those are deferred to `start()` so SwiftUI's repeated
        // view-struct construction (which throws away most of these
        // instances) doesn't pile up resources.
        switch mode {
        case .local:
            let view = DirtyTrackingLocalProcessTerminalView(
                frame: NSRect(origin: .zero, size: NSSize(width: 880, height: 566))
            )
            view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            view.nativeBackgroundColor = .black
            view.changeScrollback(10_000)
            self.terminalView = view

        case .ssh:
            let view = CattySSHTerminalView(
                frame: NSRect(origin: .zero, size: NSSize(width: 880, height: 566))
            )
            view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            view.nativeBackgroundColor = .black
            self.terminalView = view
        }
        wireDirtyTracking()
    }

    /// Connect the terminal view's dirty signal to our `needsCapture` flag.
    /// Has to happen after the switch above because `self.terminalView` is
    /// the immutable property both subclass paths bind to.
    private func wireDirtyTracking() {
        let mark: () -> Void = { [weak self] in
            self?.needsCapture = true
        }
        if let local = terminalView as? DirtyTrackingLocalProcessTerminalView {
            local.onDirty = mark
        } else if let ssh = terminalView as? CattySSHTerminalView {
            ssh.onDirty = mark
        }
    }

    /// Kick off the actual work: spawn zsh / connect SSH / start the
    /// capture timer. Idempotent — calling more than once is safe (so
    /// onAppear can re-fire without harm).
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true

        switch mode {
        case .local:
            guard let view = terminalView as? LocalProcessTerminalView else { return }
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            // chdir before spawn so the forked shell inherits that cwd —
            // without this, Catty's local terminal lands in `/` (the
            // app's own working dir), which is useless. Restore the
            // app's cwd immediately after so nothing else in the process
            // sees the change. Honor an explicit `workingDirectory`;
            // otherwise default to ~/Documents (→ ~ if missing).
            let fm = FileManager.default
            let priorCwd = fm.currentDirectoryPath
            let startDir: String = {
                if let workingDirectory,
                   fm.fileExists(atPath: workingDirectory.path) {
                    return workingDirectory.path
                }
                let docs = NSHomeDirectory() + "/Documents"
                return fm.fileExists(atPath: docs) ? docs : NSHomeDirectory()
            }()
            _ = fm.changeCurrentDirectoryPath(startDir)
            // Inherit the parent process env and override TERM. Wiping
            // env to just TERM left zsh with no HOME/PATH/USER, so
            // ~/.zshrc never sourced — meaning user exports (notably
            // CLAUDE_CODE_HIDE_ACCOUNT_INFO and PATH additions) were
            // missing inside Catty's shell vs. the user's Terminal.app.
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"
            // Guarantee HOME / SHELL / USER even if the app was launched
            // by LaunchServices without them. zsh login init falls apart
            // silently if these aren't set.
            if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }
            if env["SHELL"] == nil { env["SHELL"] = shell }
            if env["USER"] == nil { env["USER"] = NSUserName() }
            // Catty's terminal is frequently on screen during demos and
            // screenshots — hide Claude Code's account/email banner by
            // default. (Doesn't suppress the org-name line in CC's full
            // welcome box — that's tied to the cwd being a "fresh"
            // directory CC has no history for — but it does cover the
            // /login and account-switcher contexts.) Still overridable:
            // a later user export in ~/.zshrc would win.
            if env["CLAUDE_CODE_HIDE_ACCOUNT_INFO"] == nil {
                env["CLAUDE_CODE_HIDE_ACCOUNT_INFO"] = "1"
            }
            // Scrub session/agent markers that leak in when Catty itself
            // was launched from inside a Claude Code / cmux session
            // (`ProcessInfo.environment` copies the parent's env). A
            // fresh embedded terminal must not advertise itself as nested
            // inside a running agent — it confuses tools like `claude`
            // into rendering a resumed-session UI.
            for key in [
                "CLAUDECODE",
                "CLAUDE_CODE_SESSION_ID",
                "CLAUDE_CODE_ENTRYPOINT",
                "CLAUDE_CODE_EXECPATH",
                "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS",
                "CLAUDE_EFFORT",
                "CMUX_CLAUDE_PID",
                "AI_AGENT"
            ] {
                env.removeValue(forKey: key)
            }
            let envArray = env.map { "\($0.key)=\($0.value)" }
            view.startProcess(
                executable: shell,
                args: ["--login"],
                environment: envArray
            )
            _ = fm.changeCurrentDirectoryPath(priorCwd)

        case .ssh(let ctx, let makeTransport):
            guard let view = terminalView as? CattySSHTerminalView else { return }
            let transport = makeTransport { [weak view] slice in
                guard let view else { return }
                view.feed(byteArray: slice)
                view.scrollToBottomOnNewOutput()
                // Off-screen NSViews don't repaint on data alone, so
                // cacheDisplay keeps capturing the old bitmap. Force
                // a redraw each feed. Mac-only quirk vs iOS UIView.
                view.needsDisplay = true
            }
            view.transport = transport
            self.sshTransport = transport
            transport.cattyStateDidChange = { [weak self] state in
                self?.connectionState = state
                #if DEBUG
                print("🐀 Catty SSH state: \(state)")
                #endif
            }
            transport.cattyConnect(
                host: ctx.host,
                port: ctx.port,
                username: ctx.username,
                password: ctx.password,
                initialCols: 100,
                initialRows: 30
            )
        }
        startCaptureLoop()
    }

    /// Make the terminal the focused first responder of the app's main
    /// window. Called when the user clicks on the textured plane.
    public func focusTerminal() {
        guard let window = terminalView.window else { return }
        window.makeFirstResponder(terminalView)
    }

    // MARK: - Capture loop

    private func startCaptureLoop() {
        // 30Hz capture. The 3D scene itself runs at the display refresh
        // rate via TimelineView(.animation) — typically 60Hz on most
        // Macs. The texture only refreshes on capture ticks; the scene
        // RE-USES the most recent one between ticks (see the diff guard
        // in `applyTerminalTexture`), so 30Hz text doesn't gate 60fps
        // motion.
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureFrame()
            }
        }
    }

    private func captureFrame() {
        // Skip the tick entirely when the terminal hasn't dirtied itself
        // since the last capture. cacheDisplay + texture-replace cost
        // ~14 ms on main; doing that 30×/s when nothing changed was
        // saturating the main thread and stealing frames from the 3D
        // scene's TimelineView. First capture always runs (currentTexture
        // is nil) so the plane never starts blank.
        if !needsCapture && currentTexture != nil { return }
        needsCapture = false

        let view = terminalView
        let innerRect = NSRect(origin: .zero, size: captureSize)
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        #endif
        guard let viewRep = view.bitmapImageRepForCachingDisplay(in: innerRect) else { return }
        view.cacheDisplay(in: innerRect, to: viewRep)
        guard let cgImage = viewRep.cgImage else { return }
        #if DEBUG
        let tCache = CFAbsoluteTimeGetCurrent()
        #endif

        let opts = TextureResource.CreateOptions(semantic: .color)
        do {
            if let existing = currentTexture {
                // In-place GPU update — keeps the same MTLTexture, just
                // overwrites pixels. Apple's recommended path for live-
                // streaming RealityKit textures. Avoids the per-frame
                // GPU allocation that TextureResource.generate(from:)
                // would otherwise do at 30Hz.
                try existing.replace(withImage: cgImage, options: opts)
                textureVersion &+= 1
            } else {
                let texture = try TextureResource(image: cgImage, options: opts)
                currentTexture = texture
                textureVersion &+= 1
            }
        } catch {
            // Silently ignore — generation/replace can fail mid-resize.
            // Next frame will catch up.
        }
        #if DEBUG
        let tEnd = CFAbsoluteTimeGetCurrent()
        let cacheMs = (tCache - t0) * 1000
        let texMs = (tEnd - tCache) * 1000
        // Only log if either step ate more than ~half a 60Hz frame (8 ms).
        // Below that, the cost is well-amortised; above, it's a stutter
        // suspect worth investigating.
        if cacheMs > 8 || texMs > 8 {
            print("🐢 captureFrame: cacheDisplay=\(String(format: "%.1f", cacheMs))ms texture=\(String(format: "%.1f", texMs))ms")
        }
        #endif
    }

    /// Stop the capture loop and tear down any SSH transport. Call
    /// before releasing — deinit can't touch `captureTimer` because
    /// that's main-actor-isolated and deinit isn't.
    public func stop() {
        captureTimer?.invalidate()
        captureTimer = nil
        sshTransport?.cattyDisconnect()
        sshTransport = nil
    }
}

/// Hosts the source's terminal NSView in the SwiftUI hierarchy so it
/// becomes a child of the app's NSWindow — which is what lets
/// `window.makeFirstResponder` actually route keys to it.
///
/// Sized to the capture resolution. Positioned off-screen via `.offset`
/// in the parent so it stays invisible but laid out for the capture loop.
public struct TerminalSourceEmbed: NSViewRepresentable {
    public let source: TerminalLiveTextureSource

    public init(source: TerminalLiveTextureSource) {
        self.source = source
    }

    public func makeNSView(context: Context) -> TerminalView {
        source.terminalView
    }

    public func updateNSView(_ nsView: TerminalView, context: Context) {
        // The source owns the view and drives capture itself.
    }
}
#endif
