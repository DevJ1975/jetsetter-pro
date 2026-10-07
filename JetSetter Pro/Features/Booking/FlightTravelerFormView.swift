// File: Features/Booking/FlightTravelerFormView.swift
//
// Traveler details and the review/pay step of the in-app flight flow.
//
// One block per passenger on the offer (Duffel prices exactly the passengers
// that were searched, so the form has exactly that many). Validation lives in
// `TravelerValidation`; this file only shows what it finds, under the field it
// belongs to, so a typo is fixed where it is rather than in an alert.
//
// Passport fields appear only when the offer says `requires_identity_documents`.
// Nothing typed here is stored on the phone; it goes to the server in the
// checkout request.

import SwiftUI

// MARK: - Traveler form

struct FlightTravelerFormView: View {

    @Bindable var model: FlightBookingModel

    var body: some View {
        Form {
            if model.isTestMode {
                Section { TestModeBanner() }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            if !model.issues.isEmpty {
                Section {
                    Label("Some details need attention. They are marked below.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(JetsetterTheme.Colors.warning)
                }
            }

            if let offer = model.selectedOffer {
                ForEach(model.travelers.indices, id: \.self) { index in
                    if model.travelers.indices.contains(index) {
                        travelerSection(index: index, requiresDocuments: offer.requiresIdentityDocuments)
                    }
                }
            }

            Section {
                Button {
                    model.continueToReview()
                } label: {
                    Text("Review booking")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text("Names must match each traveler's passport or government ID exactly. Details are sent securely to book your ticket and are not saved on this phone.")
            }
        }
        .navigationTitle("Travelers")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: One traveler

    @ViewBuilder
    private func travelerSection(index: Int, requiresDocuments: Bool) -> some View {
        let form = model.travelers[index]
        let problems = model.issues[index] ?? [:]

        Section(TravelerForm.heading(index: index, type: form.type)) {
            Picker("Title", selection: $model.travelers[index].title) {
                Text("Select").tag("")
                ForEach(TravelerValidation.titles) { Text($0.label).tag($0.code) }
            }
            issue(problems[.title])

            TextField("First name", text: $model.travelers[index].givenName)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            issue(problems[.givenName])

            TextField("Last name", text: $model.travelers[index].familyName)
                .textContentType(.familyName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            issue(problems[.familyName])

            Picker("Gender on passport", selection: $model.travelers[index].gender) {
                Text("Select").tag("")
                ForEach(TravelerValidation.genders) { Text($0.label).tag($0.code) }
            }
            issue(problems[.gender])

            OptionalDateRow(
                title: "Date of birth",
                selection: $model.travelers[index].bornOn,
                range: Self.birthRange,
                startingAt: Self.suggestedBirthDate(type: form.type)
            )
            issue(problems[.bornOn])

            contactFields(index: index, form: form, problems: problems)

            if requiresDocuments {
                passportFields(index: index, problems: problems)
            }
        }
        .onChange(of: model.travelers[index]) { _, _ in
            // Editing clears the stale complaint for that traveler; the next
            // validation pass re-checks everything.
            if model.issues[index] != nil { model.clearIssues(at: index) }
        }
    }

    @ViewBuilder
    private func contactFields(index: Int, form: TravelerForm, problems: [TravelerField: String]) -> some View {
        if index > 0 {
            Toggle("Same email and phone as \(TravelerForm.heading(index: 0, type: model.travelers.first?.type))",
                   isOn: $model.travelers[index].sharesLeadContact)
        }
        if index == 0 || !form.sharesLeadContact {
            TextField("Email", text: $model.travelers[index].email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            issue(problems[.email])

            TextField("Phone, with country code", text: $model.travelers[index].phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
            issue(problems[.phone])
        }
    }

    @ViewBuilder
    private func passportFields(index: Int, problems: [TravelerField: String]) -> some View {
        TextField("Passport number", text: $model.travelers[index].passportNumber)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
        issue(problems[.passportNumber])

        Picker("Issuing country", selection: $model.travelers[index].passportCountry) {
            Text("Select").tag("")
            ForEach(Self.countries) { Text($0.label).tag($0.code) }
        }
        issue(problems[.passportCountry])

        OptionalDateRow(
            title: "Passport expiry",
            selection: $model.travelers[index].passportExpiry,
            range: Date()...Date.distantFuture,
            startingAt: Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date()
        )
        issue(problems[.passportExpiry])
    }

    @ViewBuilder
    private func issue(_ message: String?) -> some View {
        if let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(JetsetterTheme.Colors.danger)
        }
    }

    // MARK: Static data

    private static let birthRange: ClosedRange<Date> = {
        let now = Date()
        let oldest = Calendar.current.date(byAdding: .year, value: -TravelerValidation.maximumAgeYears, to: now) ?? .distantPast
        return oldest...now
    }()

    /// Where the date wheel opens, so the traveler isn't scrolling from today
    /// back thirty years. It is not a value until they confirm it.
    private static func suggestedBirthDate(type: String?) -> Date {
        let years: Int
        switch type {
        case "infant_without_seat": years = 1
        case "child":               years = 8
        default:                    years = 35
        }
        return Calendar.current.date(byAdding: .year, value: -years, to: Date()) ?? Date()
    }

    private static let countries: [TravelerChoice] = {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 }
            .map { TravelerChoice(code: $0, label: Locale.current.localizedString(forRegionCode: $0) ?? $0) }
            .sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
    }()
}

// MARK: - Optional date row

/// A date the traveler must choose on purpose. A date wheel that opens already
/// filled in invites a wrong birth date to be submitted unnoticed.
private struct OptionalDateRow: View {
    let title: String
    @Binding var selection: Date?
    let range: ClosedRange<Date>
    let startingAt: Date

    var body: some View {
        if selection != nil {
            DatePicker(
                title,
                selection: Binding(get: { selection ?? startingAt }, set: { selection = $0 }),
                in: range,
                displayedComponents: .date
            )
        } else {
            Button {
                selection = min(max(startingAt, range.lowerBound), range.upperBound)
            } label: {
                HStack {
                    Text(title).foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Spacer()
                    Text("Choose date")
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
            }
        }
    }
}

// MARK: - Review and pay

struct FlightReviewView: View {

    @Bindable var model: FlightBookingModel
    let onCompare: () -> Void

    @State private var legalURL: URL?

    var body: some View {
        ScrollView {
            if let offer = model.selectedOffer {
                VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.medium) {
                    if model.isTestMode { TestModeBanner() }

                    flights(offer)
                    travelers
                    total(offer)

                    if let error = model.checkoutError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(JetsetterTheme.Colors.danger)
                    }

                    payButton(offer)

                    Text(fineprint)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)

                    Button {
                        legalURL = BackendStatus.shared.termsURL
                    } label: {
                        Text("Terms of Service")
                            .font(.caption.weight(.medium))
                    }

                    Button(action: onCompare) {
                        Label("Compare on Kayak instead", systemImage: "safari")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .padding(JetsetterTheme.Spacing.medium)
                .readableWidth()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .inAppWeb(url: $legalURL)
    }

    // MARK: Sections

    private func flights(_ offer: BackendOffer) -> some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            HStack(spacing: JetsetterTheme.Spacing.small) {
                AirlineBadge(carrier: offer.airline)
                Text(offer.airline.name ?? "Flight")
                    .font(.headline)
            }
            ForEach(Array(offer.slices.enumerated()), id: \.offset) { _, slice in
                Divider()
                SliceSummaryView(slice: slice)
            }
            Divider()
            FareConditionsView(conditions: offer.conditions, baggage: offer.baggage)
        }
        .padding(JetsetterTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private var travelers: some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.xsmall) {
            Text("Travelers").font(.headline)
            ForEach(Array(model.travelers.enumerated()), id: \.offset) { _, form in
                let name = [form.givenName, form.familyName]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                Text(name.isEmpty ? "—" : name).font(.subheadline)
            }
            if let lead = model.travelers.first {
                Text(lead.email.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
        .padding(JetsetterTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func total(_ offer: BackendOffer) -> some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.xsmall) {
            HStack {
                Text("Total").font(.headline)
                Spacer()
                Text(BackendMoney.display(offer.totalAmount, currency: offer.totalCurrency))
                    .font(.title2.weight(.bold))
            }
            if let fee = offer.feeAmount, !BackendMoney.isZero(fee) {
                Text("Includes \(BackendMoney.display(fee, currency: offer.totalCurrency)) service fee")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: Pay

    private var paymentsUnavailable: Bool {
        guard let config = BackendStatus.shared.config else { return false }
        return !config.paymentsEnabled && !config.testMode
    }

    private func payButton(_ offer: BackendOffer) -> some View {
        let submitting = model.checkoutPhase == .submitting
        let amount = BackendMoney.display(offer.totalAmount, currency: offer.totalCurrency)
        let label = model.isTestMode ? "Book (test, no charge)" : "Pay \(amount)"

        return VStack(spacing: JetsetterTheme.Spacing.small) {
            Button {
                Task { await model.submit() }
            } label: {
                HStack {
                    if submitting { ProgressView().tint(.white) }
                    Text(submitting ? "Reserving your fare…" : label)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(JetsetterTheme.Colors.accentFill)
                .clipShape(.rect(cornerRadius: 12))
            }
            .disabled(submitting || paymentsUnavailable)

            if paymentsUnavailable {
                Text("Card payments aren't available right now. You can still compare this trip on Kayak.")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.warning)
            }
        }
    }

    private var fineprint: String {
        if model.isTestMode {
            return "This is a test booking: no real ticket is issued and nothing is charged."
        }
        return "You'll pay on a secure Stripe page that supports Apple Pay and cards. Your ticket is issued by the airline once payment clears, and the airline's fare rules above apply."
    }
}
