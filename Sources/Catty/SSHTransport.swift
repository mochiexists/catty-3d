//
//  SSHTransport.swift
//  Catty
//
//  Citadel-backed SSH transport. Cross-platform (macOS + iOS) because
//  Catty's iOS surface is essentially "SSH only" — there's no `.local`
//  mode on iOS (sandbox forbids process spawn) and no 3D RealityKit
//  view on iOS yet, so the SSH transport is what the iOS consumer
//  actually needs from Catty.
//
//  Bridges Citadel's `SSHClient` to a byte-stream callback the consumer
//  pipes into their terminal (SwiftTerm AppKit `TerminalView` on macOS,
//  SwiftTerm UIKit `TerminalView` on iOS, or whatever else). Owns the
//  PTY session lifecycle: connect → open shell channel → pump stdout
//  out via `onOutput`, pump keystrokes / window-size events back in,
//  close cleanly on disconnect.
//
//  Single-shot: create one transport per terminal session. After
//  `disconnect()` the instance is finished and should be discarded.
//
//  Conforms to `CattySSHTransporting` so `Terminal3DSceneView`'s
//  `.ssh(..., transportFactory:)` can drive it on macOS without
//  knowing anything about Citadel/NIO.
//

import Foundation
import Citadel
import NIOCore
import NIOSSH

@MainActor
public final class SSHTransport {
    public enum AuthMethod: Sendable {
        case password(username: String, password: String)
    }

    public enum ConnectionState: Equatable, Sendable {
        case idle
        case connecting
        case authenticating
        case connected
        case disconnected(String?)
    }

    /// Reported on the main actor whenever `state` changes.
    public var stateDidChange: ((ConnectionState) -> Void)?

    public private(set) var state: ConnectionState = .idle {
        didSet { stateDidChange?(state) }
    }

    private let onOutput: @MainActor @Sendable (ArraySlice<UInt8>) -> Void
    private var sessionTask: Task<Void, Never>?

    private enum InputEvent: Sendable {
        case data([UInt8])
        case resize(cols: Int, rows: Int)
        case disconnect
    }
    private let inputContinuation: AsyncStream<InputEvent>.Continuation
    private let inputStream: AsyncStream<InputEvent>

    public init(onOutput: @escaping @MainActor @Sendable (ArraySlice<UInt8>) -> Void) {
        self.onOutput = onOutput
        var cont: AsyncStream<InputEvent>.Continuation!
        self.inputStream = AsyncStream { cont = $0 }
        self.inputContinuation = cont
    }

    public func connect(
        host: String,
        port: Int = 22,
        auth: AuthMethod,
        initialCols: Int,
        initialRows: Int
    ) {
        guard sessionTask == nil else { return }
        state = .connecting

        let citAuth: SSHAuthenticationMethod
        switch auth {
        case .password(let user, let pass):
            citAuth = .passwordBased(username: user, password: pass)
        }

        let cols = max(initialCols, 80)
        let rows = max(initialRows, 24)
        let onOutput = self.onOutput
        let inputStream = self.inputStream

        sessionTask = Task { @MainActor in
            #if DEBUG
            print("🔐 SSHTransport: connecting to \(host):\(port) (timeout 15s)")
            #endif
            do {
                self.state = .authenticating
                let client = try await SSHClient.connect(
                    host: host,
                    port: port,
                    authenticationMethod: citAuth,
                    hostKeyValidator: .acceptAnything(),
                    reconnect: .never,
                    connectTimeout: .seconds(15)
                )
                #if DEBUG
                print("✅ SSHTransport: handshake complete — opening PTY")
                #endif
                self.state = .connected

                let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: cols,
                    terminalRowHeight: rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: SSHTerminalModes([:])
                )

                // LANG=en_US.UTF-8 — TUI apps (claude, codex, vim, etc.)
                // refuse to draw box-drawing / wide-glyph characters when
                // the locale is unset. sshd_config's `AcceptEnv` typically
                // allows LANG; if it doesn't, the server silently ignores
                // the request and we fall back to the user's shell default.
                let env: [SSHChannelRequestEvent.EnvironmentRequest] = [
                    .init(wantReply: false, name: "LANG", value: "en_US.UTF-8")
                ]
                try await client.withPTY(pty, environment: env) { inbound, outbound in
                    await Self.runSession(
                        inbound: inbound,
                        outbound: outbound,
                        input: inputStream,
                        onOutput: onOutput
                    )
                }

                try? await client.close()
                self.state = .disconnected(nil)
            } catch {
                let message = Self.describe(error: error, host: host, port: port)
                #if DEBUG
                print("❌ SSHTransport: \(host):\(port) failed — \(error)")
                #endif
                self.state = .disconnected(message)
            }
        }
    }

    public func send(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        inputContinuation.yield(.data(bytes))
    }

    public func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        inputContinuation.yield(.resize(cols: cols, rows: rows))
    }

    /// Idempotent. Safe to call multiple times.
    public func disconnect() {
        inputContinuation.yield(.disconnect)
        inputContinuation.finish()
    }

    deinit {
        sessionTask?.cancel()
    }

    /// Produce a user-facing error string with a hint when the connection
    /// timed out — the most common cause is "Remote Login" being off on the
    /// target Mac, which manifests as a TCP timeout rather than a refusal.
    private static func describe(error: Error, host: String, port: Int) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        let lowered = raw.lowercased()
        if lowered.contains("timeout") || lowered.contains("timed out") {
            return "Couldn't reach \(host):\(port) within 15s. On the target Mac, turn on System Settings → General → Sharing → Remote Login. If it's already on, check the firewall."
        }
        if lowered.contains("connection refused") || lowered.contains("econnrefused") {
            return "\(host):\(port) refused the connection. Is Remote Login enabled on the Mac?"
        }
        if lowered.contains("auth") || lowered.contains("password") || lowered.contains("permission") {
            return "Authentication failed. Check the username and password."
        }
        return raw
    }

    /// Non-isolated helper so the `withPTY` closure (which is not main-actor
    /// isolated) can manage I/O pumps without crossing actor hops on every
    /// keystroke. Output is hopped back to the main actor before reaching the
    /// terminal view.
    private static func runSession(
        inbound: TTYOutput,
        outbound: TTYStdinWriter,
        input: AsyncStream<InputEvent>,
        onOutput: @escaping @MainActor @Sendable (ArraySlice<UInt8>) -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            // Remote stdout/stderr → terminal view.
            group.addTask {
                do {
                    for try await chunk in inbound {
                        var buf: ByteBuffer
                        switch chunk {
                        case .stdout(let chunkBuffer): buf = chunkBuffer
                        case .stderr(let chunkBuffer): buf = chunkBuffer
                        }
                        guard let bytes = buf.readBytes(length: buf.readableBytes),
                              !bytes.isEmpty else { continue }
                        let slice = ArraySlice(bytes)
                        await MainActor.run { onOutput(slice) }
                    }
                } catch {
                    // Session ended (EOF, non-zero exit, or cancellation).
                }
            }

            // Local input events → remote stdin / window-change.
            group.addTask {
                for await event in input {
                    switch event {
                    case .data(let bytes):
                        var buf = ByteBuffer()
                        buf.writeBytes(bytes)
                        try? await outbound.write(buf)
                    case .resize(let cols, let rows):
                        try? await outbound.changeSize(
                            cols: cols, rows: rows,
                            pixelWidth: 0, pixelHeight: 0
                        )
                    case .disconnect:
                        return
                    }
                }
            }

            await group.next()
            group.cancelAll()
        }
    }
}

// MARK: - CattySSHTransporting conformance

/// Adapter so `Terminal3DSceneView`'s `.ssh(..., transportFactory:)` can
/// drive `SSHTransport` directly. Consumers no longer need to vendor
/// a separate transport.
extension SSHTransport: CattySSHTransporting {
    public var cattyState: CattyConnectionState { state.cattyMapping }

    public var cattyStateDidChange: ((CattyConnectionState) -> Void)? {
        get {
            // Read-back not needed by Catty — the package only ever sets.
            nil
        }
        set {
            stateDidChange = newValue.map { handler in
                { state in handler(state.cattyMapping) }
            }
        }
    }

    public func cattyConnect(
        host: String,
        port: Int,
        username: String,
        password: String,
        initialCols: Int,
        initialRows: Int
    ) {
        connect(
            host: host,
            port: port,
            auth: .password(username: username, password: password),
            initialCols: initialCols,
            initialRows: initialRows
        )
    }

    public func cattySend(_ bytes: [UInt8]) { send(bytes) }
    public func cattyResize(cols: Int, rows: Int) { resize(cols: cols, rows: rows) }
    public func cattyDisconnect() { disconnect() }
}

private extension SSHTransport.ConnectionState {
    /// 1:1 map to the package's transport-neutral state.
    var cattyMapping: CattyConnectionState {
        switch self {
        case .idle: return .idle
        case .connecting: return .connecting
        case .authenticating: return .authenticating
        case .connected: return .connected
        case .disconnected(let reason): return .disconnected(reason)
        }
    }
}
