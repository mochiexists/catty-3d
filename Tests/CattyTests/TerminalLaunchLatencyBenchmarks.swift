//
//  TerminalLaunchLatencyBenchmarks.swift
//
//  Measures time-to-ready when 4 panes simultaneously launch
//  `claude` (Claude Code). This is the "open Catty, fire ccy in
//  four windows" workload — the perf signal that matters for the
//  user-facing optimisation, not synthetic byte streams.
//
//  Readiness signal: a SessionStart hook (installed transiently in
//  ~/.claude/settings.local.json with backup/restore) emits a unique
//  per-run marker to STDERR — which IS terminal-visible — and we
//  grep the SwiftTerm grid for it. Hook-based detection is
//  deterministic and survives Claude Code banner changes; codex
//  uses model-context-only stdout per its docs, so we don't use it
//  here (banner detection would be the fallback for a codex variant).
//
//  Skips gracefully if `claude` isn't on PATH so CI runners without
//  the CLI installed still pass.
//

import AppKit
import Foundation
import XCTest

#if os(macOS)
@testable import Catty
import SwiftTerm

@MainActor
final class TerminalLaunchLatencyBenchmarks: XCTestCase {

    // MARK: - Tunables

    private let panes = 4
    private let pollInterval: TimeInterval = 0.05
    /// Cold `claude` launches can take a few seconds on first run
    /// (warm-cache much less). 90s is a generous ceiling; the test
    /// fulfils early.
    private let timeoutSecs: TimeInterval = 90
    /// Time we give zsh to land its first prompt before issuing
    /// `claude`. Spun on the main runloop, not slept.
    private let bootGraceSecs: TimeInterval = 1.0

    // MARK: - State

    /// Unique per-run marker so concurrent `claude` sessions on this
    /// machine (a user-level hook fires for every session) can't
    /// false-positive our test.
    private let runUUID = UUID().uuidString
    private var marker: String { "[CCY_READY_\(runUUID)]" }

    private let fm = FileManager.default
    private var settingsURL: URL {
        fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.local.json")
    }
    private var settingsBackup: Data?
    private var settingsExisted = false

    override func setUp() {
        super.setUp()
        // continueAfterFailure stays `true` (the default): we want
        // diagnostic prints + grid dumps to fire even if `wait(for:)`
        // times out, so a failing run is debuggable.
    }

    /// Trace file the hook touches on every fire. Counting these
    /// tells us whether the hook configuration reached `claude` at
    /// all — separating "hook didn't fire" from "marker didn't reach
    /// the SwiftTerm grid".
    private var traceGlob: String {
        "/tmp/ccy-fired-\(runUUID)-*"
    }

    // MARK: - Hook scaffolding

    /// Skip the test if `claude` isn't on PATH for an interactive
    /// zsh — same shell config the production source spawns.
    private func skipIfClaudeMissing() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", "command -v claude >/dev/null 2>&1"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            throw XCTSkip("`claude` not on PATH — skipping launch-latency benchmark")
        }
    }

    /// Install a transient SessionStart hook that printfs our marker
    /// to stderr (which IS visible in the terminal, unlike stdout
    /// which Claude Code routes to model context). Preserves any
    /// existing settings.local.json and restores in `restoreHook`.
    private func installHook() throws {
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        var current: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL) {
            settingsBackup = data
            settingsExisted = true
            if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                current = parsed
            }
        }
        var hooks = current["hooks"] as? [String: Any] ?? [:]
        // The hook does two things: emits a unique marker on stderr
        // (terminal-visible signal we grep the grid for), AND touches
        // a per-fire trace file (lets us diagnose hook-didn't-fire vs
        // marker-didn't-reach-grid independently).
        let hookCmd = "f=$(mktemp /tmp/ccy-fired-\(runUUID)-XXXXXX) && printf '\(marker)\\n' >&2"
        let ours: [String: Any] = [
            "type": "command",
            "command": hookCmd,
            "timeout": 5
        ]
        var session = hooks["SessionStart"] as? [Any] ?? []
        session.insert(ours, at: 0)
        hooks["SessionStart"] = session
        current["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: current,
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    private func restoreHook() {
        if settingsExisted, let backup = settingsBackup {
            try? backup.write(to: settingsURL, options: .atomic)
        } else if !settingsExisted {
            try? fm.removeItem(at: settingsURL)
        }
    }

    // MARK: - Helpers

    /// Read the current terminal viewport as text.
    private func gridText(_ src: TerminalLiveTextureSource) -> String {
        let t = src.terminalView.getTerminal()
        return t.getText(start: Position(col: 0, row: 0),
                         end: Position(col: max(t.cols - 1, 0),
                                       row: max(t.rows - 1, 0)))
    }

    /// Spin the main runloop for `seconds`. `Thread.sleep` would
    /// block the actor SwiftTerm's PTY reader needs to dispatch on,
    /// so output would never land in the grid.
    private func runLoopWait(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }

    // MARK: - Test

    private final class PaneState {
        var readyAt: [CFAbsoluteTime?]
        init(count: Int) { readyAt = Array(repeating: nil, count: count) }
        var allReady: Bool { !readyAt.contains(where: { $0 == nil }) }
    }

    func testFourPaneClaudeLaunchLatency() throws {
        try skipIfClaudeMissing()
        try installHook()
        defer { restoreHook() }

        // Build the production-path sources. No 3D scene, no
        // RealityKit overhead — just the PTY/SwiftTerm pipeline.
        let sources = (0..<panes).map { _ in
            TerminalLiveTextureSource(mode: .local, workingDirectory: nil)
        }
        defer { sources.forEach { $0.stop() } }

        sources.forEach { $0.start() }

        // Let zsh boot + show its prompt before we fire `claude`.
        runLoopWait(bootGraceSecs)

        // Issue the command in every pane at (essentially) the same
        // tick — the simultaneous-launch stress case.
        let issued = CFAbsoluteTimeGetCurrent()
        sources.forEach { $0.terminalView.send(txt: "claude\r") }

        // Poll each pane's grid for the marker via a main-runloop
        // timer; fulfil the expectation once every pane has seen it.
        // Ready-detection anchors (first match wins). The hook marker
        // is preferred (deterministic, fires before banner draw), but
        // `__claude_yolo`-style wrappers bypass hook trust in
        // practice, so we ALSO match the Claude Code welcome banner —
        // present once claude has drawn its UI. "Welcome back" covers
        // resumed sessions, "Welcome to Claude" covers cold first-run.
        let anchors = [marker, "Welcome back", "Welcome to Claude"]
        let state = PaneState(count: panes)
        let exp = expectation(description: "all panes ready")
        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
            for i in 0..<sources.count where state.readyAt[i] == nil {
                let grid = self.gridText(sources[i])
                if anchors.contains(where: { grid.contains($0) }) {
                    state.readyAt[i] = CFAbsoluteTimeGetCurrent()
                }
            }
            if state.allReady { exp.fulfill() }
        }
        // Use XCTWaiter directly so a timeout doesn't auto-XCTFail
        // and abort the diagnostic block below.
        let result = XCTWaiter().wait(for: [exp], timeout: timeoutSecs)
        timer.invalidate()

        // How many hook fires landed on disk — independent confirmation
        // the hook config reached `claude` (vs marker not reaching grid).
        let traceCount = (try? fm.contentsOfDirectory(atPath: "/tmp")
            .filter { $0.hasPrefix("ccy-fired-\(runUUID)-") }
            .count) ?? 0

        if result != .completed {
            // Diagnostic dump: what does each pane's grid actually
            // show right now? Trimmed to ~600 chars so the log stays
            // readable.
            print("== wait result: \(result), hook fires on disk: \(traceCount)/\(panes) ==")
            for (i, s) in sources.enumerated() {
                let raw = gridText(s)
                let snippet = raw.replacingOccurrences(of: "\u{1B}", with: "^[")
                let trimmed = snippet.count > 600 ? String(snippet.prefix(600)) + "…" : snippet
                print("---- pane \(i) grid (first 600 chars) ----")
                print(trimmed)
            }
        }

        // Report. This is a benchmark — print numbers, don't gate.
        // We only fail outright if every pane timed out, which would
        // mean the harness is broken (no signal at all).
        let times = state.readyAt.map { ($0 ?? .nan) - issued }
        print("== claude launch latency — \(panes) panes, simultaneous ==")
        for (i, t) in times.enumerated() {
            print(t.isNaN
                  ? "  pane \(i): TIMEOUT after \(timeoutSecs)s"
                  : String(format: "  pane \(i): %.3fs", t))
        }
        let resolved = times.filter { !$0.isNaN }.sorted()
        if resolved.count == panes {
            let mn = resolved.first!
            let mx = resolved.last!
            let med = resolved[resolved.count / 2]
            print(String(format: "  min=%.3fs  median=%.3fs  max=%.3fs  spread=%.3fs",
                         mn, med, mx, mx - mn))
            print(String(format: "  all-4-ready wall clock: %.3fs", mx))
        }
        XCTAssertFalse(resolved.isEmpty,
                       "No pane saw the readiness marker — hook or grid-poll is broken.")
    }
}
#endif
