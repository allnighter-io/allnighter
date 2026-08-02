//
// HarnessApp.swift — CAR-S00 product-free authority harness.
//
// Minimal Foundation macOS app. On launch it:
//   1. reads a nonce from its Application Support dir,
//   2. runs an authority probe set (Keychain reachability, filesystem write
//      outside any workspace, process/env facts),
//   3. writes receipt.json echoing the nonce,
//   4. terminates itself.
//
// No window, no user interaction, no daemon behavior. Temporary: CAR-S00 only.
//

import Foundation
import Security

// CAR-S00b: nonce/receipt live under the REAL product state root
// (`.../Application Support/Allnighter/`), which default Codex seatbelt lists
// as writable — the S00 `AllnighterHarness` dir was never writable inside
// Codex and confounded leg C (the nonce write failed before `open` ran).
let supportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Allnighter/car_s00_harness", isDirectory: true)
let nonceURL = supportDir.appendingPathComponent("nonce.txt")
let receiptURL = supportDir.appendingPathComponent("receipt.json")

// The filesystem AUTHORITY probe deliberately targets a path default Codex
// seatbelt does NOT list as writable (the old S00 harness dir). A sandboxed
// caller/inherited launch must fail this write; a detached LaunchServices
// launch must succeed. That asymmetry is the signal.
let fsProbeURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/AllnighterHarness/car_s00b_fs_probe.txt")

try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

// MARK: - 1. Nonce

let nonce = (try? String(contentsOf: nonceURL, encoding: .utf8))?
    .trimmingCharacters(in: .whitespacesAndNewlines)

// MARK: - 2a. Keychain availability probe (non-secret)
//
// Query a generic-password item that does not exist.
// errSecItemNotFound (-25300) = Keychain reachable -> authority OK.
// -34018 (errSecMissingEntitlement) or other denial = restricted context.

let keychainQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.happymoose.allnighter.harness.nonexistent",
    kSecAttrAccount as String: "car-s00-probe",
    kSecReturnData as String: false,
]
var item: CFTypeRef?
let keychainStatus = SecItemCopyMatching(keychainQuery as CFDictionary, &item)

// MARK: - 2b. Filesystem authority probe
//
// Write one byte to a path Codex seatbelt denies: outside the repo and any
// workspace root, in the user's own Library.

var fsProbeResult: String
do {
    try Data([0x41]).write(to: fsProbeURL, options: .atomic)
    fsProbeResult = "ok"
} catch {
    fsProbeResult = "denied: \(error.localizedDescription)"
}

// MARK: - 2c. Process authority facts

let pid = ProcessInfo.processInfo.processIdentifier
let ppid = getppid()
let codexSandbox = ProcessInfo.processInfo.environment["CODEX_SANDBOX"]

// MARK: - 3. Receipt

let timestamp = ISO8601DateFormatter().string(from: Date())

let receipt: [String: Any] = [
    "nonce": nonce as Any,
    "timestamp": timestamp,
    "pid": pid,
    "ppid": ppid,
    "codex_sandbox": codexSandbox as Any,
    "probes": [
        "keychain_status": Int(keychainStatus),
        "keychain_meaning": keychainStatus == errSecItemNotFound
            ? "errSecItemNotFound — Keychain reachable, authority OK"
            : "unexpected status — possible restricted context",
        "filesystem_write": fsProbeResult,
        "filesystem_path": fsProbeURL.path,
    ],
    "bundle_id": Bundle.main.bundleIdentifier as Any,
]

let receiptData = try JSONSerialization.data(
    withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
try receiptData.write(to: receiptURL, options: .atomic)

// MARK: - 4. Terminate (harness, not a daemon)

exit(0)
