#!/usr/bin/env swift
import CryptoKit
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: derive_sparkle_public_key.swift <base64-private-key>\n", stderr)
    exit(1)
}

var base64 = CommandLine.arguments[1]
while base64.count % 4 != 0 {
    base64 += "="
}

guard let data = Data(base64Encoded: base64) else {
    fputs("Error: invalid base64 input\n", stderr)
    exit(1)
}

if data.count == 32 {
    do {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        print(privateKey.publicKey.rawRepresentation.base64EncodedString())
    } catch {
        fputs("Error deriving key: \(error)\n", stderr)
        exit(1)
    }
} else if data.count == 96 {
    let publicKey = data[64...]
    print(publicKey.base64EncodedString())
} else {
    fputs("Error: unexpected key length \(data.count) (expected 32 or 96)\n", stderr)
    exit(1)
}
