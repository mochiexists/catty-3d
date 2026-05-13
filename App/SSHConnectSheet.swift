//
//  SSHConnectSheet.swift
//
//  Sheet for collecting SSH connection details. Minimal fields:
//  host, port, username, password. Defaults port to 22 and validates
//  before letting the user hit Connect.
//
//  All fields blank by default — explicitly no `NSUserName()` pre-fill
//  for the username, so nothing about the local macOS account leaks
//  into the form unless the user types it.
//
//  Credential storage (Keychain, recent-hosts list) is deferred —
//  every open is a fresh form for now. Same for SSH key auth: the
//  package's `SSHTransport` only exposes password auth as of today,
//  and adding key auth touches the package, not this app.
//

import Catty
import SwiftUI

struct SSHConnectSheet: View {
    var onConnect: (CattySSHContext) -> Void
    var onCancel: () -> Void

    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var password: String = ""

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case host, port, username, password
    }

    /// True only when all fields are non-empty and `port` parses to a
    /// reasonable TCP port. Connect button stays disabled until then.
    private var canConnect: Bool {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty,
              !username.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty,
              let portValue = Int(port),
              (1...65_535).contains(portValue)
        else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Connect via SSH")
                    .font(.title3.weight(.semibold))
                Spacer()
            }

            Form {
                TextField("Host", text: $host, prompt: Text("example.local or 192.168.1.42"))
                    .textContentType(.URL)
                    .focused($focusedField, equals: .host)
                    .onSubmit { focusedField = .port }

                TextField("Port", text: $port)
                    .focused($focusedField, equals: .port)
                    .onSubmit { focusedField = .username }

                TextField("Username", text: $username, prompt: Text("e.g. ubuntu, ec2-user"))
                    .textContentType(.username)
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .password }

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        if canConnect { fireConnect() }
                    }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect") { fireConnect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConnect)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { focusedField = .host }
    }

    private func fireConnect() {
        guard canConnect,
              let portValue = Int(port) else { return }
        let context = CattySSHContext(
            host: host.trimmingCharacters(in: .whitespaces),
            port: portValue,
            username: username.trimmingCharacters(in: .whitespaces),
            password: password,
            displayName: host.trimmingCharacters(in: .whitespaces)
        )
        onConnect(context)
    }
}
