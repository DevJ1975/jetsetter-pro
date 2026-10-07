// File: JetSetter ProTests/TravelerValidationTests.swift
//
// The traveler form's acceptance rules. What the airline receives is what these
// let through, so they pin the cases that cost travelers money or boarding:
// a phone number without a country code, a defaulted title, a passport asked
// for when the fare doesn't need one, and one contact shared across travelers.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct TravelerValidationTests {

    // MARK: - Fixtures

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private var now: Date { ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z") ?? Date() }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "T12:00:00Z") ?? Date() }

    private func validForm(id: String = "pas_1", type: String = "adult") -> TravelerForm {
        var form = TravelerForm(id: id, type: type)
        form.title = "mr"
        form.givenName = "Ada"
        form.familyName = "Lovelace"
        form.gender = "f"
        form.bornOn = date("1990-12-10")
        form.email = "ada@example.com"
        form.phone = "+1 (415) 555-0123"
        return form
    }

    private func offer(passengers: Int = 1, documents: Bool = false) throws -> BackendOffer {
        var offer = try BackendFixtures.decode(BackendOffer.self, BackendFixtures.offer)
        offer.passengers = (1...passengers).map { BackendOfferPassenger(id: "pas_\($0)", type: "adult") }
        offer.requiresIdentityDocuments = documents
        return offer
    }

    // MARK: - Fields

    @Test func phoneNumbersMustCarryACountryCodeAndNormaliseToE164() {
        #expect(TravelerValidation.normalizedPhone("+1 (415) 555-0123") == "+14155550123")
        #expect(TravelerValidation.normalizedPhone("+44 20 7946 0958") == "+442079460958")
        #expect(TravelerValidation.normalizedPhone("0044 20 7946 0958") == "+442079460958")
        #expect(TravelerValidation.normalizedPhone("+81.3.1234.5678") == "+81312345678")
        // No country code: refused rather than guessed.
        #expect(TravelerValidation.normalizedPhone("415 555 0123") == nil)
        #expect(TravelerValidation.normalizedPhone("(415) 555-0123") == nil)
        #expect(TravelerValidation.normalizedPhone("+0123456789") == nil)
        #expect(TravelerValidation.normalizedPhone("+1415") == nil)
        #expect(TravelerValidation.normalizedPhone("+1415555012345678") == nil)
        #expect(TravelerValidation.normalizedPhone("+1415abc0123") == nil)
        #expect(TravelerValidation.normalizedPhone("") == nil)
    }

    @Test func emailsNeedAnAtSignAndADomain() {
        #expect(TravelerValidation.isValidEmail("ada@example.com"))
        #expect(TravelerValidation.isValidEmail("  ada.lovelace+trips@mail.example.co.uk "))
        #expect(!TravelerValidation.isValidEmail("ada@example"))
        #expect(!TravelerValidation.isValidEmail("ada example.com"))
        #expect(!TravelerValidation.isValidEmail("@example.com"))
        #expect(!TravelerValidation.isValidEmail(""))
    }

    @Test func namesAcceptRealPassportNamesAndRejectJunk() {
        for name in ["Ada", "Mary-Jane", "O'Brien", "O’Brien", "José", "Nguyễn", "Müller", "Jean Luc", "Zhang", "Dr."] {
            #expect(TravelerValidation.isValidName(name), "\(name) should be accepted")
        }
        for name in ["", "   ", "R2D2", "Ada!", "12345", "-", String(repeating: "A", count: 61)] {
            #expect(!TravelerValidation.isValidName(name), "\(name) should be rejected")
        }
    }

    @Test func passportNumbersAndCountries() {
        #expect(TravelerValidation.isValidPassportNumber("X1234567"))
        #expect(TravelerValidation.isValidPassportNumber(" 123456789 "))
        #expect(!TravelerValidation.isValidPassportNumber("AB1"))
        #expect(!TravelerValidation.isValidPassportNumber("AB-123456"))
        #expect(TravelerValidation.isValidCountryCode("US"))
        #expect(TravelerValidation.isValidCountryCode(" gb "))
        #expect(!TravelerValidation.isValidCountryCode("USA"))
        #expect(!TravelerValidation.isValidCountryCode("U"))
        #expect(!TravelerValidation.isValidCountryCode(""))
    }

    // MARK: - Dates of birth

    @Test func birthDatesAreCheckedAgainstWhatIsCertain() {
        func issue(_ iso: String, type: String? = "adult") -> String? {
            TravelerValidation.birthDateIssue(date(iso), type: type, now: now, calendar: calendar)
        }
        #expect(issue("1990-12-10") == nil)
        #expect(issue("2027-01-01") != nil)                    // future
        #expect(issue("1890-01-01") != nil)                    // mistyped year
        #expect(issue("2020-01-01", type: "adult") != nil)     // a child booked as an adult
        #expect(issue("2018-01-01", type: "child") == nil)
        #expect(issue("2000-01-01", type: "child") != nil)     // an adult booked as a child
        #expect(issue("2026-03-01", type: "infant_without_seat") == nil)
        #expect(issue("2022-01-01", type: "infant_without_seat") != nil)
    }

    // MARK: - Whole form

    @Test func aCompleteFormIsValid() throws {
        let result = TravelerValidation.validateAll([validForm()], offer: try offer(), now: now, calendar: calendar)
        #expect(result.isValid)
        let input = try #require(result.inputs?.first)
        #expect(input.id == "pas_1")
        #expect(input.title == "mr")
        #expect(input.givenName == "Ada")
        #expect(input.familyName == "Lovelace")
        #expect(input.bornOn == BackendDates.dateOnlyString(date("1990-12-10")))
        #expect(input.gender == "f")
        #expect(input.email == "ada@example.com")
        #expect(input.phoneNumber == "+14155550123")
        #expect(input.identityDocuments == nil)
    }

    /// A silent default of "Mr" or "Male" is an error the airline charges to fix.
    @Test func titleGenderAndBirthDateMustBeChosenOnPurpose() throws {
        var form = validForm()
        form.title = ""
        form.gender = ""
        form.bornOn = nil
        let problems = TravelerValidation.issues(for: form, lead: nil, requiresDocuments: false,
                                                 travelEnd: nil, now: now, calendar: calendar)
        #expect(problems[.title] != nil)
        #expect(problems[.gender] != nil)
        #expect(problems[.bornOn] != nil)
        #expect(problems[.givenName] == nil)
    }

    @Test func passportDetailsAreOnlyAskedForWhenTheFareNeedsThem() throws {
        let form = validForm()
        let withoutDocs = TravelerValidation.validateAll([form], offer: try offer(documents: false), now: now, calendar: calendar)
        #expect(withoutDocs.isValid)

        let missing = TravelerValidation.validateAll([form], offer: try offer(documents: true), now: now, calendar: calendar)
        #expect(!missing.isValid)
        let problems = try #require(missing.issues[0])
        #expect(problems[.passportNumber] != nil)
        #expect(problems[.passportCountry] != nil)
        #expect(problems[.passportExpiry] != nil)

        var complete = form
        complete.passportNumber = "x123 4567".replacingOccurrences(of: " ", with: "")
        complete.passportCountry = "us"
        complete.passportExpiry = date("2032-01-01")
        let ok = TravelerValidation.validateAll([complete], offer: try offer(documents: true), now: now, calendar: calendar)
        #expect(ok.isValid)
        let document = try #require(ok.inputs?.first?.identityDocuments?.first)
        #expect(document.type == "passport")
        #expect(document.uniqueIdentifier == "X1234567")
        #expect(document.issuingCountryCode == "US")
    }

    @Test func aPassportMustOutliveTheTrip() throws {
        var form = validForm()
        form.passportNumber = "X1234567"
        form.passportCountry = "US"
        form.passportExpiry = date("2026-12-01")
        let beforeReturn = TravelerValidation.issues(
            for: form, lead: nil, requiresDocuments: true, travelEnd: date("2027-01-15"), now: now, calendar: calendar)
        #expect(beforeReturn[.passportExpiry] != nil)
        let afterReturn = TravelerValidation.issues(
            for: form, lead: nil, requiresDocuments: true, travelEnd: date("2026-11-20"), now: now, calendar: calendar)
        #expect(afterReturn[.passportExpiry] == nil)
    }

    @Test func extraTravelersCanShareTheLeadsContactOrUseTheirOwn() throws {
        var lead = validForm(id: "pas_1")
        lead.email = "lead@example.com"
        lead.phone = "+14155550123"

        var guest = validForm(id: "pas_2")
        guest.givenName = "Charles"
        guest.email = ""
        guest.phone = ""
        guest.sharesLeadContact = true

        let shared = TravelerValidation.validateAll([lead, guest], offer: try offer(passengers: 2), now: now, calendar: calendar)
        #expect(shared.isValid)
        let guestInput = try #require(shared.inputs?[1])
        #expect(guestInput.email == "lead@example.com")
        #expect(guestInput.phoneNumber == "+14155550123")
        #expect(guestInput.id == "pas_2")

        guest.sharesLeadContact = false
        let own = TravelerValidation.validateAll([lead, guest], offer: try offer(passengers: 2), now: now, calendar: calendar)
        #expect(!own.isValid)
        #expect(own.issues[1]?[.email] != nil)
        #expect(own.issues[1]?[.phone] != nil)
        #expect(own.issues[0] == nil)
    }

    @Test func theFormMustMatchThePassengersThatWerePriced() throws {
        let result = TravelerValidation.validateAll([validForm()], offer: try offer(passengers: 2), now: now, calendar: calendar)
        #expect(!result.isValid)
        #expect(result.inputs == nil)
    }

    @Test func inputIsTrimmedBeforeItIsSent() throws {
        var form = validForm()
        form.givenName = "  Ada "
        form.familyName = " Lovelace  "
        form.email = "  ada@example.com "
        let input = try #require(TravelerValidation.validateAll([form], offer: try offer(), now: now, calendar: calendar).inputs?.first)
        #expect(input.givenName == "Ada")
        #expect(input.familyName == "Lovelace")
        #expect(input.email == "ada@example.com")
    }

    // MARK: - Form lifecycle

    @Test func formsFollowTheOffersPassengersAndSurviveARefresh() throws {
        let twoPassengers = try offer(passengers: 2)
        var forms = TravelerForm.forms(for: twoPassengers)
        #expect(forms.map(\.id) == ["pas_1", "pas_2"])
        forms[0].givenName = "Ada"

        // The price check returns a fresh offer with new passenger ids.
        var refreshed = twoPassengers
        refreshed.passengers = [BackendOfferPassenger(id: "pas_NEW1", type: "adult"),
                                BackendOfferPassenger(id: "pas_NEW2", type: "child")]
        let reconciled = TravelerForm.reconcile(existing: forms, with: refreshed)
        #expect(reconciled.map(\.id) == ["pas_NEW1", "pas_NEW2"])
        #expect(reconciled[0].givenName == "Ada")
        #expect(reconciled[1].type == "child")
    }

    @Test func headingsNameEachTraveler() {
        #expect(TravelerForm.heading(index: 0, type: "adult") == "Adult 1")
        #expect(TravelerForm.heading(index: 1, type: "child") == "Child 2")
        #expect(TravelerForm.heading(index: 2, type: "infant_without_seat") == "Infant 3")
        #expect(TravelerForm.heading(index: 0, type: nil) == "Adult 1")
    }
}
