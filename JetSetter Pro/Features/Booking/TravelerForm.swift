// File: Features/Booking/TravelerForm.swift
//
// The traveler details a flight booking needs, and the rules for accepting
// them. Pure value types so every rule is testable without a view.
//
// What the airline needs, and why the form is strict about it:
//  * Names must match the passport or ID exactly. A typo can mean a re-issue fee
//    or a denied boarding, so the form never autofills a name from the profile.
//  * Title and gender are chosen by the traveler, never defaulted. A silent
//    "Mr" on a ticket for a woman is an error the airline charges to fix.
//  * Phone numbers are E.164 ("+14155550123") because that is what the airline
//    uses to reach the traveler about a cancellation or gate change.
//  * Passport details are collected ONLY when the offer says
//    `requires_identity_documents`. The app never asks for more than the fare
//    needs (App Store guideline 5.1.1).
//
// The form holds nothing on disk. Details go to the server in the checkout
// request and nowhere else.

import Foundation

// MARK: - Fields

nonisolated enum TravelerField: Hashable, Sendable {
    case title, givenName, familyName, bornOn, gender, email, phone
    case passportNumber, passportCountry, passportExpiry
}

// MARK: - Form

nonisolated struct TravelerForm: Identifiable, Equatable, Sendable {
    /// Duffel's passenger id from the offer; echoed on checkout.
    var id: String
    /// "adult", "child" or "infant_without_seat".
    var type: String?

    /// mr | mrs | ms | miss | dr; empty until chosen.
    var title = ""
    var givenName = ""
    var familyName = ""
    var bornOn: Date?
    /// m | f; empty until chosen.
    var gender = ""
    var email = ""
    var phone = ""
    /// For travelers after the first: reuse the lead traveler's email and phone.
    var sharesLeadContact = true

    var passportNumber = ""
    /// ISO 3166-1 alpha-2, e.g. "US".
    var passportCountry = ""
    var passportExpiry: Date?

    init(id: String, type: String? = nil) {
        self.id = id
        self.type = type
    }

    /// One blank form per passenger on the offer.
    static func forms(for offer: BackendOffer) -> [TravelerForm] {
        offer.passengers.map { TravelerForm(id: $0.id, type: $0.type) }
    }

    /// Keeps what the traveler already typed when the offer is refreshed (the
    /// price check can change the offer); passengers are matched by position
    /// and take the new ids Duffel issued.
    static func reconcile(existing: [TravelerForm], with offer: BackendOffer) -> [TravelerForm] {
        offer.passengers.enumerated().map { index, passenger in
            var form = index < existing.count ? existing[index] : TravelerForm(id: passenger.id)
            form.id = passenger.id
            form.type = passenger.type
            return form
        }
    }

    /// "Adult 1", "Child 2": the label a traveler sees above each block.
    static func heading(index: Int, type: String?) -> String {
        let kind: String
        switch type {
        case "child":               kind = "Child"
        case "infant_without_seat": kind = "Infant"
        default:                    kind = "Adult"
        }
        return "\(kind) \(index + 1)"
    }
}

// MARK: - Choices

/// A value the API accepts and the label a traveler picks.
nonisolated struct TravelerChoice: Identifiable, Equatable, Sendable {
    let code: String
    let label: String
    var id: String { code }
}

// MARK: - Validation

nonisolated enum TravelerValidation {

    static let titles: [TravelerChoice] = [
        TravelerChoice(code: "mr", label: "Mr"), TravelerChoice(code: "mrs", label: "Mrs"),
        TravelerChoice(code: "ms", label: "Ms"), TravelerChoice(code: "miss", label: "Miss"),
        TravelerChoice(code: "dr", label: "Dr")
    ]

    static let genders: [TravelerChoice] = [
        TravelerChoice(code: "m", label: "Male"), TravelerChoice(code: "f", label: "Female")
    ]

    /// The oldest birth date accepted. Anything older is a mistyped year.
    static let maximumAgeYears = 120

    // MARK: Single-field rules

    /// Letters from any alphabet, plus spaces, hyphens, apostrophes and dots.
    static func isValidName(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { return false }
        let allowedMarks = CharacterSet(charactersIn: " -'’.")
        let letters = CharacterSet.letters.union(.nonBaseCharacters)
        var sawLetter = false
        for scalar in name.unicodeScalars {
            if CharacterSet.letters.contains(scalar) { sawLetter = true; continue }
            guard letters.contains(scalar) || allowedMarks.contains(scalar) else { return false }
        }
        return sawLetter
    }

    static func isValidEmail(_ raw: String) -> Bool {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, options: .regularExpression) != nil
    }

    /// An E.164 number ("+14155550123") from what was typed, or nil. Accepts
    /// spaces, dashes, dots and parentheses, and a leading "00" for "+". A
    /// number without a country code is rejected rather than guessed, because
    /// a wrong guess sends the airline's cancellation text to a stranger.
    static func normalizedPhone(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.filter { !" -().\u{00A0}".contains($0) }
        if text.hasPrefix("00") { text = "+" + text.dropFirst(2) }
        guard text.range(of: #"^\+[1-9][0-9]{6,14}$"#, options: .regularExpression) != nil else { return nil }
        return text
    }

    static func isValidPassportNumber(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(of: #"^[A-Za-z0-9]{5,20}$"#, options: .regularExpression) != nil
    }

    static func isValidCountryCode(_ raw: String) -> Bool {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else { return false }
        return Locale.Region.isoRegions.contains { $0.identifier == code }
    }

    // MARK: Whole-form validation

    /// Problems with one traveler's details, keyed by field. Empty means valid.
    /// `lead` supplies email and phone for a traveler who shares them.
    static func issues(
        for form: TravelerForm, lead: TravelerForm?, requiresDocuments: Bool,
        travelEnd: Date?, now: Date = Date(), calendar: Calendar = .current
    ) -> [TravelerField: String] {
        var problems: [TravelerField: String] = [:]

        if !titles.contains(where: { $0.code == form.title }) { problems[.title] = "Choose a title." }
        if !isValidName(form.givenName) { problems[.givenName] = "Enter the first name exactly as on the passport or ID." }
        if !isValidName(form.familyName) { problems[.familyName] = "Enter the last name exactly as on the passport or ID." }
        if !genders.contains(where: { $0.code == form.gender }) { problems[.gender] = "Choose the gender shown on the passport or ID." }

        if let born = form.bornOn {
            if let message = birthDateIssue(born, type: form.type, now: now, calendar: calendar) {
                problems[.bornOn] = message
            }
        } else {
            problems[.bornOn] = "Choose a date of birth."
        }

        let contact = (form.sharesLeadContact ? lead : nil) ?? form
        if !isValidEmail(contact.email) { problems[.email] = "Enter a valid email address." }
        if normalizedPhone(contact.phone) == nil {
            problems[.phone] = "Enter the phone number with its country code, like +1 415 555 0123."
        }

        if requiresDocuments {
            if !isValidPassportNumber(form.passportNumber) {
                problems[.passportNumber] = "Enter the passport number (letters and digits only)."
            }
            if !isValidCountryCode(form.passportCountry) {
                problems[.passportCountry] = "Choose the country that issued the passport."
            }
            if let expiry = form.passportExpiry {
                let floor = max(travelEnd ?? now, now)
                if expiry <= floor { problems[.passportExpiry] = "The passport must still be valid after your trip." }
            } else {
                problems[.passportExpiry] = "Choose the passport expiry date."
            }
        }
        return problems
    }

    /// Why a birth date can't be right, or nil. Checks only what is certain
    /// today; the airline does the exact age-at-travel check.
    static func birthDateIssue(_ born: Date, type: String?, now: Date, calendar: Calendar) -> String? {
        if born > now { return "The date of birth can't be in the future." }
        guard let age = calendar.dateComponents([.year], from: born, to: now).year else { return nil }
        if age > maximumAgeYears { return "Check the year of birth." }
        switch type {
        case "infant_without_seat":
            if age >= 2 { return "Infants must be under 2. Add this traveler as a child or adult." }
        case "child":
            if age >= 18 { return "This traveler is booked as a child but is 18 or older." }
        default:
            if age < 12 { return "Adult travelers must be at least 12." }
        }
        return nil
    }

    struct Result: Equatable, Sendable {
        /// Traveler index -> field -> message.
        var issues: [Int: [TravelerField: String]]
        /// The checkout passengers; nil unless everything is valid.
        var inputs: [BackendPassengerInput]?
        var isValid: Bool { issues.isEmpty }
    }

    /// Validates every traveler and builds the checkout passengers.
    static func validateAll(
        _ forms: [TravelerForm], offer: BackendOffer,
        travelEnd: Date? = nil, now: Date = Date(), calendar: Calendar = .current
    ) -> Result {
        var allIssues: [Int: [TravelerField: String]] = [:]
        let lead = forms.first

        if forms.count != offer.passengers.count {
            // The form must have exactly the passengers the offer prices.
            allIssues[0] = [.givenName: "The number of travelers doesn't match the fare. Go back and try again."]
        }
        for (index, form) in forms.enumerated() {
            let found = issues(for: form, lead: index == 0 ? nil : lead,
                               requiresDocuments: offer.requiresIdentityDocuments,
                               travelEnd: travelEnd, now: now, calendar: calendar)
            if !found.isEmpty { allIssues[index] = found }
        }
        guard allIssues.isEmpty else { return Result(issues: allIssues, inputs: nil) }

        let inputs = forms.enumerated().compactMap { index, form in
            passengerInput(form, lead: index == 0 ? nil : lead, requiresDocuments: offer.requiresIdentityDocuments)
        }
        guard inputs.count == forms.count else {
            return Result(issues: [0: [.givenName: "Check the traveler details."]], inputs: nil)
        }
        return Result(issues: [:], inputs: inputs)
    }

    /// One traveler as the checkout API wants them. Nil if anything is missing
    /// (callers validate first).
    static func passengerInput(_ form: TravelerForm, lead: TravelerForm?, requiresDocuments: Bool) -> BackendPassengerInput? {
        let contact = (form.sharesLeadContact ? lead : nil) ?? form
        guard let born = form.bornOn, let phone = normalizedPhone(contact.phone) else { return nil }

        var documents: [BackendIdentityDocument]?
        if requiresDocuments {
            guard let expiry = form.passportExpiry else { return nil }
            documents = [BackendIdentityDocument(
                type: "passport",
                uniqueIdentifier: form.passportNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                issuingCountryCode: form.passportCountry.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                expiresOn: BackendDates.dateOnlyString(expiry)
            )]
        }
        return BackendPassengerInput(
            id: form.id,
            title: form.title,
            givenName: form.givenName.trimmingCharacters(in: .whitespacesAndNewlines),
            familyName: form.familyName.trimmingCharacters(in: .whitespacesAndNewlines),
            bornOn: BackendDates.dateOnlyString(born),
            gender: form.gender,
            email: contact.email.trimmingCharacters(in: .whitespacesAndNewlines),
            phoneNumber: phone,
            identityDocuments: documents
        )
    }
}

// MARK: - Search request

nonisolated enum BackendCabinClass: String, CaseIterable, Identifiable, Sendable {
    case economy
    case premiumEconomy = "premium_economy"
    case business
    case first

    var id: String { rawValue }

    var label: String {
        switch self {
        case .economy:        return "Economy"
        case .premiumEconomy: return "Premium Economy"
        case .business:       return "Business"
        case .first:          return "First"
        }
    }
}

nonisolated enum FlightSearchRequestBuilder {

    /// The backend search for the form's inputs, or nil when the route isn't
    /// usable (the form's own validation shows the message).
    static func make(from params: FlightSearchParams) -> BackendSearchRequest? {
        let origin = params.originCode
        let destination = params.destinationCode
        guard origin.count == 3, destination.count == 3, origin != destination else { return nil }

        var slices = [BackendSearchSlice(origin: origin, destination: destination,
                                         departureDate: BackendDates.dateOnlyString(params.departDate))]
        if params.tripType == .roundTrip {
            slices.append(BackendSearchSlice(origin: destination, destination: origin,
                                             departureDate: BackendDates.dateOnlyString(params.returnDate)))
        }
        return BackendSearchRequest(
            slices: slices,
            passengers: BackendSearchPassengers(adults: min(max(params.adults, 1), 9), children: 0, infants: 0),
            cabinClass: params.cabinClass.rawValue
        )
    }
}
