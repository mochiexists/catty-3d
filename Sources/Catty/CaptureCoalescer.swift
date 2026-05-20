//
//  CaptureCoalescer.swift
//
//  Decides when the terminal-capture path should run a frame, given a
//  stream of "dirty" events from SwiftTerm. Pure decision logic — no
//  timers, no threads, no SwiftTerm types — so it's unit-testable in
//  isolation and `TerminalLiveTextureSource` can replace its 30 Hz
//  polling timer with an event-driven, rate-capped cadence.
//
//  Why P0 wants this: the old `Timer.scheduledTimer(1/30)` rasterized
//  the terminal NSView at 30 Hz even when nothing changed (wasted main-
//  thread time at idle), AND gave no headroom during bursts (4-way
//  cold-launch raster costs spiked to ~480 ms on the first frames per
//  the launch-latency benchmark). Event-driven coalescing makes idle
//  free and caps burst load at 20 Hz, well under the 60 Hz display
//  refresh so the RealityKit tick + SwiftUI body always have room.
//

#if os(macOS)
import Foundation

/// Per-source rate-limiter for terminal-to-texture captures.
///
/// Usage: when a `dirty` signal arrives, ask `delay(forNow:)` how long
/// to wait before issuing the capture; defer that long; after the
/// capture, call `didCapture(at:)`. Multiple dirties inside the same
/// interval collapse into a single eventual capture.
final class CaptureCoalescer {
    /// Minimum time between consecutive captures, in seconds.
    /// Default 50 ms ⇒ 20 Hz ceiling. Below 60 Hz display refresh by
    /// design, so even a busy terminal can't saturate the runloop.
    let minInterval: TimeInterval

    private var lastCaptureAt: TimeInterval = -.infinity

    init(maxHz: Double = 20.0) {
        precondition(maxHz > 0, "maxHz must be positive")
        self.minInterval = 1.0 / maxHz
    }

    /// How long the caller should defer the next capture given current
    /// wall-clock time. 0 ⇒ capture immediately; >0 ⇒ a capture in the
    /// recent past is still rate-cap-limiting, defer by this many
    /// seconds so a burst of dirties collapses into one capture.
    func delay(forNow now: TimeInterval) -> TimeInterval {
        let elapsed = now - lastCaptureAt
        return max(0, minInterval - elapsed)
    }

    /// Record that a capture actually ran at `now`. Updates the
    /// rate-cap state used by subsequent `delay(forNow:)` calls.
    func didCapture(at now: TimeInterval) {
        lastCaptureAt = now
    }
}
#endif
