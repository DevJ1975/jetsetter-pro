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
    @Bindable var viewModel: WalletViewModel
    @Environment(UserPreferences.self) private var preferences
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
    @Bindable var viewModel: WalletViewModel
    @Environment(UserPreferences.self) private var preferences

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

    /// Cabin cell label — "CLASS" when we know it, "CLASS (EST.)" when it's only
    /// a seat-row heuristic, so an inferred value is never presented as fact.
    private var cabinLabel: String {
        item.cabinClass != nil ? "CLASS" : "CLASS (EST.)"
    }

    /// "BOARDING (EST.)" whenever a time is shown, because it's always counted
    /// back from departure; plain "BOARDING" over a "—".
    private var boardingLabel: String {
        Self.estimatedBoardingTime(for: item) == nil ? "BOARDING" : "BOARDING (EST.)"
    }

    /// Explicit cabin class when the pass carried one; otherwise the seat-row
    /// heuristic as a best-effort estimate.
    private var cabinValue: String {
        if let cabin = item.cabinClass, !cabin.isEmpty { return cabin.uppercased() }
        return Self.classFromSeat(effectiveSeat)
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
                Text(Self.flightDateString(for: item))
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
                detailCell(cabinLabel, value: cabinValue, alignment: .center)
                detailCell(boardingLabel, value: Self.boardingTimeString(for: item), alignment: .trailing)
            }
            Divider().padding(.horizontal, 20)
            HStack(alignment: .top, spacing: 0) {
                detailCell("FLIGHT", value: item.flightNumber ?? "—", alignment: .leading)
                detailCell("GATE", value: item.gate ?? "—", alignment: .center, emphasis: true)
                detailCell("SEAT", value: effectiveSeat, alignment: .trailing, emphasis: true)
            }
            // GROUP / SEQUENCE are only shown when parsed from a real imported pass —
            // never fabricated, so a traveler is never handed a wrong boarding group.
            if item.boardingGroup != nil || item.boardingSequence != nil {
                Divider().padding(.horizontal, 20)
                HStack(alignment: .top, spacing: 0) {
                    detailCell("TERMINAL", value: item.terminal ?? "—", alignment: .leading)
                    detailCell("GROUP", value: item.boardingGroup ?? "—", alignment: .center)
                    detailCell("SEQUENCE", value: item.boardingSequence ?? "—", alignment: .trailing)
                }
            } else if let terminal = item.terminal {
                Divider().padding(.horizontal, 20)
                HStack(alignment: .top, spacing: 0) {
                    detailCell("TERMINAL", value: terminal, alignment: .leading)
                    Spacer().frame(maxWidth: .infinity)
                    Spacer().frame(maxWidth: .infinity)
                }
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
            if let payload = qrPayload,
               let qr = QRCodeGenerator.image(from: payload, size: 200) {
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
            } else {
                // No real barcode captured — show the reference instead of a
                // fabricated code a gate scanner would reject.
                Image(systemName: "qrcode")
                    .font(.system(size: 60))
                    .foregroundStyle(.black.opacity(0.15))
                    .frame(width: 180, height: 180)
            }
            Text(item.confirmationNumber ?? "—")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.black.opacity(0.6))
                .tracking(2)
            Text(hasRealBarcode ? "Scan at gate" : "Reference only — use the airline's official pass to board")
                .font(.caption2)
                .foregroundStyle(.black.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 22)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    /// True when the pass carried a genuine barcode message we can reproduce.
    private var hasRealBarcode: Bool {
        !(item.barcodeMessage?.isEmpty ?? true)
    }

    /// The QR content. Only reproduces a genuine imported barcode message — we
    /// never synthesize a scannable-looking payload that could be mistaken for a
    /// boarding credential. Returns nil when no real barcode is available.
    private var qrPayload: String? {
        item.barcodeMessage.flatMap { $0.isEmpty ? nil : $0 }
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

    /// The zone the pass's times belong to. `item.date` is an absolute instant,
    /// and a boarding pass is read at the departure airport, so it renders in
    /// that airport's zone: an explicit `departure_timezone` identifier when the
    /// pass carried one, else the origin airport's zone. Nil when neither is
    /// known; callers then fall back to the device zone and say so.
    ///
    /// The defect this replaces: only `departure_timezone` was consulted, which
    /// nothing in the app ever writes, so every pass rendered in the phone's
    /// zone and a LAS departure viewed on an Atlanta phone was three hours off.
    static func departureTimeZone(for item: WalletItem) -> TimeZone? {
        if let zone = item.rawData["departure_timezone"].flatMap({ TimeZone(identifier: $0) }) {
            return zone
        }
        return item.departureAirport.flatMap { AirportCoordinates.timeZone(for: $0) }
    }

    /// True when `item.date` is a real departure clock time rather than just a
    /// day or an unrelated instant. A scanned BCBP barcode carries only the
    /// flight's day (midnight on the phone's calendar), and an imported .pkpass
    /// stores its `relevantDate` (when Wallet surfaces the pass), or the import
    /// time when it has none. Neither is a departure time to count back from.
    static func hasDepartureClockTime(_ item: WalletItem) -> Bool {
        if item.rawData["source"] == "bcbp_scan" { return false }
        if item.rawData["pkpass_data"] != nil { return false }
        return true
    }

    /// Estimated boarding: 30 minutes before departure. No pass source in the
    /// app (BCBP, .pkpass, manual entry) carries the airline's boarding time,
    /// so this is always an estimate, labelled "EST." on the card, and nil when
    /// there's no departure time to count back from.
    static func estimatedBoardingTime(for item: WalletItem) -> Date? {
        guard hasDepartureClockTime(item) else { return nil }
        return item.date.addingTimeInterval(-30 * 60)
    }

    /// The boarding cell's value: "—" when the time isn't known, otherwise the
    /// estimate in the departure airport's zone and the user's 12/24-hour
    /// preference. Without a known zone it falls back to the phone's zone and
    /// appends that zone's abbreviation so the time can't be silently misread.
    static func boardingTimeString(for item: WalletItem, locale: Locale = .autoupdatingCurrent) -> String {
        guard let boarding = estimatedBoardingTime(for: item) else { return "—" }
        if let zone = departureTimeZone(for: item) {
            return AppDateFormatters.airportTime(boarding, in: zone, style: .time, locale: locale)
        }
        let time = AppDateFormatters.airportTime(boarding, in: .current, style: .time, locale: locale)
        let abbreviation = TimeZone.current.abbreviation(for: boarding).map { " \($0)" } ?? ""
        return time + abbreviation
    }

    /// The date under the flight number, on the departure airport's calendar
    /// so a late-evening departure doesn't print as the next day. A scanned
    /// barcode's day was built on the phone's calendar, so it stays there.
    static func flightDateString(for item: WalletItem, locale: Locale = .autoupdatingCurrent) -> String {
        let zone = item.rawData["source"] == "bcbp_scan" ? TimeZone.current : (departureTimeZone(for: item) ?? .current)
        return AppDateFormatters.airportTime(item.date, in: zone, style: .weekdayDate, locale: locale)
    }

    /// Best-effort cabin estimate from the seat row when no explicit cabin_class
    /// is available. This is a rough heuristic (aircraft layouts vary widely), so
    /// callers must label the result as an estimate — never present it as fact.
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
