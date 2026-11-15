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
//   komki-tresor agree --reason <text> --nonce <kennung>
//                                       "<key> <peer>" (stdin) -> shared secret (stdout)
//   komki-tresor prompt --reason <text> --nonce <kennung>
//                                       "<key> <peer>" (stdin) -> dialog text (stdout)
//
// All values are Base64 on one line. <key> is the enclave-encrypted form of
// the private key (dataRepresentation), public keys are x963 (65 bytes), the
// shared secret is the 32-byte x-coordinate of the ECDH result.
//
// recipient creates a new P-256 key in the Secure Enclave with the access rule
// "userPresence" (Touch ID or the Mac's password, this device only, unlocked
// only). The private key never leaves the enclave. No prompt.
//
// agree needs the enclave and with it the prompt: every process that wants
// the shared secret triggers it. The dialog text is composed here, not by
// the caller (#475): the seal fingerprint (first 8 hex characters of
// SHA-256 over ref and eph), then the per-agreement nonce the caller passes,
// then the caller's reason, labelled as untrusted text — the reason is
// presentation, not authorization. The calling side shows fingerprint and
// nonce in its own terminal so the person can compare both. prompt composes
// the same text without the enclave and without any prompt: nothing but
// display data, for tests and documentation.
//
// Exit codes: 0 ok, 2 wrong call, 3 no Secure Enclave, 4 release refused or
// cancelled, 5 key or peer invalid. Messages on stderr never name values
// (the fingerprint of the dialog text is display data, not a secret).

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

// Fingerprint of the seal the agreement would release (#475): the first 8
// hex characters of SHA-256 over ref and eph. The caller cannot choose it;
// it derives from the very key material of the request.
func fingerprint(_ ref: Data, _ eph: Data) -> String {
  SHA256.hash(data: ref + eph).prefix(4).map { String(format: "%02x", $0) }.joined()
}

// The consent text of the dialog (#475): fingerprint and nonce come from the
// request, not from the caller; the caller's reason follows, labelled as
// untrusted text. Both sides must format this alike so the person can
// compare the dialog with the caller's terminal line.
func dialogText(_ ref: Data, _ eph: Data, _ nonce: String, _ reason: String) -> String {
  "Siegel " + fingerprint(ref, eph) + ", Anfrage " + nonce
    + " - unvertrauter Aufrufertext: " + reason
}

// The nonce is dialog text: keep it short and plain so it cannot blur the
// composition (#475).
func validNonce(_ nonce: String) -> Bool {
  !nonce.isEmpty && nonce.count <= 32
    && nonce.allSatisfy { ($0.isASCII && $0.isLetter) || ($0.isASCII && $0.isNumber) }
}

// One line on stdin: "<b64 ref> <b64 eph>", the second value a valid P-256
// point. Everything else is exit 5, before any prompt.
func parse(_ line: String) -> (ref: Data, eph: Data, peer: P256.KeyAgreement.PublicKey) {
  let parts = line.split(separator: " ").map { Data(base64Encoded: String($0)) }
  guard parts.count == 2, let ref = parts[0], let eph = parts[1],
    let peer = try? P256.KeyAgreement.PublicKey(x963Representation: eph)
  else { fail(5, "Schluessel ungueltig") }
  return (ref, eph, peer)
}

func agree(_ line: String, reason: String, nonce: String) -> String {
  let parsed = parse(line)

  let context = LAContext()
  context.localizedReason = dialogText(parsed.ref, parsed.eph, nonce, reason)

  let key: SecureEnclave.P256.KeyAgreement.PrivateKey
  do {
    key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
      dataRepresentation: parsed.ref, authenticationContext: context)
  } catch {
    fail(5, "Schluessel gehoert nicht zu dieser Secure Enclave")
  }

  let shared: SharedSecret
  do {
    shared = try key.sharedSecretFromKeyAgreement(with: parsed.peer)
  } catch {
    fail(4, "Freigabe verweigert oder abgebrochen")
  }
  return shared.withUnsafeBytes { Data($0) }.base64EncodedString()
}

// The dialog text for a request, composed without the enclave and without
// any prompt: what agree would show, for tests and documentation (#475).
func prompt(_ line: String, reason: String, nonce: String) -> String {
  let parsed = parse(line)
  return dialogText(parsed.ref, parsed.eph, nonce, reason)
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
case let a
  where a.count == 5 && (a[0] == "agree" || a[0] == "prompt") && a[1] == "--reason"
    && !a[2].isEmpty && a[3] == "--nonce" && validNonce(a[4]):
  if a[0] == "agree" { requireEnclave() }
  guard let line = readLine(strippingNewline: true), !line.isEmpty else {
    fail(2, "erwartet genau eine nicht leere Zeile auf stdin")
  }
  if a[0] == "agree" {
    print(agree(line, reason: a[2], nonce: a[4]))
  } else {
    print(prompt(line, reason: a[2], nonce: a[4]))
  }
default:
  fail(
    2,
    "Aufruf: komki-tresor check | recipient | agree --reason <text> --nonce <kennung> | prompt --reason <text> --nonce <kennung>"
  )
}
