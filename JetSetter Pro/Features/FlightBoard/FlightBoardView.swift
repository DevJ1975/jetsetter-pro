// File: Features/FlightBoard/FlightBoardView.swift
//
// Solari-style animated departure board. Shows the user's own flight at the
// top (when they have one), followed by a curated list of plausible departures
// from the same terminal. Tap a terminal pill to filter; the rows re-flip to
// the new values.

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
    let status: BoardStatus
    let isUserFlight: Bool

    init(
        id: UUID = UUID(),
        flightNumber: String,
        destinationIATA: String,
        destinationName: String,
        scheduledTime: String,
        gate: String,
        terminal: String,
        status: BoardStatus,
        isUserFlight: Bool = false
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
}

// MARK: - View

struct FlightBoardView: View {

    @State private var rows: [FlightBoardRow] = []
    @State private var selectedTerminal: String = "ALL"

    private var terminals: [String] {
        ["ALL"] + Array(Set(rows.map(\.terminal))).sorted()
    }

    private var filteredRows: [FlightBoardRow] {
        guard selectedTerminal != "ALL" else { return rows }
        return rows.filter { $0.terminal == selectedTerminal }
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
        .task { rows = FlightBoardData.generate() }
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
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle().fill(Color.green.opacity(0.4)).scaleEffect(2).blur(radius: 2)
                    )
                Text("LIVE")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(1.2)
            }
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
