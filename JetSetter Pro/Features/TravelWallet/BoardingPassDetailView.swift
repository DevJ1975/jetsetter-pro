// File: Features/TravelWallet/BoardingPassDetailView.swift
//
// Full-screen boarding pass — Apple-Wallet-style. Airline color strip, large
// flight number, origin → destination IATA, full passenger info row, dotted
// tear-line, scannable QR code at the bottom. Shimmer + entry animation make
// it feel premium.
//
// The visible pass body is extracted into `BoardingPassCard` so it can be
// reused inline by other surfaces (e.g. the Check-In flow's success step).
//
// Accessibility, because this is the screen a traveler holds up at the gate:
//   • Text uses text styles (or `@ScaledMetric` for the display-size airport
//     codes), so it follows Dynamic Type. The GATE / SEAT labels used to be a
//     fixed 9 pt and never grew.
//   • From xxLarge text up, the three-column rows and the route stack
//     vertically so nothing truncates.
//   • VoiceOver hears one sentence for the pass (`accessibilitySummary`)
//     instead of a dozen fragments like "L A S", "airplane", "GATE", "C22".
//   • The QR code stays 180 pt at every text size, and nothing animates over
//     it: a shimmer crossing the code can make a gate scanner miss a read.
//     With Reduce Motion on, the shimmer and the reveal are skipped entirely.

import SwiftUI
import PassKit

// MARK: - BoardingPassDetailView

struct BoardingPassDetailView: View {

    let item: WalletItem
    @Bindable var viewModel: WalletViewModel
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .tripDayReadableWidth()
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
                .accessibilityLabel("Close boarding pass")
            }
        }
        .onAppear {
            // Reduce Motion: show the pass in place, no slide-up.
            guard !reduceMotion else {
                revealed = true
                return
            }
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
    /// When true, the card paints a subtle shimmer sweep over the pass details
    /// (never over the QR code), unless Reduce Motion is on.
    var showsShimmer: Bool = true
    @Bindable var viewModel: WalletViewModel
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var shimmerPhase: CGFloat = -1

    // Display sizes that have no matching text style. Scaled relative to the
    // nearest style so they still follow Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var routeCodeSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title2) private var headerIconSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title2) private var routeIconSize: CGFloat = 22

    /// The QR code's side. Deliberately not scaled: it must stay big enough to
    /// scan at every text size, and it never shrinks to make room for text.
    private static let qrSide: CGFloat = 180

    // MARK: Computed

    private var brandColor: Color { Self.brandColor(for: item.iataCode) }

    /// Three columns of 1/3 width stop fitting their labels around xxLarge, so
    /// from there every row (and the route) stacks vertically.
    private var stacksVertically: Bool { dynamicTypeSize >= .xxLarge }

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

    private var showsShimmerNow: Bool { showsShimmer && !reduceMotion }

    // MARK: Body

    var body: some View {
        VStack(spacing: 16) {
            passBody
            appleWalletButton
        }
    }

    private var passBody: some View {
        VStack(spacing: 0) {
            passDetails
            qrBlock
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Everything above the QR code. It's one VoiceOver element, and it's the
    /// only part the shimmer crosses.
    private var passDetails: some View {
        VStack(spacing: 0) {
            airlineHeader
            routeBlock
            tearLine
            detailsBlock
        }
        .overlay {
            if showsShimmerNow { shimmerOverlay }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilitySummary(for: item, seatOverride: seatOverride))
        .onAppear {
            guard showsShimmerNow else { return }
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
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Airline strip

    private var airlineHeader: some View {
        ZStack {
            brandColor

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.airline?.uppercased() ?? "AIRLINE")
                        .font(.system(.caption2, weight: .black))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("BOARDING PASS")
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "airplane.departure")
                    .font(.system(size: headerIconSize, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Route block

    private var routeBlock: some View {
        VStack(spacing: 14) {
            if stacksVertically {
                VStack(alignment: .leading, spacing: 6) {
                    airportColumn(item.departureAirport, alignment: .leading)
                    Image(systemName: "airplane")
                        .font(.system(size: routeIconSize, weight: .bold))
                        .foregroundStyle(brandColor)
                        .rotationEffect(.degrees(90))
                    airportColumn(item.arrivalAirport, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    airportColumn(item.departureAirport, alignment: .leading)
                    Spacer()
                    Image(systemName: "airplane")
                        .font(.system(size: routeIconSize, weight: .bold))
                        .foregroundStyle(brandColor)
                    Spacer()
                    airportColumn(item.arrivalAirport, alignment: .trailing)
                }
            }

            let footer = stacksVertically
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 8))
            footer {
                Text(item.flightNumber ?? "—")
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundStyle(brandColor)
                if !stacksVertically { Spacer() }
                Text(Self.flightDateString(for: item))
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.55))
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(Color.white)
    }

    private func airportColumn(_ code: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(code ?? "—")
                .font(.system(size: routeCodeSize, weight: .black, design: .monospaced))
                .foregroundStyle(.black)
            Text(Self.cityName(for: code) ?? "")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(.black.opacity(0.55))
                .tracking(1)
        }
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
            detailRow {
                detailCell("PASSENGER", value: passengerName, alignment: .leading)
                detailCell(cabinLabel, value: cabinValue, alignment: .center)
                detailCell(boardingLabel, value: Self.boardingTimeString(for: item), alignment: .trailing)
            }
            Divider().padding(.horizontal, 20)
            detailRow {
                detailCell("FLIGHT", value: item.flightNumber ?? "—", alignment: .leading)
                detailCell("GATE", value: item.gate ?? "—", alignment: .center, emphasis: true)
                detailCell("SEAT", value: effectiveSeat, alignment: .trailing, emphasis: true)
            }
            // GROUP / SEQUENCE are only shown when parsed from a real imported pass —
            // never fabricated, so a traveler is never handed a wrong boarding group.
            if item.boardingGroup != nil || item.boardingSequence != nil {
                Divider().padding(.horizontal, 20)
                detailRow {
                    detailCell("TERMINAL", value: item.terminal ?? "—", alignment: .leading)
                    detailCell("GROUP", value: item.boardingGroup ?? "—", alignment: .center)
                    detailCell("SEQUENCE", value: item.boardingSequence ?? "—", alignment: .trailing)
                }
            } else if let terminal = item.terminal {
                Divider().padding(.horizontal, 20)
                detailRow {
                    detailCell("TERMINAL", value: terminal, alignment: .leading)
                    if !stacksVertically {
                        Spacer().frame(maxWidth: .infinity)
                        Spacer().frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .background(Color.white)
    }

    /// Three cells side by side, or one under another from xxLarge text up.
    private func detailRow<Cells: View>(@ViewBuilder _ cells: () -> Cells) -> some View {
        let layout = stacksVertically
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        return layout { cells() }
    }

    private func detailCell(_ label: String, value: String, alignment: HorizontalAlignment, emphasis: Bool = false) -> some View {
        // Stacked rows read top to bottom, so every cell lines up on the leading edge.
        let effectiveAlignment: HorizontalAlignment = stacksVertically ? .leading : alignment
        return VStack(alignment: effectiveAlignment, spacing: 4) {
            Text(label)
                .font(.system(.caption2, weight: .black))
                .tracking(1.5)
                .foregroundStyle(.black.opacity(0.55))
            Text(value)
                .font(emphasis
                      ? .system(.title2, design: .monospaced, weight: .bold)
                      : .system(.subheadline, weight: .bold))
                .foregroundStyle(emphasis ? brandColor : .black)
                // Side by side, a long name may shrink a little to stay on one
                // line; stacked, it has the full width and wraps instead.
                .lineLimit(stacksVertically ? nil : 1)
                .minimumScaleFactor(stacksVertically ? 1 : 0.7)
        }
        .frame(maxWidth: .infinity, alignment: alignmentToFrameAlignment(effectiveAlignment))
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
                    .frame(width: Self.qrSide, height: Self.qrSide)
                    .padding(8)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
                    .accessibilityLabel("Boarding pass barcode")
                    .accessibilityAddTraits(.isImage)
            } else {
                // No real barcode captured — show the reference instead of a
                // fabricated code a gate scanner would reject.
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundStyle(.black.opacity(0.15))
                    .frame(width: Self.qrSide, height: Self.qrSide)
                    .accessibilityHidden(true)
            }
            Text(item.confirmationNumber ?? "—")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(.black.opacity(0.6))
                .tracking(2)
                .accessibilityLabel(confirmationAccessibilityLabel)
            Text(hasRealBarcode ? "Scan at gate" : "Reference only — use the airline's official pass to board")
                .font(.caption2)
                .foregroundStyle(.black.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
        .padding(.bottom, 22)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    /// "Confirmation code J L X R A Y": spelled letter by letter, because a
    /// record locator is read out to an agent, never pronounced as a word.
    private var confirmationAccessibilityLabel: Text {
        guard let code = item.confirmationNumber, !code.isEmpty, code != "—" else {
            return Text("No confirmation code on this pass")
        }
        return Text("Confirmation code ") + Text(code).speechSpellsOutCharacters()
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
                    .accessibilityHidden(true)
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

    // MARK: - Accessibility summary

    /// The one sentence VoiceOver reads for the whole pass, e.g.
    /// "Delta flight 1423, Las Vegas to Atlanta, departs 9:05 AM, gate C22,
    /// seat 3A". Terminal, boarding group and the boarding estimate follow
    /// when the pass has them.
    ///
    /// The departure time is spoken in the departure airport's zone, the same
    /// as the card shows it. A gate or seat the pass doesn't have yet is said
    /// as "not assigned yet", never guessed.
    static func accessibilitySummary(
        for item: WalletItem,
        seatOverride: String? = nil,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        var parts = [spokenFlight(for: item)]

        let codes = [item.departureAirport, item.arrivalAirport]
        if codes.contains(where: { TripSpeech.spokenValue($0, missing: "").isEmpty == false }) {
            parts.append(TripSpeech.spokenRoute(codes))
        }

        parts.append("departs \(spokenDeparture(for: item, locale: locale))")
        parts.append("gate \(TripSpeech.spokenValue(item.gate))")
        parts.append("seat \(TripSpeech.spokenValue(seatOverride ?? item.seatNumber))")

        let terminal = TripSpeech.spokenValue(item.terminal, missing: "")
        if !terminal.isEmpty { parts.append("terminal \(terminal)") }
        let group = TripSpeech.spokenValue(item.boardingGroup, missing: "")
        if !group.isEmpty { parts.append("boarding group \(group)") }
        if estimatedBoardingTime(for: item) != nil {
            parts.append("boarding about \(boardingTimeString(for: item, locale: locale)), estimated")
        }
        return parts.joined(separator: ", ")
    }

    /// "Delta flight 1423" from airline "Delta" and flight "DL1423". The
    /// designator is dropped because the airline name already says it, and
    /// "D L 1423" is how VoiceOver would otherwise read it.
    private static func spokenFlight(for item: WalletItem) -> String {
        let number = (item.flightNumber ?? "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        let hasNumber = !number.isEmpty && number != "—"
        let designator = hasNumber ? TravelStore.airlineDesignator(from: number) : ""
        let digits = hasNumber ? String(number.dropFirst(designator.count)) : ""

        let airline: String? = {
            let named = TripSpeech.spokenValue(item.airline, missing: "")
            if !named.isEmpty { return named }
            let code = (item.iataCode ?? designator).uppercased()
            return TravelProfileEngine.airlineCodeToName[code]
        }()

        switch (airline, hasNumber) {
        case let (name?, true):
            return "\(name) flight \(digits.isEmpty ? number : digits)"
        case let (name?, false):
            return "\(name) boarding pass"
        case (nil, true):
            return "Flight \(number)"
        case (nil, false):
            return "Boarding pass"
        }
    }

    /// The departure clock time in the departure airport's zone, or the
    /// flight's day when the pass only carries a day (a scanned barcode).
    private static func spokenDeparture(for item: WalletItem, locale: Locale) -> String {
        guard hasDepartureClockTime(item) else {
            return flightDateString(for: item, locale: locale)
        }
        if let zone = departureTimeZone(for: item) {
            return AppDateFormatters.airportTime(item.date, in: zone, style: .time, locale: locale)
        }
        let time = AppDateFormatters.airportTime(item.date, in: .current, style: .time, locale: locale)
        let abbreviation = TimeZone.current.abbreviation(for: item.date).map { " \($0)" } ?? ""
        return time + abbreviation
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
