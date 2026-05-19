// Performance BASELINE for the terminal-capture hot path.
//
// The perf review found the dominant cost is the full-view CPU
// rasterization in TerminalLiveTextureSource.captureFrame()
// (`bitmapImageRepForCachingDisplay` + `cacheDisplay`, ~14 ms on main
// during output), and the planned P0 fix (coalesce/rate-cap captures)
// + P1/P2-5 (per-pane material reuse, bitmap reuse) target it.
//
// These tests load the terminal into three representative states and
// measure the capture cost so "perf isn't amazing" becomes a number.
// Re-run before/after each optimization and compare the reported
// averages — that is the regression/improvement yardstick the work
// is sequenced around.
//
// Reading the numbers: `swift test` prints
//   "measured [Clock Monotonic Time, s] average: 0.0123 ..."
// per case. Lower is better; relative std-dev should stay small.

import AppKit
import XCTest

#if os(macOS)
@testable import Catty
import SwiftTerm

@MainActor
final class TerminalCapturePerformanceTests: XCTestCase {

    private let captureRect = NSRect(origin: .zero,
                                     size: NSSize(width: 880, height: 566))

    /// A `.local` source WITHOUT `start()` — no zsh spawn, no 30 Hz
    /// timer. We feed bytes straight into the SwiftTerm view exactly
    /// the way the SSH path does (`view.feed(byteArray:)`), so the
    /// terminal reaches a real on-screen state deterministically.
    private func loadedSource(feeding text: String) -> TerminalLiveTextureSource {
        let source = TerminalLiveTextureSource(mode: .local)
        source.terminalView.feed(byteArray: ArraySlice(Array(text.utf8)))
        return source
    }

    /// Mirrors the production raster (TerminalLiveTextureSource.swift:
    /// 281-283) so we measure exactly that cost in isolation — GPU-free
    /// and deterministic, the bulletproof baseline.
    private func raster(_ view: TerminalView) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: captureRect) else {
            XCTFail("no bitmap rep")
            return
        }
        view.cacheDisplay(in: captureRect, to: rep)
        _ = rep.cgImage
    }

    // MARK: - Workloads

    private func bulkScrollback(lines: Int) -> String {
        (0..<lines).map {
            "drwxr-xr-x  3 user  staff  96 May 19 12:00 file-entry-\($0).swift\r\n"
        }.joined()
    }

    private func fullScreenChurn(frames: Int) -> String {
        let screen = (0..<25).map { row in
            String(repeating: "ABCDEFGHIJ", count: 8) + " r\(row)\r\n"
        }.joined()
        // ESC[2J = clear, ESC[H = home — a vim/htop-style full repaint.
        return (0..<frames).map { _ in "\u{1B}[2J\u{1B}[H" + screen }.joined()
    }

    private func manySmallChunks(count: Int) -> String {
        (0..<count).map { "chunk \($0) ok\r\n" }.joined()
    }

    // MARK: - Raster-cost baselines (GPU-free, deterministic)

    func testRasterCost_idlePrompt() {
        let source = loadedSource(feeding: "user@catty ~ % ")
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            raster(source.terminalView)
        }
    }

    func testRasterCost_bulkScrollback() {
        let source = loadedSource(feeding: bulkScrollback(lines: 5_000))
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            raster(source.terminalView)
        }
    }

    func testRasterCost_fullScreenChurn() {
        let source = loadedSource(feeding: fullScreenChurn(frames: 300))
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            raster(source.terminalView)
        }
    }

    func testRasterCost_manySmallChunksSSHLike() {
        let source = loadedSource(feeding: manySmallChunks(count: 3_000))
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            raster(source.terminalView)
        }
    }

    // MARK: - End-to-end production capture (raster + TextureResource)

    /// Drives the REAL TerminalLiveTextureSource.captureFrame() via the
    /// DEBUG test hook — the number to beat after the P0/P1 renderer
    /// work. Includes the RealityKit texture replace; if Metal is
    /// unavailable headless the replace throws and is swallowed exactly
    /// as in production, so the measurement still completes.
    func testEndToEndCaptureCost_fullScreenChurn() {
        let source = loadedSource(feeding: fullScreenChurn(frames: 300))
        measure(metrics: [XCTClockMetric()]) {
            source.captureFrameForTesting()
        }
    }
}
#endif
