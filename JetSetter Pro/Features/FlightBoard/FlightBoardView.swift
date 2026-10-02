// File: Features/FlightBoard/FlightBoardView.swift
//
// Solari-style animated departure board of the traveler's own upcoming flights.
// With no flights on file it shows a clearly labeled sample board. Statuses
// re-derive on a 30s timer so the board behaves live and retires departed
// flights. Tap a terminal pill to filter; the rows re-flip to the new values.
//
// Accessibility:
//   • Each row is one VoiceOver element with one sentence ("Your flight DL1423
//     to Atlanta, departs 09:05, gate C22, scheduled"), so VoiceOver never
//     reads the split-flap characters halfway through a flip.
//   • The flap tiles are a fixed-size picture, like a QR code. From xxLarge
//     text up the rows switch to plain Dynamic Type text instead of tiles, so
//     a traveler who asked for bigger text gets it.
//   • Column widths come from the tile size and the longest value, not from
//     numbers tuned for one 390 pt phone; a far-future "OCT 5 14:30" used to
//     run into the gate column.

import SwiftUI

// MARK: - Model

struct FlightBoardRow: Identifiable, Equatable {
    let id: UUID
    let flightNumber: String
    let destinationIATA: String
    let destinationName: String
    let scheduledTime: String   // e.g. "18:25"
    let gate: String
    let terminal: String
    var status: BoardStatus
    let isUserFlight: Bool

    /// Fixed scheduled departure instant used to keep the board live: statuses
    /// are re-derived from this against the current time (see `status(minutesAway:)`)
    /// and the board is sorted chronologically by it. Optional because a user
    /// flight with an unparseable date can still be shown.
    let departureDate: Date?

    init(
        id: UUID = UUID(),
        flightNumber: String,
        destinationIATA: String,
        destinationName: String,
        scheduledTime: String,
        gate: String,
        terminal: String,
        status: BoardStatus,
        isUserFlight: Bool = false,
        departureDate: Date? = nil
    ) {
        self.id = id
        self.flightNumber = flightNumber
        self.destinationIATA = destinationIATA
        self.destinationName = destinationName
        self.scheduledTime = scheduledTime
        self.gate = gate
        self.terminal = terminal
        self.status = status
        self.isUserFlight = isUserFlight
        self.departureDate = departureDate
    }
}

enum BoardStatus: String, CaseIterable {
    /// Neutral state for the traveler's own flights: the board has no live
    /// airline feed, so it states the timetable and nothing more. The airline
    /// statuses below are only for the labeled SAMPLE board.
    case scheduled = "SCHEDULED"
    case onTime    = "ON TIME"
    case boarding  = "BOARDING"
    case delayed   = "DELAYED"
    case finalCall = "FINAL CALL"
    case departed  = "DEPARTED"
    case cancelled = "CANCELLED"

    var tint: Color {
        switch self {
        case .scheduled:                     return Color(white: 0.75)
        case .onTime, .boarding, .departed: return .green
        case .delayed:                       return .orange
        case .finalCall:                     return .yellow
        case .cancelled:                     return .red
        }
    }

    /// Derives a live status from how many minutes remain until departure.
    /// Shared by the initial board build and the periodic live refresh so
    /// thresholds stay in one place. `.delayed`/`.cancelled` are editorial
    /// states not driven by the clock, so callers pass them through unchanged.
    static func live(minutesAway: Int) -> BoardStatus {
        switch minutesAway {
        case ..<(-5):  return .departed
        case ..<15:    return .finalCall
        case 15..<45:  return .boarding
        default:       return .onTime
        }
    }
}

// MARK: - View

struct FlightBoardView: View {

    @State private var rows: [FlightBoardRow] = []
    @State private var isSample = false
    @State private var selectedTerminal: String = "ALL"
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Larger text sizes get plain text rows instead of fixed-size flap tiles.
    private var usesTextRows: Bool { dynamicTypeSize >= .xxLarge }

    private var terminals: [String] {
        // Unknown-terminal rows (empty string) only surface under "ALL", so
        // don't offer an empty "TERMINAL " pill.
        let named = rows.map(\.terminal).filter { !$0.isEmpty }
        return ["ALL"] + Array(Set(named)).sorted()
    }

    private var filteredRows: [FlightBoardRow] {
        guard selectedTerminal != "ALL" else { return rows }
        return rows.filter { $0.terminal == selectedTerminal }
    }

    /// Re-derives clock-driven statuses from each row's fixed departure instant
    /// and drops flights that departed a while ago, so the board behaves live
    /// without regenerating (which would reset the sample schedule each tick).
    private static func refreshed(_ rows: [FlightBoardRow]) -> [FlightBoardRow] {
        let now = Date()
        return rows.compactMap { row in
            guard let departure = row.departureDate else { return row }
            let minutesAway = Int(departure.timeIntervalSince(now) / 60)
            // Clear the board of flights that left more than ~30 min ago.
            guard minutesAway > -30 else { return nil }
            var updated = row
            // Only the labeled sample rows tick through clock-driven statuses.
            // The traveler's own flights stay "SCHEDULED": calling one
            // BOARDING or FINAL CALL from the clock would invent an airline
            // status. Editorial sample states (delayed/cancelled) stay as authored.
            if !row.isUserFlight && row.status != .delayed && row.status != .cancelled {
                updated.status = BoardStatus.live(minutesAway: minutesAway)
            }
            return updated
        }
    }

    var body: some View {
        ZStack {
            // Deep midnight background — boards are always shown in dim airport halls
            LinearGradient(
                colors: [Color(white: 0.02), Color(red: 0.04, green: 0.05, blue: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                header
                terminalPicker
                boardList
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .tripDayReadableWidth()
        }
        .navigationTitle("Departures")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task {
            let board = FlightBoardData.generate()
            rows = board.rows
            isSample = board.isSample
            // Keep the board live: re-derive statuses and retire departed flights
            // every 30s until the view goes away (the task is cancelled on disappear).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                    rows = Self.refreshed(rows)
                }
            }
        }
        .onChange(of: rows) { _, _ in
            // If the currently selected terminal no longer has any flights (its
            // last departure just left the board), fall back to "ALL" so the
            // user isn't left staring at an empty filtered board.
            if selectedTerminal != "ALL", !terminals.contains(selectedTerminal) {
                selectedTerminal = "ALL"
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DEPARTURES")
                    .font(.system(.caption2, design: .rounded, weight: .black))
                    .tracking(2.5)
                    .foregroundStyle(Color.yellow.opacity(0.85))
                    .accessibilityAddTraits(.isHeader)
                Text(Self.boardDateString)
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            // Rows are the traveler's own itinerary flights; the app has no
            // airport-wide feed. With none on file the board is a labeled sample.
            HStack(spacing: 6) {
                Circle()
                    .fill(isSample ? Color.yellow : Color.green)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle().fill((isSample ? Color.yellow : Color.green).opacity(0.4)).scaleEffect(2).blur(radius: 2)
                    )
                Text(isSample ? "SAMPLE" : "MY FLIGHTS")
                    .font(.system(.caption2, weight: .black))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(1.2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isSample ? "Sample departure board. Illustrative flights only." : "Your upcoming flights.")
        }
        .padding(.horizontal, 4)
    }

    private static var boardDateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEE  MMM d  ·  HH:mm"
        return f.string(from: Date()).uppercased()
    }

    // MARK: - Terminal picker

    private var terminalPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(terminals, id: \.self) { terminal in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                            selectedTerminal = terminal
                        }
                    } label: {
                        Text(terminal == "ALL" ? "ALL" : "TERMINAL \(terminal)")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .tracking(1.5)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    selectedTerminal == terminal
                                        ? Color.yellow.opacity(0.18)
                                        : Color.white.opacity(0.06)
                                )
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    selectedTerminal == terminal
                                        ? Color.yellow.opacity(0.6)
                                        : Color.white.opacity(0.12),
                                    lineWidth: 0.5
                                )
                            )
                            .foregroundStyle(
                                selectedTerminal == terminal ? .yellow : .white.opacity(0.7)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(terminal == "ALL" ? "All terminals" : "Terminal \(terminal)")
                    .accessibilityAddTraits(selectedTerminal == terminal ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Board

    private var boardList: some View {
        ScrollView {
            VStack(spacing: 6) {
                if !usesTextRows { columnHeader }
                ForEach(filteredRows) { row in
                    Group {
                        if usesTextRows {
                            FlightBoardTextRowView(row: row)
                        } else {
                            FlightBoardRowView(row: row, columns: columns)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.accessibilityText(for: row))
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 32)
        }
    }

    /// "Your flight DL1423 to Atlanta, departs 09:05, gate C22, scheduled".
    /// Read from the row's values, never from the flap tiles, which may be
    /// halfway through a flip.
    static func accessibilityText(for row: FlightBoardRow) -> String {
        var parts = [
            "\(row.isUserFlight ? "Your flight" : "Flight") \(row.flightNumber) to \(TripSpeech.spokenAirport(row.destinationIATA))",
            "departs \(row.scheduledTime)",
            "gate \(TripSpeech.spokenValue(row.gate))"
        ]
        if !row.terminal.isEmpty { parts.append("terminal \(row.terminal)") }
        parts.append(row.status.rawValue.lowercased())
        return parts.joined(separator: ", ")
    }

    /// Column widths for the flap tiles, from the tile size and the longest
    /// value in each column (a far-future time carries its date).
    private var columns: FlightBoardColumns {
        FlightBoardColumns(timeCharacters: max(5, rows.map(\.scheduledTime.count).max() ?? 5))
    }

    private var columnHeader: some View {
        HStack(spacing: FlightBoardColumns.spacing) {
            columnTitle("FLIGHT",  width: columns.flight)
            columnTitle("TO",      width: columns.to)
            columnTitle("TIME",    width: columns.time)
            columnTitle("GATE",    width: columns.gate)
            columnTitle("STATUS",  width: nil, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        // Each row already says what every column holds.
        .accessibilityHidden(true)
    }

    private func columnTitle(_ text: String, width: CGFloat?, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .black))
            .tracking(1.5)
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

// MARK: - Column metrics

/// Flap-tile geometry and the column widths that follow from it. A column is
/// as wide as its characters plus the 1 pt gap `SplitFlapText` puts between them.
struct FlightBoardColumns {
    static let characterWidth: CGFloat = 11
    static let characterHeight: CGFloat = 18
    static let fontSize: CGFloat = 12
    static let spacing: CGFloat = 6

    var timeCharacters: Int = 5

    static func width(forCharacters count: Int) -> CGFloat {
        CGFloat(count) * characterWidth + CGFloat(max(count - 1, 0))
    }

    var flight: CGFloat { Self.width(forCharacters: 6) }
    var to: CGFloat     { Self.width(forCharacters: 3) }
    var time: CGFloat   { Self.width(forCharacters: timeCharacters) }
    var gate: CGFloat   { Self.width(forCharacters: 3) }
}

// MARK: - Single row

private struct FlightBoardRowView: View {

    let row: FlightBoardRow
    let columns: FlightBoardColumns

    private let charW = FlightBoardColumns.characterWidth
    private let charH = FlightBoardColumns.characterHeight
    private let charFont = FlightBoardColumns.fontSize

    var body: some View {
        HStack(spacing: FlightBoardColumns.spacing) {
            cell(row.flightNumber.padding(toLength: 6, withPad: " ", startingAt: 0), width: columns.flight, tint: .yellow)
            cell(row.destinationIATA, width: columns.to, tint: .yellow)
            cell(row.scheduledTime, width: columns.time, tint: .yellow)
            cell(row.gate.padding(toLength: 3, withPad: " ", startingAt: 0), width: columns.gate, tint: .yellow)
            cell(row.status.rawValue, width: nil, tint: row.status.tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(row.isUserFlight
                      ? JetsetterTheme.Colors.accent.opacity(0.12)
                      : Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    row.isUserFlight
                        ? JetsetterTheme.Colors.accent.opacity(0.45)
                        : Color.white.opacity(0.05),
                    lineWidth: row.isUserFlight ? 1 : 0.5
                )
        )
    }

    @ViewBuilder
    private func cell(_ text: String, width: CGFloat?, tint: Color) -> some View {
        if let width {
            SplitFlapText(
                text: text,
                characterWidth: charW,
                characterHeight: charH,
                fontSize: charFont,
                tint: tint
            )
            .frame(width: width, alignment: .leading)
        } else {
            SplitFlapText(
                text: text,
                characterWidth: charW,
                characterHeight: charH,
                fontSize: charFont,
                tint: tint
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Text row (larger text sizes)

/// The same row as plain Dynamic Type text, for xxLarge text and up, where
/// fixed-size flap tiles would stay small or run off the screen.
private struct FlightBoardTextRowView: View {

    let row: FlightBoardRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.flightNumber)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.yellow)
                Spacer(minLength: 8)
                Text(row.status.rawValue)
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundStyle(row.status.tint)
                    .multilineTextAlignment(.trailing)
            }
            Text("TO \(row.destinationIATA) · \(row.scheduledTime) · GATE \(row.gate)")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(row.isUserFlight
                      ? JetsetterTheme.Colors.accent.opacity(0.12)
                      : Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    row.isUserFlight
                        ? JetsetterTheme.Colors.accent.opacity(0.45)
                        : Color.white.opacity(0.05),
                    lineWidth: row.isUserFlight ? 1 : 0.5
                )
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FlightBoardView()
    }
}
