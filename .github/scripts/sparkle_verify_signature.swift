// Exit 0: valid, 1: invalid signature, 2: usage or input error.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(2)
}

var publicKeyB64: String?
var zipPath: String?
var feedPath: String?
var signatureB64: String?
var args = CommandLine.arguments.dropFirst()
while let flag = args.first {
  args = args.dropFirst()
  guard let value = args.first else { fail("missing value for \(flag)") }
  args = args.dropFirst()
  switch flag {
  case "--public-key": publicKeyB64 = value
  case "--zip": zipPath = value
  case "--feed": feedPath = value
  case "--signature": signatureB64 = value
  default: fail("unknown argument: \(flag)")
  }
}
guard let publicKeyB64, (zipPath != nil && signatureB64 != nil && feedPath == nil)
    || (feedPath != nil && zipPath == nil && signatureB64 == nil) else {
  fail("usage: --public-key <base64> (--zip <path> --signature <base64> | --feed <path>)")
}
guard let publicKeyData = Data(base64Encoded: publicKeyB64), publicKeyData.count == 32 else {
  fail("public key is not base64 for 32 bytes")
}
let path = feedPath ?? zipPath!
guard var archive = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
  fail("cannot read file: \(path)")
}
if feedPath != nil {
  let prefix = Data("<!-- sparkle-signatures:\n".utf8)
  let suffix = Data("-->".utf8)
  guard let start = archive.range(of: prefix, options: .backwards),
        let end = archive.range(of: suffix, in: start.upperBound..<archive.endIndex),
        let block = String(data: archive.subdata(in: start.upperBound..<end.lowerBound), encoding: .utf8) else {
    print("feed signature is missing or malformed")
    exit(1)
  }
  var contentLength: UInt64?
  block.enumerateLines { line, _ in
    if line.hasPrefix("edSignature:") {
      signatureB64 = String(line.dropFirst("edSignature:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    } else if line.hasPrefix("length:") {
      contentLength = UInt64(String(line.dropFirst("length:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }
  archive = archive.subdata(in: archive.startIndex..<start.lowerBound)
  guard contentLength == UInt64(archive.count) else {
    print("feed content length does NOT match its signature block")
    exit(1)
  }
}
guard let signatureB64, let signatureData = Data(base64Encoded: signatureB64), signatureData.count == 64 else {
  fail("signature is not base64 for 64 bytes")
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
