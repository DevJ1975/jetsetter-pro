// File: Features/FlightBoard/FlightBoardView.swift
//
// Solari-style animated departure board. Merges the user's own flight (when
// they have one) into a chronologically ordered list of illustrative sample
// departures, highlighting it via `isUserFlight` styling. Statuses re-derive
// on a 30s timer so the board behaves live and retires departed flights. Tap a
// terminal pill to filter; the rows re-flip to the new values.

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
    case onTime    = "ON TIME"
    case boarding  = "BOARDING"
    case delayed   = "DELAYED"
    case finalCall = "FINAL CALL"
    case departed  = "DEPARTED"
    case cancelled = "CANCELLED"

    var tint: Color {
        switch self {
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
    @State private var selectedTerminal: String = "ALL"

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
            // Preserve editorial states that aren't driven by the clock.
            if row.status != .delayed && row.status != .cancelled {
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
        }
        .navigationTitle("Departures")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task {
            rows = FlightBoardData.generate()
            // Keep the board live: re-derive statuses and retire departed flights
            // every 30s until the view goes away (the task is cancelled on disappear).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.4)) {
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
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(Color.yellow.opacity(0.85))
                Text(Self.boardDateString)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            // The departures other than the user's own flight are illustrative,
            // not fetched from a live flight-data feed. Badge it as "SAMPLE"
            // rather than "LIVE" so a traveller can't mistake these fabricated
            // rows for real departures from their airport.
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle().fill(Color.yellow.opacity(0.4)).scaleEffect(2).blur(radius: 2)
                    )
                Text("SAMPLE")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(1.2)
            }
            .accessibilityLabel("Sample departure board. Illustrative flights only.")
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
                        withAnimation(.spring(response: 0.3)) {
                            selectedTerminal = terminal
                        }
                    } label: {
                        Text(terminal == "ALL" ? "ALL" : "TERMINAL \(terminal)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Board

    private var boardList: some View {
        ScrollView {
            VStack(spacing: 6) {
                columnHeader
                ForEach(filteredRows) { row in
                    FlightBoardRowView(
                        row: row,
                        colFlight: colFlight,
                        colTo: colTo,
                        colTime: colTime,
                        colGate: colGate
                    )
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 32)
        }
    }

    // Column widths sized to actually fit the SplitFlap cell content
    // (char ~11pt wide, +1pt spacing). Tuned for iPhone 14/15 (390pt).
    private let colFlight: CGFloat = 74   // 6 chars
    private let colTo:     CGFloat = 38   // 3 chars
    private let colTime:   CGFloat = 62   // 5 chars (HH:MM)
    private let colGate:   CGFloat = 38   // 3 chars

    private var columnHeader: some View {
        HStack(spacing: 6) {
            columnTitle("FLIGHT",  width: colFlight)
            columnTitle("TO",      width: colTo)
            columnTitle("TIME",    width: colTime)
            columnTitle("GATE",    width: colGate)
            columnTitle("STATUS",  width: nil, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func columnTitle(_ text: String, width: CGFloat?, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(.white.opacity(0.4))
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

// MARK: - Single row

private struct FlightBoardRowView: View {

    let row: FlightBoardRow
    let colFlight: CGFloat
    let colTo: CGFloat
    let colTime: CGFloat
    let colGate: CGFloat

    // Character size tuned so 6-char flight numbers fit ~74pt and the
    // STATUS column has room for "BOARDING" / "FINAL CALL" on iPhone 14+.
    private let charW: CGFloat = 11
    private let charH: CGFloat = 18
    private let charFont: CGFloat = 12

    var body: some View {
        HStack(spacing: 6) {
            cell(row.flightNumber.padding(toLength: 6, withPad: " ", startingAt: 0), width: colFlight, tint: .yellow)
            cell(row.destinationIATA, width: colTo, tint: .yellow)
            cell(row.scheduledTime, width: colTime, tint: .yellow)
            cell(row.gate.padding(toLength: 3, withPad: " ", startingAt: 0), width: colGate, tint: .yellow)
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

// MARK: - Preview

#Preview {
    NavigationStack {
        FlightBoardView()
    }
}
