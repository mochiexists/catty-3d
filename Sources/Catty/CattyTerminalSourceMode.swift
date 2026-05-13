// Catty's terminal source mode. Selects whether the textured plane in
// the 3D scene is fed by a local zsh process or a remote SSH session.
//
// Both modes produce a `SwiftTerm.TerminalView` (NSView on macOS); the
// capture loop in TerminalLiveTextureSource doesn't care which.
//
// macOS-only for this first pass — iOS port follows once we add a
// UIView-based capture path.

#if os(macOS)
import AppKit
import Foundation
import SwiftTerm

/// What's running inside the terminal pane. Public so consumers can
/// construct a Catty view targeted at either mode.
public enum CattyTerminalSourceMode {
    /// Local interactive shell (zsh by default). Not available in
    /// sandboxed builds — the host app is responsible for gating.
    case local

    /// SSH session against a remote host. Uses the host-provided
    /// `CattySSHTransportFactory` so the package stays neutral about
    /// which SSH library actually does the work.
    case ssh(CattySSHContext, transportFactory: CattySSHTransportFactory)
}

/// SwiftTerm `TerminalView` subclass that bridges keystrokes and resize
/// events to a bound `CattySSHTransporting`. Mirrors the iOS pattern but
/// uses AppKit clipboard / URL handlers.
@MainActor
final class CattySSHTerminalView: TerminalView, @preconcurrency TerminalViewDelegate {
    var transport: (any CattySSHTransporting)?

    /// Set by `TerminalLiveTextureSource` to be notified whenever the
    /// terminal view marks itself for redisplay. The source uses this to
    /// gate its 30 Hz capture loop: no dirty marks since last capture →
    /// skip the cacheDisplay + texture-replace work, freeing main-thread
    /// budget for the RealityKit TimelineView.
    var onDirty: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        terminalDelegate = self
        // 10k scrollback — same as the iOS sibling.
        changeScrollback(10_000)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
        onDirty?()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Pin to bottom on remote output (SwiftTerm only auto-scrolls on
    /// user keystrokes, so TUI repaints land below the viewport without
    /// this).
    func scrollToBottomOnNewOutput() {
        scroll(toPosition: 1.0)
    }

    // MARK: TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        transport?.cattySend(Array(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        transport?.cattyResize(cols: newCols, rows: newRows)
    }

    func scrolled(source: TerminalView, position: Double) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func clipboardCopy(source: TerminalView, content: Data) {
        if let str = String(data: content, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
        }
    }

    func clipboardRead(source: TerminalView) -> Data? {
        guard let str = NSPasteboard.general.string(forType: .string) else { return nil }
        return Data(str.utf8)
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    func bell(source: TerminalView) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

/// `LocalProcessTerminalView` with the same `onDirty` hook as the SSH
/// sibling, so the capture loop can skip ticks when nothing has changed
/// in the local zsh pane.
@MainActor
final class DirtyTrackingLocalProcessTerminalView: LocalProcessTerminalView {
    var onDirty: (() -> Void)?

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
        onDirty?()
    }
}
#endif
