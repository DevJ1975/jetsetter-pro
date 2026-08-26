// File: Features/Booking/FlightCheckoutView.swift
//
// Real Duffel flight checkout: search offers → pick one → enter traveler →
// pay with Apple Pay → create the order → persist. Shown only when the Duffel
// proxy is configured (DuffelBookingService.isConfigured); otherwise the Flights
// tab keeps its Kayak deep-link. "Booked" is shown ONLY after the order-creation
// call itself succeeds — never on payment alone.

import SwiftUI

// MARK: - ViewModel

@MainActor
@Observable
final class FlightCheckoutViewModel {

    enum Stage: Equatable {
        case searching, offers, traveler, paying, booking, success, failed
    }

    let params: DuffelSearchParams

    var stage: Stage = .searching
    var offers: [DuffelOffer] = []
    var selectedOffer: DuffelOffer?
    var confirmation: DuffelOrderConfirmation?
    var errorMessage: String?

    // Traveler (single adult for now; multi-pax is a follow-on).
    var title = "mr"
    var givenName = ""
    var familyName = ""
    var email = ""
    var phone = ""
    var bornOn = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    var gender = "m"

    init(params: DuffelSearchParams) { self.params = params }

    var canSubmitTraveler: Bool {
        !givenName.trimmingCharacters(in: .whitespaces).isEmpty
            && !familyName.trimmingCharacters(in: .whitespaces).isEmpty
            && email.contains("@")
            && phone.hasPrefix("+")
    }

    func search() async {
        stage = .searching
        errorMessage = nil
        do {
            offers = try await DuffelBookingService.shared.searchOffers(params)
            stage = .offers
            if offers.isEmpty { errorMessage = "No flights found for that route and date." }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Search failed."
            stage = .failed
        }
    }

    func select(_ offer: DuffelOffer) {
        selectedOffer = offer
        stage = .traveler
    }

    /// Charge with Apple Pay, then create the order, then persist. Only reaches
    /// `.success` if the order call returns — payment alone is not "booked".
    func payAndBook() async {
        guard let offer = selectedOffer, let passengerID = offer.passengers.first?.id else {
            errorMessage = "This fare can't be booked right now."
            stage = .failed
            return
        }
        let total = Decimal(string: offer.totalAmount) ?? 0
        errorMessage = nil

        do {
            stage = .paying
            let paymentReference = try await ApplePayService.shared.pay(
                total: total,
                currency: offer.totalCurrency,
                itemLabel: "Flight \(params.origin) → \(params.destination)"
            )

            stage = .booking
            let passenger = DuffelPassengerBooking(
                id: passengerID,
                title: title,
                givenName: givenName.trimmingCharacters(in: .whitespaces),
                familyName: familyName.trimmingCharacters(in: .whitespaces),
                bornOn: ISO8601DateFormatter.expediaDate.string(from: bornOn),
                gender: gender,
                email: email.trimmingCharacters(in: .whitespaces),
                phoneNumber: phone.trimmingCharacters(in: .whitespaces),
                type: "adult"
            )
            let order = try await DuffelBookingService.shared.createOrder(
                offerId: offer.id, passengers: [passenger], paymentReference: paymentReference
            )

            let tripID = TravelStore.activeOrNextTrip()?.id ?? UUID()
            await DuffelBookingPersistence.record(order: order, offer: offer, params: params, tripID: tripID)

            confirmation = order
            stage = .success
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Booking failed."
            stage = .failed
        }
    }
}

// MARK: - View

struct FlightCheckoutView: View {

    @State private var viewModel: FlightCheckoutViewModel
    @Environment(\.dismiss) private var dismiss

    init(params: DuffelSearchParams) {
        _viewModel = State(initialValue: FlightCheckoutViewModel(params: params))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.stage {
                case .searching: progress("Searching flights…")
                case .offers:    offerList
                case .traveler:  travelerForm
                case .paying:    progress("Contacting Apple Pay…")
                case .booking:   progress("Confirming your booking…")
                case .success:   successView
                case .failed:    failureView
                }
            }
            .navigationTitle("Book Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { if viewModel.stage == .searching { await viewModel.search() } }
    }

    private func progress(_ label: String) -> some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            ProgressView().scaleEffect(1.3)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var offerList: some View {
        ScrollView {
            LazyVStack(spacing: JetsetterTheme.Spacing.medium) {
                ForEach(viewModel.offers) { offer in
                    Button { viewModel.select(offer) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(offer.owner?.name ?? "Flight").font(.headline)
                                Text("\(viewModel.params.origin) → \(viewModel.params.destination)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(priceString(offer.totalAmount, offer.totalCurrency))
                                .font(.headline).foregroundStyle(JetsetterTheme.Colors.accent)
                        }
                        .padding(JetsetterTheme.Card.padding)
                        .jetCard()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(JetsetterTheme.Spacing.medium)
        }
    }

    private var travelerForm: some View {
        Form {
            Section("Traveler") {
                TextField("First name", text: $viewModel.givenName).textContentType(.givenName)
                TextField("Last name", text: $viewModel.familyName).textContentType(.familyName)
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress).autocorrectionDisabled()
                TextField("Phone (+1…)", text: $viewModel.phone).keyboardType(.phonePad)
                DatePicker("Date of birth", selection: $viewModel.bornOn, displayedComponents: .date)
                Picker("Title", selection: $viewModel.title) {
                    ForEach(["mr", "mrs", "ms", "miss", "dr"], id: \.self) { Text($0.uppercased()).tag($0) }
                }
                Picker("Gender", selection: $viewModel.gender) {
                    Text("Male").tag("m"); Text("Female").tag("f")
                }
            }
            Section {
                Button {
                    Task { await viewModel.payAndBook() }
                } label: {
                    Label(payButtonTitle, systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .disabled(!viewModel.canSubmitTraveler)
                if !ApplePayService.canPay {
                    Text("Apple Pay isn't set up on this device. Add a card in Wallet to continue.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var payButtonTitle: String {
        guard let offer = viewModel.selectedOffer else { return "Pay" }
        return "Pay \(priceString(offer.totalAmount, offer.totalCurrency)) with Apple Pay"
    }

    private var successView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52)).foregroundStyle(JetsetterTheme.Colors.success)
            Text("Booked!").font(.title2.weight(.bold))
            if let conf = viewModel.confirmation {
                Text("Confirmation \(conf.bookingReference)").font(.subheadline)
                Text("It's in your itinerary.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent).padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var failureView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44)).foregroundStyle(JetsetterTheme.Colors.warning)
            Text(viewModel.errorMessage ?? "Something went wrong.")
                .font(.body).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .padding(.horizontal, JetsetterTheme.Spacing.large)
            Button("Try Again") {
                Task { await viewModel.search() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func priceString(_ amount: String, _ currency: String) -> String {
        guard let value = Decimal(string: amount) else { return "\(amount) \(currency)" }
        return value.formatted(.currency(code: currency))
    }
}
