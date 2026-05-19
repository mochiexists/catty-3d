//
//  DeterministicRender.swift
//
//  Single source of truth for "render a frozen, reproducible frame"
//  mode, driven by the `CATTY_DETERMINISTIC_RENDER=1` launch
//  environment variable that `CattyUITests` already sets.
//
//  When on, the app:
//    • freezes orbit / cursor-cat / Maxwell motion (reuses the
//      existing `freezeOrbiters` icon-compose path),
//    • hides the random animated starfield,
//    • feeds the terminal a fixed scripted fixture instead of the
//      user's live zsh (whose prompt/cwd/timestamps are not
//      reproducible).
//
//  This is what makes before/after screenshot PARITY possible — the
//  whole scene is otherwise live (two TimelineViews + RNG + a real
//  shell), so a naive diff fails even with zero code change.
//
//  Zero release impact: it is a no-op unless the env var is set, and
//  only UI-test / parity tooling sets it.
//

import Foundation

#if os(macOS)

public enum DeterministicRender {
    /// True when launched for reproducible-frame capture. Read once at
    /// process start — the env is fixed for the process lifetime.
    public static let isOn: Bool =
        ProcessInfo.processInfo.environment["CATTY_DETERMINISTIC_RENDER"] == "1"

    /// Fixed terminal contents shown in deterministic mode. No clock,
    /// no cwd, no prompt drift — byte-identical every run so the
    /// captured texture is reproducible.
    public static let terminalFixture: String =
        """
        catty3d ~ % ls
        README.md   Sources   Tests   docs   Package.swift
        catty3d ~ % echo "a terminal that lives in 3D space"
        a terminal that lives in 3D space
        catty3d ~ % uname -sm
        Darwin arm64
        catty3d ~ %\u{20}
        """
}

#endif
