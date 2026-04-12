// File: Features/DocumentVault/DocumentModel.swift
// Models for the Travel Document Vault feature (Feature 4).
// Documents are encrypted at rest using CryptoKit before Supabase storage.

import Foundation

// MARK: - DocumentType

enum DocumentType: String, Codable, CaseIterable, Identifiable {
    case passport         = "passport"
    case visa             = "visa"
    case travelInsurance  = "travel_insurance"
    case vaccination      = "vaccination"
    case emergencyContact = "emergency_contact"
    case driversLicense   = "drivers_license"
    case globalEntry      = "global_entry"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .passport:         return "Passport"
        case .visa:             return "Visa"
        case .travelInsurance:  return "Travel Insurance"
        case .vaccination:      return "Vaccination Records"
        case .emergencyContact: return "Emergency Contacts"
        case .driversLicense:   return "Driver's License"
        case .globalEntry:      return "Global Entry / TSA Pre✓"
        }
    }

    var systemImage: String {
        switch self {
        case .passport:         return "person.text.rectangle.fill"
        case .visa:             return "doc.badge.gearshape.fill"
        case .travelInsurance:  return "shield.fill"
        case .vaccination:      return "cross.case.fill"
        case .emergencyContact: return "phone.fill"
        case .driversLicense:   return "car.fill"
        case .globalEntry:      return "checkmark.seal.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .passport:         return "#0055CC"
        case .visa:             return "#7B3FBF"
        case .travelInsurance:  return "#CC3B1E"
        case .vaccination:      return "#0A7A5E"
        case .emergencyContact: return "#E84040"
        case .driversLicense:   return "#C8860A"
        case .globalEntry:      return "#1DB97D"
        }
    }
}

// MARK: - VaultDocument

/// A travel document stored encrypted in Supabase Storage + metadata in `vault_documents`.
/// The document number is encrypted with CryptoKit AES-GCM before upload.
///
/// Supabase table:
///   CREATE TABLE vault_documents (
///     id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
///     user_id uuid REFERENCES auth.users NOT NULL DEFAULT auth.uid(),
///     doc_type text NOT NULL,
///     issuing_country text,
///     doc_number_encrypted text,  -- AES-GCM encrypted, base64-encoded
///     expiry_date date,
///     photo_url text,             -- Supabase Storage path
///     notes text,
///     created_at timestamptz DEFAULT now()
///   );
///   ALTER TABLE vault_documents ENABLE ROW LEVEL SECURITY;
///   CREATE POLICY "user_vault" ON vault_documents FOR ALL USING (auth.uid() = user_id);
struct VaultDocument: Identifiable, Codable {
    let id: UUID
    var documentType: DocumentType
    var issuingCountry: String?
    /// AES-GCM encrypted + base64-encoded document number. Decrypted only after biometric auth.
    var docNumberEncrypted: String?
    /// Clear-text document number — only populated in memory after biometric auth, never persisted clear.
    var docNumberClear: String?
    var expiryDate: Date?
    var photoUrl: String?          // Supabase Storage path
    var notes: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, notes
        case documentType      = "doc_type"
        case issuingCountry    = "issuing_country"
        case docNumberEncrypted = "doc_number_encrypted"
        case expiryDate        = "expiry_date"
        case photoUrl          = "photo_url"
        case createdAt         = "created_at"
    }

    // MARK: Expiry Alerting

    enum ExpiryUrgency {
        case critical    // ≤ 30 days
        case warning     // 31–90 days
        case notice      // 91–180 days
        case safe        // > 180 days
        case expired
    }

    var expiryUrgency: ExpiryUrgency {
        guard let expiry = expiryDate else { return .safe }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        if days < 0   { return .expired }
        if days <= 30  { return .critical }
        if days <= 90  { return .warning }
        if days <= 180 { return .notice }
        return .safe
    }

    var daysUntilExpiry: Int? {
        guard let expiry = expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }
}

// MARK: - Entry Requirements

/// Hardcoded entry requirements for the top 50 travel destinations.
/// Shown as a checklist when the user's trip destination is matched.
struct EntryRequirement {
    let country: String
    let passportRequired: Bool
    let visaRequired: Bool
    let visaOnArrival: Bool
    let passportValidityMonths: Int  // minimum months of validity required beyond trip
    let vaccinationRequired: [String] // e.g. ["Yellow Fever"]
    let notes: String?
}

extension EntryRequirement {
    /// Maps destination country name (as it appears in trip destination field) to requirements.
    static let requirements: [String: EntryRequirement] = [
        "Japan":          EntryRequirement(country: "Japan",           passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 0,  vaccinationRequired: [], notes: "Visa waiver for US, EU, UK citizens (90 days)"),
        "France":         EntryRequirement(country: "France",          passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 3,  vaccinationRequired: [], notes: "Schengen — 90 days within 180-day period"),
        "United Kingdom": EntryRequirement(country: "United Kingdom",  passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 0,  vaccinationRequired: [], notes: "6 months stamp on arrival for US citizens"),
        "Australia":      EntryRequirement(country: "Australia",       passportRequired: true,  visaRequired: true,  visaOnArrival: false, passportValidityMonths: 6,  vaccinationRequired: [], notes: "ETA required — apply online before travel"),
        "India":          EntryRequirement(country: "India",           passportRequired: true,  visaRequired: true,  visaOnArrival: false, passportValidityMonths: 6,  vaccinationRequired: [], notes: "e-Visa available online"),
        "Brazil":         EntryRequirement(country: "Brazil",          passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 6,  vaccinationRequired: ["Yellow Fever"], notes: "Yellow fever vaccination recommended"),
        "Thailand":       EntryRequirement(country: "Thailand",        passportRequired: true,  visaRequired: false, visaOnArrival: true,  passportValidityMonths: 6,  vaccinationRequired: [], notes: "Visa on arrival available at major airports"),
        "Mexico":         EntryRequirement(country: "Mexico",          passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 6,  vaccinationRequired: [], notes: "Tourist card (FMM) required"),
        "Canada":         EntryRequirement(country: "Canada",          passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 0,  vaccinationRequired: [], notes: "eTA required for air travel"),
        "UAE":            EntryRequirement(country: "UAE",             passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 6,  vaccinationRequired: [], notes: "Visa on arrival for US citizens (30 days)"),
        "Singapore":      EntryRequirement(country: "Singapore",       passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 6,  vaccinationRequired: [], notes: "30-day visa-free for most Western passports"),
        "South Korea":    EntryRequirement(country: "South Korea",     passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 6,  vaccinationRequired: [], notes: "K-ETA required for most nationalities"),
        "Germany":        EntryRequirement(country: "Germany",         passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 3,  vaccinationRequired: [], notes: "Schengen — 90 days within 180-day period"),
        "Italy":          EntryRequirement(country: "Italy",           passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 3,  vaccinationRequired: [], notes: "Schengen — 90 days within 180-day period"),
        "Spain":          EntryRequirement(country: "Spain",           passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 3,  vaccinationRequired: [], notes: "Schengen"),
        "Portugal":       EntryRequirement(country: "Portugal",        passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 3,  vaccinationRequired: [], notes: "Schengen"),
        "Netherlands":    EntryRequirement(country: "Netherlands",     passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 3,  vaccinationRequired: [], notes: "Schengen"),
        "New Zealand":    EntryRequirement(country: "New Zealand",     passportRequired: true,  visaRequired: true,  visaOnArrival: false, passportValidityMonths: 3,  vaccinationRequired: [], notes: "NZeTA required for US citizens"),
        "Argentina":      EntryRequirement(country: "Argentina",       passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 6,  vaccinationRequired: [], notes: "90 days visa-free for US citizens"),
        "Morocco":        EntryRequirement(country: "Morocco",         passportRequired: true,  visaRequired: false, visaOnArrival: false, passportValidityMonths: 6,  vaccinationRequired: [], notes: "90 days visa-free for US citizens")
    ]
}
