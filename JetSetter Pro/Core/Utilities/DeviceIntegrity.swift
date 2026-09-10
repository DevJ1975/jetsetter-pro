// File: Core/Utilities/DeviceIntegrity.swift
//
// Best-effort jailbreak / compromised-OS heuristics. This is advisory only — it
// MUST NOT hard-block the app: these checks produce false positives and can be
// defeated, so treat a positive result as a signal to warn the user (e.g. before
// showing the encrypted document Vault), not to deny access.
//
// The Keychain (`.whenUnlockedThisDeviceOnly`) and VaultCrypto AES-256 protect
// data under an intact OS sandbox; on a jailbroken device those guarantees are
// weaker, so surfacing an advisory is the appropriate response.

import Foundation

enum DeviceIntegrity {

    /// True when the device shows signs of being jailbroken / sandbox-escaped.
    /// Always false on the Simulator (some paths below exist there legitimately).
    /// Safe to call from any isolation context (no UIKit / main-actor deps).
    static var isCompromised: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return hasSuspiciousPaths() || canWriteOutsideSandbox()
        #endif
    }

    #if !targetEnvironment(simulator)
    /// Files/dirs that commonly exist only on jailbroken devices.
    private static func hasSuspiciousPaths() -> Bool {
        let paths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/usr/sbin/sshd",
            "/usr/bin/ssh",
            "/bin/bash",
            "/etc/apt",
            "/private/var/lib/apt"
        ]
        let fm = FileManager.default
        return paths.contains { fm.fileExists(atPath: $0) }
    }

    /// A sandboxed app cannot write outside its container; success implies escape.
    private static func canWriteOutsideSandbox() -> Bool {
        let probe = "/private/jailbreak_probe.txt"
        do {
            try "probe".write(toFile: probe, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: probe)
            return true
        } catch {
            return false
        }
    }
    #endif
}
