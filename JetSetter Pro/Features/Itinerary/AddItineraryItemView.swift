// File: Features/Itinerary/AddItineraryItemView.swift

import SwiftUI
import AVFoundation
import VisionKit

// MARK: - AddItineraryItemView

/// Sheet form for creating — or editing — an itinerary item inside a trip.
///
/// For flights, hotels, and rental cars the form reveals structured "booking"
/// fields (confirmation/PNR, seat, room type, pickup/drop-off, cost, …) so a
/// trip booked *outside* the app can be recorded with real detail. Activity and
/// restaurant items keep the original lightweight form.
///
/// Pass `existingItem` to edit in place: the form seeds itself from the item,
/// retitles to "Edit Booking", and routes Save to `updateItem` (preserving the
/// item's `id` and any calendar sync) instead of creating a new item.
struct AddItineraryItemView: View {

    let tripID: UUID
    @Bindable var viewModel: ItineraryViewModel
    private let existingItem: ItineraryItem?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var title: String
    @State private var type: ItineraryItemType
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var location: String
    @State private var notes: String

    // Shared booking fields
    @State private var confirmationNumber: String
    @State private var bookingProvider: String     // airline / company / hotel chain
    @State private var costAmount: String
    @State private var costCurrency: String

    // Flight
    @State private var flightNumber: String
    @State private var originCode: String
    @State private var destinationCode: String
    @State private var seat: String
    @State private var cabinClass: String
    @State private var terminal: String
    @State private var gate: String

    // Hotel
    @State private var hotelAddress: String
    @State private var roomType: String
    @State private var hotelPhone: String

    // Rental car
    @State private var vehicleClass: String
    @State private var vehicleDescription: String
    @State private var pickupLocation: String
    @State private var dropoffLocation: String

    // Boarding-pass scan
    @State private var isShowingScanner = false
    @State private var scanError: String?

    // Paste-confirmation import
    @State private var isShowingPaste = false

    private static let cabinOptions = ["", "Economy", "Premium Economy", "Business", "First"]

    // MARK: - Init

    init(tripID: UUID, viewModel: ItineraryViewModel, existingItem: ItineraryItem? = nil) {
        self.tripID = tripID
        self.viewModel = viewModel
        self.existingItem = existingItem

        // Default a brand-new item to the start of the trip rather than "now", so
        // items on a future trip don't get today's date and sort above the rest.
        let tripStart = viewModel.trips.first { $0.id == tripID }?.startDate ?? Date()
        let start = existingItem?.startDate ?? tripStart
        let resolvedType = existingItem?.type ?? .flight

        _title   = State(initialValue: existingItem?.title ?? "")
        _type    = State(initialValue: resolvedType)
        _startDate = State(initialValue: start)
        _hasEndDate = State(initialValue: existingItem?.endDate != nil || (existingItem == nil && resolvedType == .hotel))
        _endDate = State(initialValue: existingItem?.endDate
            ?? start.addingTimeInterval(resolvedType == .hotel ? 86_400 : 3_600))
        _location = State(initialValue: existingItem?.location ?? "")
        _notes    = State(initialValue: existingItem?.notes ?? "")

        _confirmationNumber = State(initialValue: existingItem?.confirmationNumber ?? "")
        _bookingProvider    = State(initialValue: existingItem?.bookingProvider ?? "")

        if let cost = existingItem?.cost {
            _costAmount = State(initialValue: MoneyFormatting.decimalString(
                cost.amount, fractionDigits: MoneyFormatting.fractionDigits(for: cost.currencyCode)))
            _costCurrency = State(initialValue: cost.currencyCode)
        } else {
            _costAmount = State(initialValue: "")
            _costCurrency = State(initialValue: "USD")
        }

        let flight = existingItem?.flightDetails
        _flightNumber    = State(initialValue: flight?.flightNumber ?? "")
        _originCode      = State(initialValue: flight?.originCode ?? "")
        _destinationCode = State(initialValue: flight?.destinationCode ?? "")
        _seat            = State(initialValue: flight?.seat ?? "")
        _cabinClass      = State(initialValue: flight?.cabinClass ?? "")
        _terminal        = State(initialValue: flight?.terminal ?? "")
        _gate            = State(initialValue: flight?.gate ?? "")

        let hotel = existingItem?.hotelDetails
        _hotelAddress = State(initialValue: hotel?.address ?? "")
        _roomType     = State(initialValue: hotel?.roomType ?? "")
        _hotelPhone   = State(initialValue: hotel?.phone ?? "")

        let car = existingItem?.carDetails
        _vehicleClass       = State(initialValue: car?.vehicleClass ?? "")
        _vehicleDescription = State(initialValue: car?.vehicleDescription ?? "")
        _pickupLocation     = State(initialValue: car?.pickupLocation ?? "")
        _dropoffLocation    = State(initialValue: car?.dropoffLocation ?? "")
    }

    /// The trip this item is being added to, read live from the view model.
    private var trip: Trip? {
        viewModel.trips.first { $0.id == tripID }
    }

    private var isEditing: Bool { existingItem != nil }

    // MARK: - Validation

    private var canSave: Bool {
        switch type {
        case .flight:
            return !trimmed(flightNumber).isEmpty || !trimmed(bookingProvider).isEmpty || !trimmed(title).isEmpty
        case .transport:
            return !trimmed(bookingProvider).isEmpty || !trimmed(vehicleDescription).isEmpty
                || !trimmed(vehicleClass).isEmpty || !trimmed(title).isEmpty
        case .hotel, .activity, .restaurant:
            return !trimmed(title).isEmpty
        }
    }

    /// True when the chosen start date falls outside the trip's date range.
    private var startDateOutsideTrip: Bool {
        guard let trip else { return false }
        let cal = Calendar.current
        let day = cal.startOfDay(for: startDate)
        return day < cal.startOfDay(for: trip.startDate) || day > cal.startOfDay(for: trip.endDate)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Type Picker
                Section("Type") {
                    Picker("Item type", selection: $type) {
                        ForEach(ItineraryItemType.allCases) { itemType in
                            Label(itemType.displayName, systemImage: itemType.systemImage)
                                .tag(itemType)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // MARK: Type-specific details
                switch type {
                case .flight:     flightSection
                case .hotel:      hotelSection
                case .transport:  rentalSection
                case .activity, .restaurant: genericSection
                }

                // MARK: Dates
                dateSection

                // MARK: Cost
                Section("Cost (optional)") {
                    HStack {
                        TextField("Amount", text: $costAmount)
                            .keyboardType(.decimalPad)
                        Divider()
                        Picker("Currency", selection: $costCurrency) {
                            ForEach(UserPreferences.supportedCurrencies, id: \.code) { c in
                                Text(c.code).tag(c.code)
                            }
                        }
                        .labelsHidden()
                    }
                }

                // MARK: Notes
                Section("Notes (optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(isEditing ? "Edit Booking" : "Add Item")
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
            .fullScreenCover(isPresented: $isShowingScanner) {
                scannerCover
            }
            .sheet(isPresented: $isShowingPaste) {
                PasteConfirmationSheet { text in
                    applyParsedConfirmation(text)
                }
            }
            .alert("Boarding Pass", isPresented: scanErrorBinding, presenting: scanError) { _ in
                Button("OK", role: .cancel) { scanError = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    /// Shared "paste a confirmation email" affordance used by every booking type.
    private var pasteButton: some View {
        Button {
            isShowingPaste = true
        } label: {
            Label("Paste confirmation details", systemImage: "doc.on.clipboard")
                .foregroundStyle(JetsetterTheme.Colors.accent)
        }
    }

    // MARK: - Boarding-pass scanner

    private var scanErrorBinding: Binding<Bool> {
        Binding(get: { scanError != nil }, set: { if !$0 { scanError = nil } })
    }

    private var scannerCover: some View {
        ZStack(alignment: .top) {
            BoardingPassScannerView(
                onScan: { payload in
                    isShowingScanner = false
                    applyBoardingPass(payload)
                },
                onFailure: { message in
                    isShowingScanner = false
                    scanError = message
                }
            )
            .ignoresSafeArea()

            HStack {
                Button {
                    isShowingScanner = false
                } label: {
                    Text("Cancel")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                Spacer()
                Label("Point at the barcode", systemImage: "barcode.viewfinder")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
            }
            .padding()
        }
    }

    /// Checks camera availability/permission and presents the scanner, or sets an
    /// explanatory error when it can't run.
    private func presentScanner() {
        scanError = nil
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            scanError = "Barcode scanning isn't available on this device."
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingScanner = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                await MainActor.run {
                    if granted {
                        isShowingScanner = true
                    } else {
                        scanError = "Camera access is off. Enable it in Settings to scan."
                    }
                }
            }
        default:
            scanError = "Camera access is off. Enable it in Settings to scan."
        }
    }

    /// Parses a scanned BCBP payload and fills the flight fields. Confirmation and
    /// airline are only filled when blank, so a scan never clobbers what the user
    /// already typed.
    private func applyBoardingPass(_ payload: String) {
        guard let pass = BCBPParser.parse(payload) else {
            scanError = "That barcode didn't look like a boarding pass."
            return
        }
        if let flight = pass.flightNumber { flightNumber = flight }
        if let origin = pass.originCode { originCode = origin }
        if let destination = pass.destinationCode { destinationCode = destination }
        if let scannedSeat = pass.seat { seat = scannedSeat }
        if let pnr = pass.pnr, trimmed(confirmationNumber).isEmpty { confirmationNumber = pnr }
        if let airline = pass.airlineCode, trimmed(bookingProvider).isEmpty { bookingProvider = airline }
        if let date = pass.flightDate { startDate = date }
    }

    /// Applies best-effort fields parsed from pasted confirmation text. Only fills
    /// blanks so it never overwrites something the user already entered.
    private func applyParsedConfirmation(_ text: String) {
        let parsed = ConfirmationTextParser.parse(text)
        if let conf = parsed.confirmationNumber, trimmed(confirmationNumber).isEmpty {
            confirmationNumber = conf
        }
        if type == .flight {
            if let origin = parsed.originCode, trimmed(originCode).isEmpty { originCode = origin }
            if let destination = parsed.destinationCode, trimmed(destinationCode).isEmpty { destinationCode = destination }
        }
        if let amount = parsed.amount, trimmed(costAmount).isEmpty {
            if let code = parsed.currencyCode { costCurrency = code }
            costAmount = MoneyFormatting.decimalString(
                amount, fractionDigits: MoneyFormatting.fractionDigits(for: costCurrency))
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var flightSection: some View {
        Section {
            Button {
                presentScanner()
            } label: {
                Label("Scan boarding pass", systemImage: "barcode.viewfinder")
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }
            pasteButton
        } footer: {
            Text("Scan the barcode on a paper or wallet boarding pass, or paste a confirmation email, to fill in the flight automatically.")
        }

        Section("Ticket details") {
            TextField("Airline (e.g. American)", text: $bookingProvider)
            TextField("Flight number (e.g. AA 100)", text: $flightNumber)
                .autocorrectionDisabled()
            TextField("Confirmation / PNR", text: $confirmationNumber)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            HStack {
                TextField("From (SFO)", text: $originCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("To (JFK)", text: $destinationCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            TextField("Seat (e.g. 14A)", text: $seat)
            Picker("Cabin", selection: $cabinClass) {
                ForEach(Self.cabinOptions, id: \.self) { option in
                    Text(option.isEmpty ? "Not set" : option).tag(option)
                }
            }
            TextField("Terminal (optional)", text: $terminal)
            TextField("Gate (optional)", text: $gate)
        }
    }

    @ViewBuilder
    private var hotelSection: some View {
        Section {
            pasteButton
        } footer: {
            Text("Paste a confirmation email to fill in what we can.")
        }
        Section("Reservation details") {
            TextField("Hotel name", text: $title)
            TextField("Confirmation number", text: $confirmationNumber)
                .autocorrectionDisabled()
            TextField("Address", text: $hotelAddress)
            TextField("Room type (e.g. King, Suite)", text: $roomType)
            TextField("Phone (optional)", text: $hotelPhone)
                .keyboardType(.phonePad)
        }
    }

    @ViewBuilder
    private var rentalSection: some View {
        Section {
            pasteButton
        } footer: {
            Text("Paste a confirmation email to fill in what we can.")
        }
        Section("Rental details") {
            TextField("Company (e.g. Hertz)", text: $bookingProvider)
            TextField("Confirmation number", text: $confirmationNumber)
                .autocorrectionDisabled()
            TextField("Vehicle class (e.g. Midsize)", text: $vehicleClass)
            TextField("Vehicle (e.g. Toyota Corolla or similar)", text: $vehicleDescription)
            TextField("Pickup location", text: $pickupLocation)
            TextField("Drop-off location (optional)", text: $dropoffLocation)
        }
    }

    @ViewBuilder
    private var genericSection: some View {
        Section("Details") {
            TextField("Title", text: $title)
            TextField("Location (optional)", text: $location)
        }
    }

    @ViewBuilder
    private var dateSection: some View {
        Section {
            DatePicker(startDateLabel, selection: $startDate, displayedComponents: [.date, .hourAndMinute])

            Toggle(endToggleLabel, isOn: $hasEndDate)

            if hasEndDate {
                DatePicker(endDateLabel, selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
            }
        } header: {
            Text("Date & Time")
        } footer: {
            if startDateOutsideTrip {
                Label("This date is outside your trip's dates.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.warning)
            }
        }
    }

    // Contextual date labels so the same date section reads naturally per type.
    private var startDateLabel: String {
        switch type {
        case .flight:    return "Departure"
        case .hotel:     return "Check-in"
        case .transport: return "Pickup"
        default:         return "Start"
        }
    }

    private var endDateLabel: String {
        switch type {
        case .flight:    return "Arrival"
        case .hotel:     return "Check-out"
        case .transport: return "Drop-off"
        default:         return "End"
        }
    }

    private var endToggleLabel: String {
        switch type {
        case .hotel:     return "Add check-out"
        case .transport: return "Add drop-off"
        default:         return "Add end time"
        }
    }

    // MARK: - Save

    private func saveItem() {
        let item = ItineraryItem(
            id: existingItem?.id ?? UUID(),
            title: composedTitle(),
            type: type,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            location: composedLocation(),
            notes: nilIfEmpty(notes),
            calendarEventIdentifier: existingItem?.calendarEventIdentifier,
            confirmationNumber: nilIfEmpty(confirmationNumber),
            bookingProvider: nilIfEmpty(bookingProvider),
            cost: composedCost(),
            flightDetails: type == .flight ? composedFlightDetails() : nil,
            hotelDetails: type == .hotel ? composedHotelDetails() : nil,
            carDetails: type == .transport ? composedCarDetails() : nil
        )

        if isEditing {
            viewModel.updateItem(item, in: tripID)
        } else {
            viewModel.addItem(item, to: tripID)
        }
        dismiss()
    }

    // MARK: - Composition

    /// Composes the display title from structured fields, preserving any
    /// explicitly-typed title (and legacy titles when editing older items).
    private func composedTitle() -> String {
        switch type {
        case .flight:
            let parts = [trimmed(bookingProvider), trimmed(flightNumber)].filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " ") }
            return trimmed(title).isEmpty ? "Flight" : trimmed(title)
        case .transport:
            let vehicle = trimmed(vehicleClass).isEmpty ? trimmed(vehicleDescription) : trimmed(vehicleClass)
            let parts = [trimmed(bookingProvider), vehicle].filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " — ") }
            return trimmed(title).isEmpty ? "Rental Car" : trimmed(title)
        case .hotel, .activity, .restaurant:
            return trimmed(title)
        }
    }

    /// Composes the `location` string from structured fields, falling back to any
    /// seeded/typed location so legacy data (e.g. "SFO → NRT") is never lost.
    private func composedLocation() -> String? {
        switch type {
        case .flight:
            let o = trimmed(originCode).uppercased()
            let d = trimmed(destinationCode).uppercased()
            if !o.isEmpty && !d.isEmpty { return "\(o) → \(d)" }
            return nilIfEmpty(location)
        case .hotel:
            return nilIfEmpty(hotelAddress) ?? nilIfEmpty(location)
        case .transport:
            return nilIfEmpty(pickupLocation) ?? nilIfEmpty(location)
        case .activity, .restaurant:
            return nilIfEmpty(location)
        }
    }

    private func composedCost() -> BookingCost? {
        guard let amount = MoneyFormatting.parseDecimal(costAmount), amount > 0 else { return nil }
        return BookingCost(amount: amount, currencyCode: costCurrency)
    }

    private func composedFlightDetails() -> FlightBookingDetails? {
        let details = FlightBookingDetails(
            airline: nilIfEmpty(bookingProvider),
            flightNumber: nilIfEmpty(flightNumber),
            originCode: nilIfEmpty(originCode).map { $0.uppercased() },
            destinationCode: nilIfEmpty(destinationCode).map { $0.uppercased() },
            seat: nilIfEmpty(seat),
            cabinClass: nilIfEmpty(cabinClass),
            terminal: nilIfEmpty(terminal),
            gate: nilIfEmpty(gate)
        )
        return details == FlightBookingDetails() ? nil : details
    }

    private func composedHotelDetails() -> HotelBookingDetails? {
        let details = HotelBookingDetails(
            address: nilIfEmpty(hotelAddress),
            roomType: nilIfEmpty(roomType),
            phone: nilIfEmpty(hotelPhone)
        )
        return details == HotelBookingDetails() ? nil : details
    }

    private func composedCarDetails() -> CarRentalDetails? {
        let details = CarRentalDetails(
            vehicleClass: nilIfEmpty(vehicleClass),
            vehicleDescription: nilIfEmpty(vehicleDescription),
            pickupLocation: nilIfEmpty(pickupLocation),
            dropoffLocation: nilIfEmpty(dropoffLocation)
        )
        return details == CarRentalDetails() ? nil : details
    }

    // MARK: - Helpers

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nilIfEmpty(_ s: String) -> String? {
        let t = trimmed(s)
        return t.isEmpty ? nil : t
    }
}

// MARK: - PasteConfirmationSheet

/// Simple sheet that lets the user paste raw confirmation text; on Apply the text
/// is handed back to the form's best-effort parser.
private struct PasteConfirmationSheet: View {
    let onApply: (String) -> Void

    @State private var text: String = ""
    @Environment(\.dismiss) private var dismiss

    private var canApply: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                } footer: {
                    Text("Paste your booking confirmation. We'll fill in the confirmation number, route, and price where we can — review everything before saving.")
                }
            }
            .navigationTitle("Paste Confirmation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        onApply(text)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(canApply ? JetsetterTheme.Colors.accent : .secondary)
                    .disabled(!canApply)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Add") {
    AddItineraryItemView(tripID: UUID(), viewModel: ItineraryViewModel())
}
