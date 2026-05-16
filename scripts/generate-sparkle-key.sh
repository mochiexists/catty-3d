#!/usr/bin/env bash
set -euo pipefail

swift - <<'SWIFT'
import CryptoKit
import Foundation

let privateKey = Curve25519.Signing.PrivateKey()
let privateKeyBase64 = privateKey.rawRepresentation.base64EncodedString()
let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()

print("SPARKLE_PRIVATE_KEY=\(privateKeyBase64)")
print("SPARKLE_ED_PUBLIC_KEY=\(publicKeyBase64)")
SWIFT
