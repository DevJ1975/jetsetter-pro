// File: Features/TravelWallet/TravelWalletView.swift

import SwiftUI
import PassKit

// MARK: - TravelWalletView

/// Central hub for all trip documents: boarding passes, hotel reservations,
/// car rentals, event tickets, and travel insurance documents.
struct TravelWalletView: View {

    @StateObject private var viewModel = WalletViewModel()
    @State private var isShowingAddSheet = false
    @State private var selectedItem: WalletItem? = nil

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    loadingView
                } else if viewModel.items.isEmpty {
                    emptyStateView
                } else {
                    walletList
                }
            }
            .navigationTitle("Travel Wallet")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                AddWalletItemView(viewModel: viewModel)
            }
            .sheet(item: $selectedItem) { item in
                WalletItemDetailView(item: item, viewModel: viewModel)
            }
            .overlay(alignment: .top) {
                if let msg = viewModel.successMessage ?? viewModel.errorMessage {
                    bannerView(message: msg, isError: viewModel.errorMessage != nil)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(3))
                                withAnimation {
                                    viewModel.successMessage = nil
                                    viewModel.errorMessage = nil
                                }
                            }
                        }
                }
            }
            .animation(.easeInOut, value: viewModel.successMessage)
            .animation(.easeInOut, value: viewModel.errorMessage)
        }
        .task { await viewModel.load() }
    }

    // MARK: - Wallet List

    private var walletList: some View {
        ScrollView {
            LazyVStack(spacing: JetsetterTheme.Spacing.medium) {
                // Active items pinned at the top
                if !viewModel.activeItems.isEmpty {
                    sectionHeader(title: "Active Now", icon: "bolt.fill", color: JetsetterTheme.Colors.success)
                    ForEach(viewModel.activeItems) { item in
                        WalletItemCard(item: item)
                            .onTapGesture { selectedItem = item }
                    }
                }

                // Upcoming items
                if !viewModel.upcomingItems.isEmpty {
                    sectionHeader(title: "Upcoming", icon: "clock.fill", color: JetsetterTheme.Colors.accent)
                    ForEach(viewModel.upcomingItems) { item in
                        WalletItemCard(item: item)
                            .onTapGesture { selectedItem = item }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteItem(withID: item.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }

                // Past items collapsed
                let past = viewModel.items.filter { $0.status == .completed }
                if !past.isEmpty {
                    sectionHeader(title: "Past", icon: "checkmark.circle", color: .secondary)
                    ForEach(past) { item in
                        WalletItemCard(item: item)
                            .opacity(0.6)
                            .onTapGesture { selectedItem = item }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteItem(withID: item.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, JetsetterTheme.Spacing.medium)
            .padding(.bottom, JetsetterTheme.Spacing.large)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption).bold()
                .foregroundStyle(color)
            Text(title.uppercased())
                .font(JetsetterTheme.Typography.label)
                .tracking(1.2)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.top, JetsetterTheme.Spacing.small)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            ProgressView()
            Text("Loading wallet…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: JetsetterTheme.Spacing.large) {
            Spacer()
            Image(systemName: "wallet.pass")
                .font(.system(size: 64))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))

            VStack(spacing: JetsetterTheme.Spacing.small) {
                Text("Your Wallet Is Empty")
                    .font(.title3).fontWeight(.semibold)
                Text("Add boarding passes, hotel reservations, car rentals, and more — all in one place.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JetsetterTheme.Spacing.xlarge)
            }

            Button {
                isShowingAddSheet = true
            } label: {
                Label("Add Document", systemImage: "plus")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, JetsetterTheme.Spacing.large)
                    .padding(.vertical, JetsetterTheme.Spacing.small)
                    .background(JetsetterTheme.Colors.accent)
                    .cornerRadius(12)
            }
            Spacer()
        }
    }

    // MARK: - Banner

    private func bannerView(message: String, isError: Bool) -> some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? JetsetterTheme.Colors.danger : JetsetterTheme.Colors.success)
            Text(message).font(.subheadline)
            Spacer()
        }
        .padding(JetsetterTheme.Spacing.medium)
        .background(.regularMaterial)
        .cornerRadius(12)
        .padding(.horizontal, JetsetterTheme.Spacing.medium)
        .padding(.top, JetsetterTheme.Spacing.small)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}

// MARK: - WalletItemCard

private struct WalletItemCard: View {
    let item: WalletItem

    var body: some View {
        HStack(spacing: JetsetterTheme.Spacing.medium) {
            // Type icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: item.itemType.colorHex).opacity(0.15))
                    .frame(width: 50, height: 50)
                Image(systemName: item.itemType.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: item.itemType.colorHex))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let conf = item.confirmationNumber {
                    Text(conf)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(item.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                // Status badge
                Text(item.status.displayName)
                    .font(.caption2).fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: item.status.colorHex).opacity(0.15))
                    .foregroundStyle(Color(hex: item.status.colorHex))
                    .clipShape(Capsule())

                Image(systemName: "chevron.right")
                    .font(.caption).bold()
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .padding(JetsetterTheme.Spacing.medium)
        .jetCard()
    }
}

// MARK: - WalletItemDetailView

struct WalletItemDetailView: View {
    let item: WalletItem
    @ObservedObject var viewModel: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pkPassAddResult: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: JetsetterTheme.Spacing.medium) {
                    // Header hero card
                    heroCard

                    // Type-specific details
                    switch item.itemType {
                    case .boardingPass:     boardingPassDetails
                    case .hotelReservation: hotelDetails
                    case .carRental:        carRentalDetails
                    case .eventTicket:      eventTicketDetails
                    case .travelInsurance:  insuranceDetails
                    }

                    // Apple Wallet button — shown only for boarding passes with PKPass data
                    if item.itemType == .boardingPass {
                        addToWalletSection
                    }

                    // Check-In card for boarding passes
                    if item.itemType == .boardingPass,
                       let iata = item.iataCode,
                       let flight = item.flightNumber {
                        CheckInCardView(iataCode: iata, flightNumber: flight, departureDate: item.date)
                    }

                    // Delete button
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteItem(withID: item.id)
                            dismiss()
                        }
                    } label: {
                        Label("Remove from Wallet", systemImage: "trash")
                            .font(.subheadline).fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(JetsetterTheme.Spacing.medium)
                            .background(JetsetterTheme.Colors.danger.opacity(0.10))
                            .foregroundStyle(JetsetterTheme.Colors.danger)
                            .cornerRadius(12)
                    }
                }
                .padding(JetsetterTheme.Spacing.medium)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(item.itemType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
            }
        }
    }

    // MARK: Hero Card

    private var heroCard: some View {
        VStack(spacing: JetsetterTheme.Spacing.small) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: item.itemType.colorHex),
                                Color(hex: item.itemType.colorHex).opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 100)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.itemType.displayName.uppercased())
                            .font(.caption2).fontWeight(.bold)
                            .foregroundStyle(.white.opacity(0.8))
                            .tracking(1.5)
                        Text(item.title)
                            .font(.title3).fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: item.itemType.systemImage)
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(JetsetterTheme.Spacing.medium)
            }

            // Status + confirmation row
            HStack {
                Label(item.status.displayName, systemImage: "circle.fill")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color(hex: item.status.colorHex))
                Spacer()
                if let conf = item.confirmationNumber {
                    Text(conf)
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: Detail Sections

    @ViewBuilder
    private var boardingPassDetails: some View {
        detailCard(title: "Flight Details") {
            if let airline = item.airline { detailRow("Airline", value: airline) }
            if let flight = item.flightNumber { detailRow("Flight", value: flight) }
            detailRow("Date", value: item.date.formatted(.dateTime.month().day().year().hour().minute()))
            if let dep = item.departureAirport, let arr = item.arrivalAirport {
                detailRow("Route", value: "\(dep) → \(arr)")
            }
            if let seat = item.seatNumber { detailRow("Seat", value: seat) }
            if let terminal = item.terminal { detailRow("Terminal", value: terminal) }
            if let gate = item.gate { detailRow("Gate", value: gate) }
        }
    }

    @ViewBuilder
    private var hotelDetails: some View {
        detailCard(title: "Reservation Details") {
            if let addr = item.hotelAddress { detailRow("Address", value: addr) }
            if let ci = item.checkInDateString { detailRow("Check-in", value: ci) }
            if let co = item.checkOutDateString { detailRow("Check-out", value: co) }
            if let conf = item.confirmationNumber { detailRow("Confirmation", value: conf) }
        }
    }

    @ViewBuilder
    private var carRentalDetails: some View {
        detailCard(title: "Rental Details") {
            if let co = item.rentalCompany { detailRow("Company", value: co) }
            if let pl = item.pickupLocation { detailRow("Pick-up", value: pl) }
            if let vc = item.vehicleClass { detailRow("Vehicle", value: vc) }
            if let conf = item.confirmationNumber { detailRow("Confirmation", value: conf) }
            detailRow("Pick-up Date", value: item.date.formatted(.dateTime.month().day().year()))
        }
    }

    @ViewBuilder
    private var eventTicketDetails: some View {
        detailCard(title: "Event Details") {
            if let venue = item.venue { detailRow("Venue", value: venue) }
            if let loc = item.eventLocation { detailRow("Location", value: loc) }
            detailRow("Date", value: item.date.formatted(.dateTime.month().day().year().hour().minute()))
            if let conf = item.confirmationNumber { detailRow("Reference", value: conf) }
        }
    }

    @ViewBuilder
    private var insuranceDetails: some View {
        detailCard(title: "Policy Details") {
            if let prov = item.provider { detailRow("Provider", value: prov) }
            if let pol = item.policyNumber { detailRow("Policy #", value: pol) }
            if let cov = item.coverageType { detailRow("Coverage", value: cov) }
            detailRow("Start Date", value: item.date.formatted(.dateTime.month().day().year()))
        }
    }

    // MARK: Apple Wallet Section

    @ViewBuilder
    private var addToWalletSection: some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            Text("APPLE WALLET")
                .font(JetsetterTheme.Typography.label)
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: JetsetterTheme.Spacing.small) {
                if PKPassLibrary.isPassLibraryAvailable() {
                    Button {
                        addToAppleWallet()
                    } label: {
                        HStack {
                            Image(systemName: "wallet.pass.fill")
                            Text("Add to Apple Wallet")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(JetsetterTheme.Spacing.medium)
                        .background(Color.black)
                        .cornerRadius(12)
                    }
                }

                if let result = pkPassAddResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(JetsetterTheme.Spacing.medium)
            .jetCard()
        }
    }

    // MARK: Helpers

    private func detailCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            Text(title.uppercased())
                .font(JetsetterTheme.Typography.label)
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .jetCard()
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline).fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, JetsetterTheme.Spacing.medium)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, JetsetterTheme.Spacing.medium)
        }
    }

    /// Attempts to instantiate a PKPass from a base64 pkpass_data string and present it.
    /// In production this would be triggered by an actual .pkpass download URL.
    private func addToAppleWallet() {
        guard let base64 = item.rawData["pkpass_data"],
              let data = Data(base64Encoded: base64) else {
            pkPassAddResult = "No pass data available. Forward the airline's confirmation email to import."
            return
        }
        do {
            let pass = try PKPass(data: data)
            let library = PKPassLibrary()
            if library.containsPass(pass) {
                pkPassAddResult = "This pass is already in your Apple Wallet."
            } else {
                // PKAddPassesViewController must be presented via UIKit
                NotificationCenter.default.post(
                    name: NSNotification.Name("AddPKPassToWallet"),
                    object: pass
                )
            }
        } catch {
            pkPassAddResult = "Could not read pass: \(error.localizedDescription)"
        }
    }
}

// MARK: - AddWalletItemView

/// Sheet for manually adding a new wallet item.
struct AddWalletItemView: View {

    @ObservedObject var viewModel: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var itemType: WalletItemType = .boardingPass
    @State private var title: String = ""
    @State private var confirmationNumber: String = ""
    @State private var date: Date = Date()

    // Boarding pass fields
    @State private var airline: String = ""
    @State private var flightNumber: String = ""
    @State private var iataCode: String = ""
    @State private var depAirport: String = ""
    @State private var arrAirport: String = ""
    @State private var seat: String = ""
    @State private var terminal: String = ""
    @State private var gate: String = ""

    // Hotel fields
    @State private var hotelAddress: String = ""
    @State private var checkOutDate: Date = Date().addingTimeInterval(3 * 86_400)

    // Car rental fields
    @State private var rentalCompany: String = ""
    @State private var pickupLocation: String = ""
    @State private var vehicleClass: String = ""

    // Insurance fields
    @State private var provider: String = ""
    @State private var policyNumber: String = ""
    @State private var coverageType: String = ""

    // Event fields
    @State private var venue: String = ""
    @State private var eventLocation: String = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Document Type") {
                    Picker("Type", selection: $itemType) {
                        ForEach(WalletItemType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Confirmation / Reference #", text: $confirmationNumber)
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                // Type-specific fields
                switch itemType {
                case .boardingPass:
                    Section("Flight Info") {
                        TextField("Airline (e.g. Japan Airlines)", text: $airline)
                        TextField("Flight # (e.g. JL006)", text: $flightNumber)
                        TextField("Airline IATA code (e.g. JL)", text: $iataCode)
                            .textInputAutocapitalization(.characters)
                        HStack {
                            TextField("From (IATA)", text: $depAirport)
                                .textInputAutocapitalization(.characters)
                            Text("→")
                            TextField("To (IATA)", text: $arrAirport)
                                .textInputAutocapitalization(.characters)
                        }
                        TextField("Seat", text: $seat)
                        TextField("Terminal", text: $terminal)
                        TextField("Gate", text: $gate)
                    }
                case .hotelReservation:
                    Section("Stay Info") {
                        TextField("Hotel address", text: $hotelAddress)
                        DatePicker("Check-out", selection: $checkOutDate, in: date..., displayedComponents: .date)
                    }
                case .carRental:
                    Section("Rental Info") {
                        TextField("Rental company", text: $rentalCompany)
                        TextField("Pick-up location", text: $pickupLocation)
                        TextField("Vehicle class", text: $vehicleClass)
                    }
                case .travelInsurance:
                    Section("Policy Info") {
                        TextField("Provider", text: $provider)
                        TextField("Policy number", text: $policyNumber)
                        TextField("Coverage type", text: $coverageType)
                    }
                case .eventTicket:
                    Section("Event Info") {
                        TextField("Venue", text: $venue)
                        TextField("Location", text: $eventLocation)
                    }
                }
            }
            .navigationTitle("Add to Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveItem() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? JetsetterTheme.Colors.accent : .secondary)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func saveItem() {
        var rawData: [String: String] = [:]

        switch itemType {
        case .boardingPass:
            if !airline.isEmpty        { rawData["airline"] = airline }
            if !flightNumber.isEmpty   { rawData["flight_number"] = flightNumber }
            if !iataCode.isEmpty       { rawData["iata_code"] = iataCode.uppercased() }
            if !depAirport.isEmpty     { rawData["departure_airport"] = depAirport.uppercased() }
            if !arrAirport.isEmpty     { rawData["arrival_airport"] = arrAirport.uppercased() }
            if !seat.isEmpty           { rawData["seat_number"] = seat }
            if !terminal.isEmpty       { rawData["terminal"] = terminal }
            if !gate.isEmpty           { rawData["gate"] = gate }
        case .hotelReservation:
            if !hotelAddress.isEmpty   { rawData["hotel_address"] = hotelAddress }
            rawData["check_in_date"]  = isoFormatter.string(from: date)
            rawData["check_out_date"] = isoFormatter.string(from: checkOutDate)
            rawData["end_date"]       = isoFormatter.string(from: checkOutDate)
        case .carRental:
            if !rentalCompany.isEmpty  { rawData["rental_company"] = rentalCompany }
            if !pickupLocation.isEmpty { rawData["pickup_location"] = pickupLocation }
            if !vehicleClass.isEmpty   { rawData["vehicle_class"] = vehicleClass }
        case .travelInsurance:
            if !provider.isEmpty       { rawData["provider"] = provider }
            if !policyNumber.isEmpty   { rawData["policy_number"] = policyNumber }
            if !coverageType.isEmpty   { rawData["coverage_type"] = coverageType }
        case .eventTicket:
            if !venue.isEmpty          { rawData["venue"] = venue }
            if !eventLocation.isEmpty  { rawData["event_location"] = eventLocation }
        }

        let item = WalletItem(
            itemType: itemType,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            confirmationNumber: confirmationNumber.isEmpty ? nil : confirmationNumber,
            date: date,
            rawData: rawData
        )
        Task {
            await viewModel.addItem(item)
            dismiss()
        }
    }
}

private let isoFormatter = ISO8601DateFormatter()

// MARK: - Preview

#Preview {
    TravelWalletView()
}

#Preview("Detail — Boarding Pass") {
    let vm = WalletViewModel()
    return WalletItemDetailView(item: .sampleBoardingPass, viewModel: vm)
}
