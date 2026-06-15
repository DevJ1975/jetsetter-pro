// File: Features/CheckIn/CheckInFlowView.swift
//
// Three-step full-screen check-in flow used by Home and Flight Detail.
// Steps: seat map → confirming spinner → success boarding pass.
//
// Step 3 renders the full boarding pass (seat, gate, QR, e-ticket #) when a
// `walletItem` + `walletViewModel` are supplied. It no longer auto-dismisses —
// the user taps Done to close. Call sites that don't have a wallet item still
// compile (both params default to nil) and get the fallback e-ticket badge.

import SwiftUI

// MARK: - CheckInFlowView

struct CheckInFlowView: View {

    // ── Inputs ────────────────────────────────────────────────────────────────

    var flightNumber: String = "AA169"
    var route: String        = "JFK → NRT"
    var departureLabel: String = "11:45 PM tonight"
    var gate: String         = "B14"
    var departure: Date      = Date().addingTimeInterval(60 * 60 * 12)

    /// Optional boarding-pass payload for the Step-3 embedded pass. When nil,
    /// Step 3 falls back to a simple e-ticket badge so old call sites still work.
    var walletItem: WalletItem? = nil
    var walletViewModel: WalletViewModel? = nil

    // ── Steps ─────────────────────────────────────────────────────────────────

    enum Step { case seatMap, confirming, success }

    @State private var step: Step = .seatMap
    @State private var selectedSeat: String
    @Environment(\.dismiss) private var dismiss

    // Custom init so `selectedSeat` can default to the wallet item's seat (if
    // any) without needing an `.onAppear` hack. All other params keep their
    // defaults so existing call sites compile unchanged.
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
        self._selectedSeat = State(initialValue: walletItem?.seatNumber ?? "3A")
    }

    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()

            switch step {
            case .seatMap:   seatMapStep
            case .confirming: confirmingStep
            case .success:   successStep
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Step 1: Seat Map

    private var seatMapStep: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("Select your seat")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 60)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                VStack(spacing: 18) {
                    flightSummaryCard
                    seatMapView
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.25)) { step = .confirming }
            } label: {
                Text("Confirm seat \(selectedSeat)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(JetsetterTheme.Colors.success, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // ── Flight summary card ───────────────────────────────────────────────────

    private var flightSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(flightNumber)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Text("Gate \(gate)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(JetsetterTheme.Colors.accent.opacity(0.25))
                    .clipShape(Capsule())
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

    // ── Seat map ──────────────────────────────────────────────────────────────

    private var seatMapView: some View {
        VStack(spacing: 18) {
            cabinSection(
                title: "First",
                rows: Array(1...2),
                seatLetters: ["A", "D", "G", "K"], // 1-2-1
                taken: ["1A", "2K"]
            )
            cabinDivider
            cabinSection(
                title: "Business",
                rows: Array(3...9),
                seatLetters: ["A", "D", "G", "K"], // 1-2-1 reverse herringbone
                taken: ["3D", "4G", "5K", "6A", "7D", "8K", "9G"],
                isSelectable: true
            )
            cabinDivider
            cabinSection(
                title: "Premium Economy",
                rows: Array(20...25),
                seatLetters: ["A", "B", "D", "E", "F", "G", "J", "K"], // 2-4-2
                taken: ["20A", "21F", "22K", "23B", "24E", "25J"]
            )
            cabinDivider
            economyPlaceholder
        }
    }

    private var cabinDivider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func cabinSection(
        title: String,
        rows: [Int],
        seatLetters: [String],
        taken: Set<String>,
        isSelectable: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(JetsetterTheme.Colors.accent)

            VStack(spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 6) {
                        Text("\(row)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(width: 18, alignment: .trailing)

                        ForEach(seatLetters, id: \.self) { letter in
                            let seat = "\(row)\(letter)"
                            seatButton(
                                seat: seat,
                                isTaken: taken.contains(seat),
                                isSelectable: isSelectable
                            )
                        }
                    }
                }
            }
        }
    }

    private func seatButton(seat: String, isTaken: Bool, isSelectable: Bool) -> some View {
        let isUserSeat = seat == (walletItem?.seatNumber ?? "3A")
        let isSelected = seat == selectedSeat

        return Button {
            guard isSelectable, !isTaken else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                selectedSeat = seat
            }
        } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(fillColor(isTaken: isTaken, isSelected: isSelected, isUserSeat: isUserSeat))
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            strokeColor(isTaken: isTaken, isSelected: isSelected, isUserSeat: isUserSeat),
                            lineWidth: isSelected || isUserSeat ? 1.5 : 0.7
                        )
                )
                .shadow(
                    color: (isUserSeat || isSelected) ? JetsetterTheme.Colors.success.opacity(0.6) : .clear,
                    radius: 6
                )
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable || isTaken)
        .accessibilityLabel("Seat \(seat)\(isTaken ? ", taken" : isSelected ? ", selected" : "")")
    }

    private func fillColor(isTaken: Bool, isSelected: Bool, isUserSeat: Bool) -> Color {
        if isUserSeat || isSelected { return JetsetterTheme.Colors.success.opacity(0.35) }
        if isTaken { return Color.white.opacity(0.18) }
        return Color.clear
    }

    private func strokeColor(isTaken: Bool, isSelected: Bool, isUserSeat: Bool) -> Color {
        if isUserSeat || isSelected { return JetsetterTheme.Colors.success }
        if isTaken { return Color.white.opacity(0.2) }
        return Color.white.opacity(0.45)
    }

    private var economyPlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ECONOMY")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.35))
            Text("Sold out")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Step 2: Confirming

    private var confirmingStep: some View {
        VStack(spacing: 18) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.6)
                .tint(.white)
            Text("Checking in with American Airlines…")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { step = .success }
        }
    }

    // MARK: - Step 3: Success
    //
    // Renders the full boarding pass card when a walletItem is available; the
    // SEAT cell is overridden with the user's freshly-confirmed selection.
    // When no walletItem is supplied (e.g. FlightDetailView with no wallet
    // entry), falls back to a minimal e-ticket badge. Does NOT auto-dismiss —
    // the user taps Done.

    private var successStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Small inline checkmark (not the big animated one)
                ZStack {
                    Circle().fill(Color.green.opacity(0.15)).frame(width: 56, height: 56)
                    Image(systemName: "checkmark").font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.green)
                }
                .padding(.top, 20)

                VStack(spacing: 4) {
                    Text("You're checked in").font(.title2).fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text("Seat \(selectedSeat) confirmed · Gate \(gate)")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.green.opacity(0.12)).clipShape(Capsule())
                }

                // Embedded boarding pass card
                if let item = walletItem, let vm = walletViewModel {
                    BoardingPassCard(item: item, seatOverride: selectedSeat, viewModel: vm)
                        .padding(.horizontal, 8)
                } else {
                    // Fallback when no walletItem (e.g. from FlightDetailView with no wallet item)
                    fallbackEticketBadge
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
        .onAppear {
            CheckInStateStore.markCheckedIn(
                flightNumber: flightNumber,
                departure: departure
            )
            // Activate luggage tracking the moment check-in completes —
            // bags transition from passive to active states with scan history
            // and the BagDetailView animations start playing.
            if MockDataService.isEnabled {
                MockDataService.activateBagsForCheckIn()
            }
        }
    }

    private var fallbackEticketBadge: some View {
        VStack(spacing: 8) {
            Text("E-TICKET").font(.system(size: 10, weight: .black)).tracking(2)
                .foregroundStyle(.white.opacity(0.55))
            Text("XBZP4Q").font(.system(.title3, design: .monospaced)).fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(JetsetterTheme.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

#Preview {
    CheckInFlowView()
}
