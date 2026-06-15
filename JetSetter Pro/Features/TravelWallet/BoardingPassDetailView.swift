// File: Features/TravelWallet/BoardingPassDetailView.swift
//
// Full-screen boarding pass — Apple-Wallet-style. Airline color strip, large
// flight number, origin → destination IATA, full passenger info row, dotted
// tear-line, scannable QR code at the bottom. Shimmer + entry animation make
// it feel premium.
//
// The visible pass body is extracted into `BoardingPassCard` so it can be
// reused inline by other surfaces (e.g. the Check-In flow's success step).

import SwiftUI
import PassKit

// MARK: - BoardingPassDetailView

struct BoardingPassDetailView: View {

    let item: WalletItem
    @ObservedObject var viewModel: WalletViewModel
    @EnvironmentObject private var preferences: UserPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var revealed = false

    private var brandColor: Color { BoardingPassCard.brandColor(for: item.iataCode) }

    var body: some View {
        ZStack {
            // Sky → deep navy background
            LinearGradient(
                colors: [
                    Color(hex: "#0A0A1E"),
                    brandColor.opacity(0.4),
                    Color(hex: "#0A0A1E")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // The card handles its own internal shimmer; BoardingPassDetailView
                    // adds the larger reveal animation on top.
                    BoardingPassCard(item: item, showsShimmer: true, viewModel: viewModel)
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 30)
                }
                .padding(20)
                .padding(.top, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                revealed = true
            }
        }
    }
}

// MARK: - BoardingPassCard
//
// Reusable boarding-pass body — airline header, IATA route block, dotted
// tear-line, details block (with optional seat override), QR block, and the
// Add-to-Apple-Wallet button. Designed to be dropped into any container; the
// caller is responsible for outer reveal/shimmer animation if desired.

struct BoardingPassCard: View {

    let item: WalletItem
    var seatOverride: String? = nil
    /// When true, the card paints its own subtle shimmer sweep — useful when
    /// it's embedded somewhere that doesn't supply its own. The dedicated
    /// `BoardingPassDetailView` paints a richer external shimmer so it sets
    /// this to false to avoid double-shimmering.
    var showsShimmer: Bool = true
    @ObservedObject var viewModel: WalletViewModel
    @EnvironmentObject private var preferences: UserPreferences

    @State private var shimmerPhase: CGFloat = -1

    // MARK: Computed

    private var brandColor: Color { Self.brandColor(for: item.iataCode) }

    private var passengerName: String {
        let name = preferences.displayName
        return name.isEmpty ? "PASSENGER NAME" : name.uppercased()
    }

    /// Effective seat to render in the SEAT cell — caller's override wins.
    private var effectiveSeat: String {
        seatOverride ?? item.seatNumber ?? "—"
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 16) {
            passBody
            appleWalletButton
        }
    }

    private var passBody: some View {
        VStack(spacing: 0) {
            airlineHeader
            routeBlock
            tearLine
            detailsBlock
            qrBlock
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        )
        .overlay(showsShimmer ? AnyView(shimmerOverlay) : AnyView(EmptyView()))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            guard showsShimmer else { return }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 2
            }
        }
    }

    private var shimmerOverlay: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, .white.opacity(0.16), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geo.size.width * 1.5)
            .offset(x: geo.size.width * shimmerPhase)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
        .mask(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Airline strip

    private var airlineHeader: some View {
        ZStack {
            brandColor

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.airline?.uppercased() ?? "AIRLINE")
                        .font(.system(size: 11, weight: .black))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("BOARDING PASS")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "airplane.departure")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Route block

    private var routeBlock: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                // Origin
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.departureAirport ?? "—")
                        .font(.system(size: 44, weight: .black, design: .monospaced))
                        .foregroundStyle(.black)
                    Text(Self.cityName(for: item.departureAirport) ?? "")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.5))
                        .tracking(1)
                }
                Spacer()
                Image(systemName: "airplane")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(brandColor)
                    .rotationEffect(.degrees(0))
                Spacer()
                // Destination
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.arrivalAirport ?? "—")
                        .font(.system(size: 44, weight: .black, design: .monospaced))
                        .foregroundStyle(.black)
                    Text(Self.cityName(for: item.arrivalAirport) ?? "")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.5))
                        .tracking(1)
                }
            }
            HStack {
                Text(item.flightNumber ?? "—")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(brandColor)
                Spacer()
                Text(item.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.5))
                    .tracking(0.5)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(Color.white)
    }

    // MARK: - Tear line

    private var tearLine: some View {
        HStack {
            Circle().fill(Color(hex: "#0A0A1E")).frame(width: 22, height: 22).offset(x: -11)
            Spacer()
            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(height: 1)
                .overlay(
                    HStack(spacing: 6) {
                        ForEach(0..<24, id: \.self) { _ in
                            Rectangle().fill(Color.white).frame(width: 4, height: 1)
                        }
                    }
                )
            Spacer()
            Circle().fill(Color(hex: "#0A0A1E")).frame(width: 22, height: 22).offset(x: 11)
        }
        .frame(height: 22)
        .background(Color.white)
    }

    // MARK: - Details block

    private var detailsBlock: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                detailCell("PASSENGER", value: passengerName, alignment: .leading)
                detailCell("CLASS", value: Self.classFromSeat(effectiveSeat), alignment: .center)
                detailCell("BOARDING", value: boardingTimeString, alignment: .trailing)
            }
            Divider().padding(.horizontal, 20)
            HStack(alignment: .top, spacing: 0) {
                detailCell("FLIGHT", value: item.flightNumber ?? "—", alignment: .leading)
                detailCell("GATE", value: item.gate ?? "—", alignment: .center, emphasis: true)
                detailCell("SEAT", value: effectiveSeat, alignment: .trailing, emphasis: true)
            }
            Divider().padding(.horizontal, 20)
            HStack(alignment: .top, spacing: 0) {
                detailCell("TERMINAL", value: item.terminal ?? "—", alignment: .leading)
                detailCell("GROUP", value: "1", alignment: .center)
                detailCell("SEQUENCE", value: "048", alignment: .trailing)
            }
        }
        .padding(.vertical, 14)
        .background(Color.white)
    }

    private func detailCell(_ label: String, value: String, alignment: HorizontalAlignment, emphasis: Bool = false) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .black))
                .tracking(1.5)
                .foregroundStyle(.black.opacity(0.4))
            Text(value)
                .font(.system(size: emphasis ? 22 : 15, weight: .bold, design: emphasis ? .monospaced : .default))
                .foregroundStyle(emphasis ? brandColor : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: alignmentToFrameAlignment(alignment))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func alignmentToFrameAlignment(_ alignment: HorizontalAlignment) -> Alignment {
        switch alignment {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }

    // MARK: - QR

    private var qrBlock: some View {
        VStack(spacing: 10) {
            if let qr = QRCodeGenerator.image(from: qrPayload, size: 200) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .padding(8)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
            }
            Text(item.confirmationNumber ?? "—")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.black.opacity(0.6))
                .tracking(2)
            Text("Scan at gate")
                .font(.caption2)
                .foregroundStyle(.black.opacity(0.4))
        }
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private var qrPayload: String {
        // PNR-style payload — looks authentic when scanned.
        [
            "M1",
            passengerName.replacingOccurrences(of: " ", with: ""),
            item.confirmationNumber ?? "XXXXXX",
            item.departureAirport ?? "—",
            item.arrivalAirport ?? "—",
            item.flightNumber ?? "—",
            ISO8601DateFormatter().string(from: item.date)
        ].joined(separator: " ")
    }

    // MARK: - Apple Wallet button

    private var appleWalletButton: some View {
        Button {
            // Existing PassKit flow already handles base64 pkpass_data when present.
            if let base64 = item.rawData["pkpass_data"],
               let data = Data(base64Encoded: base64),
               let pass = try? PKPass(data: data) {
                PassKitService.presentAddPass(pass)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wallet.pass.fill")
                Text("Add to Apple Wallet")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    private var boardingTimeString: String {
        // Boarding typically starts 30 min before departure.
        let boarding = item.date.addingTimeInterval(-30 * 60)
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: boarding)
    }

    static func classFromSeat(_ seat: String?) -> String {
        guard let seat = seat else { return "—" }
        if let row = Int(seat.prefix(while: { $0.isNumber })) {
            if row <= 4 { return "FIRST" }
            if row <= 10 { return "BUSINESS" }
            if row <= 25 { return "PREMIUM" }
        }
        return "ECONOMY"
    }

    static func cityName(for iata: String?) -> String? {
        guard let iata = iata?.uppercased() else { return nil }
        let map: [String: String] = [
            "JFK": "New York", "LGA": "New York", "EWR": "Newark",
            "LAX": "Los Angeles", "SFO": "San Francisco", "ORD": "Chicago",
            "ATL": "Atlanta", "MIA": "Miami", "BOS": "Boston", "SEA": "Seattle",
            "DFW": "Dallas", "DEN": "Denver", "LAS": "Las Vegas",
            "NRT": "Tokyo", "HND": "Tokyo", "KIX": "Osaka",
            "LHR": "London", "LGW": "London", "CDG": "Paris", "AMS": "Amsterdam",
            "FRA": "Frankfurt", "MAD": "Madrid", "BCN": "Barcelona",
            "FCO": "Rome", "DXB": "Dubai", "DOH": "Doha", "SIN": "Singapore",
            "HKG": "Hong Kong", "ICN": "Seoul", "SYD": "Sydney",
            "YYZ": "Toronto", "MEX": "Mexico City"
        ]
        return map[iata] ?? iata
    }

    static func brandColor(for iataCode: String?) -> Color {
        switch iataCode?.uppercased() {
        case "AA": return Color(hex: "#0078D2")
        case "EK": return Color(hex: "#D71921")
        case "DL": return Color(hex: "#E01933")
        case "UA": return Color(hex: "#005DAA")
        case "BA": return Color(hex: "#075AAA")
        case "JL": return Color(hex: "#E60012")
        case "NH": return Color(hex: "#13448F")
        case "AF": return Color(hex: "#002B7F")
        case "LH": return Color(hex: "#05164D")
        default:   return Color(hex: "#0066CC")
        }
    }
}
