// Exit 0: valid, 1: invalid signature, 2: usage or input error.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(2)
}

var publicKeyB64: String?
var zipPath: String?
var signatureB64: String?
var args = CommandLine.arguments.dropFirst()
while let flag = args.first {
  args = args.dropFirst()
  guard let value = args.first else { fail("missing value for \(flag)") }
  args = args.dropFirst()
  switch flag {
  case "--public-key": publicKeyB64 = value
  case "--zip": zipPath = value
  case "--signature": signatureB64 = value
  default: fail("unknown argument: \(flag)")
  }
}
guard let publicKeyB64, let zipPath, let signatureB64 else {
  fail("usage: --public-key <base64> --zip <path> --signature <base64>")
}
guard let publicKeyData = Data(base64Encoded: publicKeyB64), publicKeyData.count == 32 else {
  fail("public key is not base64 for 32 bytes")
}
guard let signatureData = Data(base64Encoded: signatureB64), signatureData.count == 64 else {
  fail("signature is not base64 for 64 bytes")
}
guard let archive = try? Data(contentsOf: URL(fileURLWithPath: zipPath), options: .mappedIfSafe) else {
  fail("cannot read archive: \(zipPath)")
}
guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
  fail("public key is not a valid Curve25519 key")
}
if publicKey.isValidSignature(signatureData, for: archive) {
  print("signature verifies against the public key")
} else {
  print("signature does NOT verify against the public key")
  exit(1)
}
