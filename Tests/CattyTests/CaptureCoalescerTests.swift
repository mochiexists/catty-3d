//
//  CaptureCoalescerTests.swift
//
//  Locks the P0 capture-rate-limiter's decision logic — pure, no
//  timers, no SwiftTerm. The integration win (lower main-thread load
//  under 4-way cold launch) is measured separately by
//  TerminalLaunchLatencyBenchmarks; this file just guards the math
//  so a future refactor can't silently break the rate-cap or the
//  "first dirty captures immediately" guarantee.
//

@testable import Catty
import XCTest

#if os(macOS)
final class CaptureCoalescerTests: XCTestCase {

    func testFirstCallFiresImmediately() {
        let c = CaptureCoalescer(maxHz: 20.0)
        XCTAssertEqual(c.delay(forNow: 0), 0, accuracy: 1e-9,
                       "first capture must not be deferred")
        XCTAssertEqual(c.delay(forNow: 1000), 0, accuracy: 1e-9,
                       "no prior capture ⇒ still immediate, regardless of clock")
    }

    func testRateCapsAtMaxHz() {
        // 20 Hz ⇒ 50 ms min interval.
        let c = CaptureCoalescer(maxHz: 20.0)
        c.didCapture(at: 0)
        XCTAssertEqual(c.delay(forNow: 0.000), 0.050, accuracy: 1e-9)
        XCTAssertEqual(c.delay(forNow: 0.010), 0.040, accuracy: 1e-9)
        XCTAssertEqual(c.delay(forNow: 0.049), 0.001, accuracy: 1e-9)
        XCTAssertEqual(c.delay(forNow: 0.050), 0.000, accuracy: 1e-9)
        XCTAssertEqual(c.delay(forNow: 0.100), 0.000, accuracy: 1e-9,
                       "well past the interval is still 0, never negative")
    }

    func testSuccessiveCapturesUpdateBaseline() {
        let c = CaptureCoalescer(maxHz: 20.0)
        c.didCapture(at: 0.000)
        XCTAssertEqual(c.delay(forNow: 0.050), 0.000, accuracy: 1e-9)
        c.didCapture(at: 0.050)
        // Now the next-capture clock is from 0.050, not 0.000.
        XCTAssertEqual(c.delay(forNow: 0.060), 0.040, accuracy: 1e-9)
        XCTAssertEqual(c.delay(forNow: 0.100), 0.000, accuracy: 1e-9)
    }

    func testHigherHzGivesShorterInterval() {
        let fast = CaptureCoalescer(maxHz: 60.0)
        XCTAssertEqual(fast.minInterval, 1.0 / 60.0, accuracy: 1e-9)
        let slow = CaptureCoalescer(maxHz: 10.0)
        XCTAssertEqual(slow.minInterval, 0.1, accuracy: 1e-9)
    }
}
#endif
