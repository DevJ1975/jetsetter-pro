// File: Core/Utilities/BiometryLabel.swift
//
// The words and SF Symbol for "how this device unlocks", so security screens
// never hard-code Face ID. The foldable iPhone Ultra uses Touch ID in the side
// button, Vision Pro uses Optic ID, and a device with no biometrics enrolled
// falls back to its passcode. The vault used to show a `faceid` glyph and
// "Face ID or Touch ID" copy on every device, which reads as broken on a Touch
// ID phone.
//
// `LAContext.biometryType` is only filled in after `canEvaluatePolicy` runs, and
// it reports the *hardware* even when nothing is enrolled. So `current()` asks
// whether biometrics can actually be used right now; if not (not enrolled,
// locked out after too many attempts), the system will ask for the passcode,
// and the label says so. The mapping itself is pure so it can be unit-tested
// without a device.

import LocalAuthentication

nonisolated struct BiometryLabel: Equatable, Sendable {

    enum Method: Equatable, Sendable {
        case faceID
        case touchID
        case opticID
        case passcode
    }

    let method: Method

    /// Maps the hardware biometry type. `.none` (no biometric hardware) means
    /// the device passcode is what unlocks.
    init(biometryType: LABiometryType) {
        switch biometryType {
        case .faceID:  method = .faceID
        case .touchID: method = .touchID
        case .opticID: method = .opticID
        case .none:    method = .passcode
        @unknown default:
            // A future biometric we don't have copy for: "passcode" is never
            // wrong, because `.deviceOwnerAuthentication` always allows it.
            method = .passcode
        }
    }

    /// The label for what the system will actually prompt for: the biometric
    /// only when it can be evaluated now, otherwise the passcode.
    init(biometryType: LABiometryType, canUseBiometrics: Bool) {
        self.init(biometryType: canUseBiometrics ? biometryType : .none)
    }

    /// Reads the current device. Cheap; call it when a screen appears rather
    /// than caching it, since the traveler can enrol or remove biometrics in
    /// Settings while the app is suspended.
    static func current() -> BiometryLabel {
        let context = LAContext()
        var error: NSError?
        let canUse = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return BiometryLabel(biometryType: context.biometryType, canUseBiometrics: canUse)
    }

    /// Title-case name for buttons and headings: "Face ID", "Passcode".
    var name: String {
        switch method {
        case .faceID:   return "Face ID"
        case .touchID:  return "Touch ID"
        case .opticID:  return "Optic ID"
        case .passcode: return "Passcode"
        }
    }

    /// Mid-sentence form: "Use Face ID to…" / "Use your passcode to…".
    var phrase: String {
        method == .passcode ? "your passcode" : name
    }

    /// SF Symbol for the unlock method. `touchid` needs iOS 14 and `opticid`
    /// iOS 17, both below the deployment target.
    var systemImage: String {
        switch method {
        case .faceID:   return "faceid"
        case .touchID:  return "touchid"
        case .opticID:  return "opticid"
        case .passcode: return "lock.fill"
        }
    }

    /// Button title: "Unlock with Touch ID".
    var unlockTitle: String { "Unlock with \(name)" }

    /// What to tell someone who can't authenticate at all (no passcode set).
    /// Build the label with `init(biometryType:)` from the hardware type for
    /// this, so a Touch ID phone is told to set up Touch ID, never Face ID.
    var setupHint: String {
        method == .passcode
            ? "Set a device passcode"
            : "Set up \(name) or a device passcode"
    }
}
