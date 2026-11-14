// komki-tresor: the Secure Enclave side of komki's seals (format ktv2).
//
// Why a separate program: the Secure Enclave is only reachable through
// Apple's frameworks (CryptoKit, LocalAuthentication), not from Erlang. This
// program does hardware and nothing else. It holds no state and knows neither
// komki, the keychain nor the seal format; sealing and opening happen in
// Elixir (apps/sealed_envelope). Plaintext never reaches this program.
//
//   komki-tresor check                  Secure Enclave available? (exit 0/3)
//   komki-tresor recipient              new key -> "<key> <public>" (stdout)
//   komki-tresor agree --reason <text>  "<key> <peer>" (stdin) -> shared secret (stdout)
//
// All values are Base64 on one line. <key> is the enclave-encrypted form of
// the private key (dataRepresentation), public keys are x963 (65 bytes), the
// shared secret is the 32-byte x-coordinate of the ECDH result.
//
// recipient creates a new P-256 key in the Secure Enclave with the access rule
// "userPresence" (Touch ID or the Mac's password, this device only, unlocked
// only). The private key never leaves the enclave. No prompt.
//
// agree needs the enclave and with it the prompt: every process that wants the
// shared secret triggers it, and the person at the Mac sees the reason.
//
// Exit codes: 0 ok, 2 wrong call, 3 no Secure Enclave, 4 release refused or
// cancelled, 5 key or peer invalid. Messages on stderr never name values.

import CryptoKit
import Foundation
import LocalAuthentication
import Security

func fail(_ code: Int32, _ message: String) -> Never {
  FileHandle.standardError.write(Data(("komki-tresor: " + message + "\n").utf8))
  exit(code)
}

func recipient() throws -> String {
  var error: Unmanaged<CFError>?
  guard
    let access = SecAccessControlCreateWithFlags(
      nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &error)
  else { fail(3, "Zugriffsregel nicht anlegbar") }

  let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
  return key.dataRepresentation.base64EncodedString() + " "
    + key.publicKey.x963Representation.base64EncodedString()
}

func agree(_ line: String, reason: String) -> String {
  let parts = line.split(separator: " ").map { Data(base64Encoded: String($0)) }
  guard parts.count == 2, let ref = parts[0], let raw = parts[1],
    let peer = try? P256.KeyAgreement.PublicKey(x963Representation: raw)
  else { fail(5, "Schluessel ungueltig") }

  let context = LAContext()
  context.localizedReason = reason

  let key: SecureEnclave.P256.KeyAgreement.PrivateKey
  do {
    key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
      dataRepresentation: ref, authenticationContext: context)
  } catch {
    fail(5, "Schluessel gehoert nicht zu dieser Secure Enclave")
  }

  let shared: SharedSecret
  do {
    shared = try key.sharedSecretFromKeyAgreement(with: peer)
  } catch {
    fail(4, "Freigabe verweigert oder abgebrochen")
  }
  return shared.withUnsafeBytes { Data($0) }.base64EncodedString()
}

func requireEnclave() {
  guard SecureEnclave.isAvailable else { fail(3, "keine Secure Enclave auf diesem Mac") }
}

let args = Array(CommandLine.arguments.dropFirst())

switch args {
case ["check"]:
  requireEnclave()
  exit(0)
case ["recipient"]:
  requireEnclave()
  do {
    print(try recipient())
  } catch {
    fail(3, "Schluessel nicht anlegbar")
  }
case let a where a.count == 3 && a[0] == "agree" && a[1] == "--reason" && !a[2].isEmpty:
  requireEnclave()
  guard let line = readLine(strippingNewline: true), !line.isEmpty else {
    fail(2, "erwartet genau eine nicht leere Zeile auf stdin")
  }
  print(agree(line, reason: a[2]))
default:
  fail(2, "Aufruf: komki-tresor check | recipient | agree --reason <text>")
}
