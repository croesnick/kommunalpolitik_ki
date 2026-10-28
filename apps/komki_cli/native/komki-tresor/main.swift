// komki-tresor: versiegelt Geheimnisse mit einem Schluessel der Secure Enclave.
//
// Warum ein eigenes Programm: Die Secure Enclave ist nur ueber Apples
// Frameworks (CryptoKit, LocalAuthentication) erreichbar, nicht aus Erlang.
// Das Programm haelt keinen Zustand und kennt weder komki noch den
// Schluesselbund; komki legt das Siegel im Schluesselbund ab.
//
//   komki-tresor check                  Secure Enclave vorhanden? (Exit 0/3)
//   komki-tresor seal                   Klartext (eine Zeile, stdin) -> Siegel (stdout)
//   komki-tresor open --reason <text>   Siegel (eine Zeile, stdin) -> Klartext (stdout)
//
// seal erzeugt je Geheimnis einen neuen P-256-Schluessel in der Secure
// Enclave mit der Zugriffsregel "userPresence" (Touch ID oder Passwort des
// Macs, nur auf diesem Geraet, nur entsperrt). Der private Schluessel
// verlaesst die Enclave nie; im Siegel steht nur seine von der Enclave
// verschluesselte Form. Verschluesselt wird per ECIES: ephemeres
// ECDH mit dem Enclave-Schluessel, HKDF-SHA256, AES-GCM.
//
// open braucht die Enclave und damit die Rueckfrage: Jeder Prozess, der das
// Siegel oeffnen will, loest sie aus, und die Person am Mac sieht den Grund.
//
// Exit-Codes: 0 ok, 2 Aufruf falsch, 3 keine Secure Enclave,
// 4 Freigabe verweigert oder abgebrochen, 5 Siegel ungueltig.
// Meldungen auf stderr nennen nie Klartext oder Siegel.

import CryptoKit
import Foundation
import LocalAuthentication
import Security

let prefix = "ktv1."
let info = Data("komki-tresor v1".utf8)

struct Seal: Codable {
  let key: Data  // dataRepresentation des Enclave-Schluessels
  let eph: Data  // ephemerer oeffentlicher Schluessel (x963)
  let box: Data  // AES-GCM, combined (Nonce + Chiffretext + Tag)
}

func fail(_ code: Int32, _ message: String) -> Never {
  FileHandle.standardError.write(Data(("komki-tresor: " + message + "\n").utf8))
  exit(code)
}

func readLine1() -> String {
  guard let line = readLine(strippingNewline: true), !line.isEmpty else {
    fail(2, "erwartet genau eine nicht leere Zeile auf stdin")
  }
  return line
}

func symmetricKey(_ shared: SharedSecret, eph: Data, recipient: Data) -> SymmetricKey {
  shared.hkdfDerivedSymmetricKey(
    using: SHA256.self, salt: eph + recipient, sharedInfo: info, outputByteCount: 32)
}

func seal(_ plaintext: String) throws -> String {
  var error: Unmanaged<CFError>?
  guard
    let access = SecAccessControlCreateWithFlags(
      nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &error)
  else { fail(3, "Zugriffsregel nicht anlegbar") }

  let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
  let eph = P256.KeyAgreement.PrivateKey()
  let ephPub = eph.publicKey.x963Representation
  let recipient = key.publicKey.x963Representation
  let shared = try eph.sharedSecretFromKeyAgreement(with: key.publicKey)
  let box = try AES.GCM.seal(
    Data(plaintext.utf8), using: symmetricKey(shared, eph: ephPub, recipient: recipient),
    authenticating: info)

  let sealed = Seal(key: key.dataRepresentation, eph: ephPub, box: box.combined!)
  return prefix + (try JSONEncoder().encode(sealed)).base64EncodedString()
}

func open(_ text: String, reason: String) -> String {
  guard text.hasPrefix(prefix),
    let raw = Data(base64Encoded: String(text.dropFirst(prefix.count))),
    let sealed = try? JSONDecoder().decode(Seal.self, from: raw),
    let ephPub = try? P256.KeyAgreement.PublicKey(x963Representation: sealed.eph),
    let box = try? AES.GCM.SealedBox(combined: sealed.box)
  else { fail(5, "Siegel ungueltig") }

  let context = LAContext()
  context.localizedReason = reason

  let key: SecureEnclave.P256.KeyAgreement.PrivateKey
  do {
    key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
      dataRepresentation: sealed.key, authenticationContext: context)
  } catch {
    fail(5, "Siegel gehoert nicht zu dieser Secure Enclave")
  }

  let shared: SharedSecret
  do {
    shared = try key.sharedSecretFromKeyAgreement(with: ephPub)
  } catch {
    fail(4, "Freigabe verweigert oder abgebrochen")
  }

  let symmetric = symmetricKey(
    shared, eph: sealed.eph, recipient: key.publicKey.x963Representation)
  guard let plain = try? AES.GCM.open(box, using: symmetric, authenticating: info),
    let value = String(data: plain, encoding: .utf8)
  else { fail(5, "Siegel ungueltig") }
  return value
}

func requireEnclave() {
  guard SecureEnclave.isAvailable else { fail(3, "keine Secure Enclave auf diesem Mac") }
}

let args = Array(CommandLine.arguments.dropFirst())

switch args {
case ["check"]:
  requireEnclave()
  exit(0)
case ["seal"]:
  requireEnclave()
  do {
    print(try seal(readLine1()))
  } catch {
    fail(3, "Versiegeln fehlgeschlagen")
  }
case let a where a.count == 3 && a[0] == "open" && a[1] == "--reason" && !a[2].isEmpty:
  requireEnclave()
  print(open(readLine1(), reason: a[2]))
default:
  fail(2, "Aufruf: komki-tresor check | seal | open --reason <text>")
}
