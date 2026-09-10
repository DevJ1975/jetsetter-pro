// File: Features/CheckIn/CheckInFlowView.swift
//
// Check-in hand-off used by Home and Flight Detail. The app never checks a
// traveler in itself — no airline exposes that — so this flow does the honest
// thing: opens the carrier's own check-in page in-app, then lets the traveler
// confirm they finished and (optionally) scan the real boarding pass into the
// wallet. The previous version showed a fabricated seat map and declared
// success after a 1.5-second spinner.
//
// Steps: hand-off → confirm → done. When the flight was already marked as
// checked in, the view opens on the done step.

import SwiftUI

// MARK: - CheckInFlowView

struct CheckInFlowView: View {

    // ── Inputs ────────────────────────────────────────────────────────────────

    var flightNumber: String = "AA169"
    var route: String        = "JFK → NRT"
    var departureLabel: String = "11:45 PM tonight"
    var gate: String         = "B14"
    var departure: Date      = Date().addingTimeInterval(60 * 60 * 12)

    /// Optional boarding-pass payload for the done step. When nil, the done
    /// step offers to scan a pass instead.
    var walletItem: WalletItem? = nil
    var walletViewModel: WalletViewModel? = nil

    // ── Steps ─────────────────────────────────────────────────────────────────

    enum Step { case handoff, confirm, done }

    @State private var step: Step
    @State private var checkInResult: CheckInResult?
    @State private var isResolving = false
    @State private var webURL: URL?
    @State private var showScanner = false
    @State private var scanError: String?
    @State private var scannedPass: WalletItem?
    @State private var didCommit = false
    @Environment(\.dismiss) private var dismiss

    init(
        flightNumber: String = "AA169",
        route: String = "JFK → NRT",
        departureLabel: String = "11:45 PM tonight",
        gate: String = "B14",
        departure: Date = Date().addingTimeInterval(60 * 60 * 12),
        walletItem: WalletItem? = nil,
        walletViewModel: WalletViewModel? = nil
    ) {
        self.flightNumber = flightNumber
        self.route = route
        self.departureLabel = departureLabel
        self.gate = gate
        self.departure = departure
        self.walletItem = walletItem
        self.walletViewModel = walletViewModel

        let alreadyCheckedIn = CheckInStateStore.isCheckedIn(flightNumber: flightNumber, departure: departure)
        self._step = State(initialValue: alreadyCheckedIn ? .done : .handoff)
        self._didCommit = State(initialValue: alreadyCheckedIn)
    }

    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()

            switch step {
            case .handoff: handoffStep
            case .confirm: confirmStep
            case .done:    doneStep
            }
        }
        .preferredColorScheme(.dark)
        .inAppWeb(url: $webURL, title: "\(carrierDisplayName) Check-In")
        .onChange(of: webURL) { old, new in
            // The airline page was dismissed — ask whether check-in finished.
            if old != nil, new == nil, step == .handoff {
                withAnimation(.easeInOut(duration: 0.25)) { step = .confirm }
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                BoardingPassScannerView(
                    onScan: { payload in
                        showScanner = false
                        importScannedPass(payload)
                    },
                    onFailure: { message in
                        showScanner = false
                        scanError = message
                    }
                )
                .ignoresSafeArea()
                .navigationTitle("Scan Boarding Pass")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showScanner = false }
                    }
                }
            }
        }
        .task { await resolveCheckInLink() }
    }

    // MARK: - Airline

    /// Airline code from the leading letters of the flight number ("DL2244" → "DL").
    private var airlineCode: String {
        String(flightNumber.prefix(while: { $0.isLetter })).uppercased()
    }

    private var carrierDisplayName: String {
        if let airline = walletItem?.airline, !airline.isEmpty { return airline }
        if let name = checkInResult?.airlineName, name != airlineCode { return name }
        if let name = TravelProfileEngine.airlineCodeToName[airlineCode] { return name }
        return "your airline"
    }

    private func resolveCheckInLink() async {
        guard !airlineCode.isEmpty, checkInResult == nil else { return }
        isResolving = true
        checkInResult = await CheckInService.shared.checkInResult(for: airlineCode)
        isResolving = false
    }

    // MARK: - Step 1: Hand-off

    private var handoffStep: some View {
        VStack(spacing: 0) {
            topBar(title: "Check in")

            ScrollView {
                VStack(spacing: 18) {
                    flightSummaryCard

                    VStack(alignment: .leading, spacing: 10) {
                        Text("HOW THIS WORKS")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                        stepRow(1, "Open \(carrierDisplayName)'s check-in page here in the app.")
                        stepRow(2, "Check in and pick your seat with the airline.")
                        stepRow(3, "Come back, confirm, and scan your boarding pass into the wallet.")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            VStack(spacing: 10) {
                Button {
                    if let url = checkInResult?.mobileURL ?? checkInResult?.webURL {
                        webURL = url
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isResolving { ProgressView().tint(.white) }
                        Image(systemName: "safari")
                        Text("Open \(carrierDisplayName) Check-In")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(JetsetterTheme.Colors.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(checkInResult == nil)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { step = .confirm }
                } label: {
                    Text("I already checked in")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 2: Confirm

    private var confirmStep: some View {
        VStack(spacing: 0) {
            topBar(title: "Checked in?")

            Spacer()

            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.success)
                Text("Did you finish checking in with \(carrierDisplayName)?")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("We'll mark \(flightNumber) as checked in, start the live flight card, and stop the check-in reminders.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { step = .done }
                } label: {
                    Text("Yes, I'm checked in")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(JetsetterTheme.Colors.success, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { step = .handoff }
                } label: {
                    Text("Not yet — go back")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 3: Done

    private var doneStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color.green.opacity(0.15)).frame(width: 56, height: 56)
                    Image(systemName: "checkmark").font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.green)
                }
                .padding(.top, 20)

                VStack(spacing: 4) {
                    Text("You're checked in").font(.title2).fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text(gate == "—" ? flightNumber : "\(flightNumber) · Gate \(gate)")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.green.opacity(0.12)).clipShape(Capsule())
                }

                if let item = scannedPass ?? walletItem, let vm = walletViewModel {
                    BoardingPassCard(item: item, seatOverride: item.seatNumber, viewModel: vm)
                        .padding(.horizontal, 8)
                } else {
                    scanPassCard
                }

                if let scanError {
                    Text(scanError)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer(minLength: 24)

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(JetsetterTheme.Colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .onAppear(perform: commitCheckIn)
    }

    private var scanPassCard: some View {
        VStack(spacing: 10) {
            Text("BOARDING PASS")
                .font(.system(size: 10, weight: .black)).tracking(2)
                .foregroundStyle(.white.opacity(0.55))
            Text("Scan the barcode on your pass to keep it in the JetSetter wallet, with gate and seat.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button {
                scanError = nil
                showScanner = true
            } label: {
                Label("Scan Boarding Pass", systemImage: "barcode.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(JetsetterTheme.Colors.accent.opacity(0.14), in: Capsule())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(JetsetterTheme.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    /// One-shot side effects of a confirmed check-in: state, Live Activity,
    /// learning signal, and the Home reload.
    private func commitCheckIn() {
        guard !didCommit else { return }
        didCommit = true

        CheckInStateStore.markCheckedIn(flightNumber: flightNumber, departure: departure)

        let legs = route.components(separatedBy: " → ").map { $0.trimmingCharacters(in: .whitespaces) }
        func iata(_ code: String?) -> String {
            guard let code, code != "—" else { return "" }
            return code
        }
        FlightLiveActivityService.shared.start(
            flightNumber: flightNumber,
            airline: airlineCode,
            originIATA: iata(legs.first),
            destinationIATA: iata(legs.count > 1 ? legs[1] : nil),
            scheduledDeparture: departure,
            gate: gate == "—" ? nil : gate,
            terminal: nil,
            initialStatus: .onTime
        )
        if let seat = (scannedPass ?? walletItem)?.seatNumber, !seat.isEmpty {
            TravelProfileStore.shared.record(
                .seatChosen,
                value: seat,
                attributes: ["airline": airlineCode, "flight": String(flightNumber.drop(while: { $0.isLetter }))],
                source: "checkin"
            )
        }
        NotificationCenter.default.post(name: .jetSetterCheckInPosted, object: nil)
    }

    /// Parses a scanned BCBP barcode into a wallet boarding pass and saves it.
    private func importScannedPass(_ payload: String) {
        guard let parsed = BCBPParser.parse(payload) else {
            scanError = "That barcode didn't read as a boarding pass. Try again with better lighting."
            return
        }
        let item = Self.walletItem(from: parsed, fallbackFlightNumber: flightNumber, fallbackDate: departure)
        scannedPass = item
        if let vm = walletViewModel {
            Task { await vm.addItem(item) }
        }
        if let seat = item.seatNumber, !seat.isEmpty, didCommit {
            TravelProfileStore.shared.record(.seatChosen, value: seat,
                                             attributes: ["airline": airlineCode], source: "checkin")
        }
    }

    /// Builds a wallet boarding pass from a scanned BCBP barcode. Uses the same
    /// rawData keys as the rest of the wallet so BoardingPassCard renders it.
    private static func walletItem(from pass: BoardingPass, fallbackFlightNumber: String, fallbackDate: Date) -> WalletItem {
        let flight = (pass.flightNumber ?? fallbackFlightNumber).replacingOccurrences(of: " ", with: "")
        let airlineCode = pass.airlineCode ?? String(flight.prefix(while: { $0.isLetter }))
        var rawData: [String: String] = [
            "airline": TravelProfileEngine.airlineCodeToName[airlineCode.uppercased()] ?? airlineCode,
            "flight_number": flight,
            "iata_code": airlineCode.uppercased(),
            "departure_airport": pass.originCode ?? "—",
            "arrival_airport": pass.destinationCode ?? "—",
            "seat_number": pass.seat ?? "—",
            "gate": "—",
            "terminal": "—",
            "source": "bcbp_scan"
        ]
        if let name = pass.passengerName, !name.isEmpty { rawData["passenger"] = name }
        return WalletItem(
            itemType: .boardingPass,
            title: "\(flight) \(pass.originCode ?? "—") → \(pass.destinationCode ?? "—")",
            confirmationNumber: pass.pnr,
            date: pass.flightDate ?? fallbackDate,
            rawData: rawData
        )
    }

    // MARK: - Shared pieces

    private func topBar(title: String) -> some View {
        HStack {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 60)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var flightSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(flightNumber)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                if gate != "—" {
                    Text("Gate \(gate)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(JetsetterTheme.Colors.accent.opacity(0.25))
                        .clipShape(Capsule())
                }
            }
            Text(route)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(departureLabel)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(JetsetterTheme.Colors.accent.opacity(0.35), in: Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    CheckInFlowView()
}
