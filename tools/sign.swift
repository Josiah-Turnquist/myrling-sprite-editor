// Signs a message with Myrling's update key.
//
//   printf 'myrling-page\n%s\n%s' "$version" "$sha256" | swift tools/sign.swift
//
// Reads the message from stdin and prints two lines: the base64 Ed25519
// signature, then the base64 public key it can be checked against. tools/publish.py
// compares that second line to the public key baked into the Mac app, so a wrong
// key is caught here rather than by every user's failed update.
//
// The private key is base64 of 32 raw bytes, at ~/.myrling/update-key.b64 (or
// wherever MYRLING_UPDATE_KEY points). It lives outside the repository and must
// never be committed or copied into CI. macOS ships LibreSSL, which cannot do
// Ed25519 at all, so this is CryptoKit's job.

import Foundation
import CryptoKit

func die(_ message: String) -> Never {
  FileHandle.standardError.write(Data("sign.swift: \(message)\n".utf8))
  exit(1)
}

let env = ProcessInfo.processInfo.environment
let keyPath = env["MYRLING_UPDATE_KEY"]
  ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".myrling/update-key.b64").path

guard let keyText = try? String(contentsOfFile: keyPath, encoding: .utf8) else {
  die("cannot read the signing key at \(keyPath). Updates are signed with it; without it there is nothing to publish.")
}
guard let keyBytes = Data(base64Encoded: keyText.trimmingCharacters(in: .whitespacesAndNewlines)),
      keyBytes.count == 32 else {
  die("\(keyPath) is not base64 of 32 raw private key bytes.")
}
guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyBytes) else {
  die("\(keyPath) is not a usable Ed25519 private key.")
}

let message = FileHandle.standardInput.readDataToEndOfFile()
guard !message.isEmpty else { die("nothing arrived on stdin to sign.") }

guard let signature = try? key.signature(for: message) else { die("signing failed.") }
guard key.publicKey.isValidSignature(signature, for: message) else {
  die("the signature did not verify against its own key; refusing to hand it on.")
}

print(signature.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
