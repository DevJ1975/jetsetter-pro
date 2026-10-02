// File: JetSetter ProTests/BiometryLabelTests.swift
//
// Security screens describe how the device unlocks from `LAContext`'s
// biometry type instead of hard-coding Face ID. The foldable iPhone Ultra has
// Touch ID, so a vault that says "Face ID" there reads as broken. The mapping
// is pure, so it is tested here without a device or a prompt.

import Testing
import LocalAuthentication
@testable import JetSetter_Pro

@Suite struct BiometryLabelTests {

    /// Defect: the Document Vault showed the `faceid` glyph and "Face ID or
    /// Touch ID" copy on every device, including Touch ID phones such as the
    /// iPhone Ultra.
    @Test func aTouchIDPhoneIsLabelledTouchIDNeverFaceID() {
        let label = BiometryLabel(biometryType: .touchID)
        #expect(label.method == .touchID)
        #expect(label.name == "Touch ID")
        #expect(label.systemImage == "touchid")
        #expect(label.unlockTitle == "Unlock with Touch ID")
        #expect(!label.setupHint.contains("Face ID"))
    }

    @Test func aFaceIDPhoneIsLabelledFaceID() {
        let label = BiometryLabel(biometryType: .faceID)
        #expect(label.method == .faceID)
        #expect(label.name == "Face ID")
        #expect(label.systemImage == "faceid")
    }

    @Test func anOpticIDDeviceIsLabelledOpticID() {
        let label = BiometryLabel(biometryType: .opticID)
        #expect(label.method == .opticID)
        #expect(label.name == "Optic ID")
        #expect(label.systemImage == "opticid")
    }

    @Test func noBiometricHardwareMeansThePasscode() {
        let label = BiometryLabel(biometryType: .none)
        #expect(label.method == .passcode)
        #expect(label.name == "Passcode")
        #expect(label.phrase == "your passcode")
        #expect(label.systemImage == "lock.fill")
        #expect(label.setupHint == "Set a device passcode")
    }

    /// Hardware that isn't enrolled, or is locked out after failed attempts,
    /// gets the passcode prompt from `.deviceOwnerAuthentication`, so the
    /// label must say passcode too.
    @Test func biometricsThatCantBeUsedRightNowAreLabelledAsThePasscode() {
        let label = BiometryLabel(biometryType: .touchID, canUseBiometrics: false)
        #expect(label.method == .passcode)
        #expect(label.unlockTitle == "Unlock with Passcode")
    }

    @Test func usableBiometricsKeepTheirOwnName() {
        let label = BiometryLabel(biometryType: .faceID, canUseBiometrics: true)
        #expect(label.method == .faceID)
        #expect(label.phrase == "Face ID")
    }

    @Test func theSetupHintNamesTheHardwareTheTravelerActuallyHas() {
        #expect(BiometryLabel(biometryType: .touchID).setupHint == "Set up Touch ID or a device passcode")
        #expect(BiometryLabel(biometryType: .faceID).setupHint == "Set up Face ID or a device passcode")
    }
}
