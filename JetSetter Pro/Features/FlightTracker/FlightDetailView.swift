// File: Features/FlightTracker/FlightDetailView.swift

import SwiftUI

// MARK: - FlightDetailView

/// Full detail screen for a single flight, showing gate, terminal, timing, and status.
struct FlightDetailView: View {

    let flight: Flight

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: JetsetterTheme.Spacing.medium) {
                headerCard
                routeCard
                timingCard
                gateCard

                // Show baggage claim only if available
                if let baggageClaim = flight.baggageClaim {
                    baggageCard(claim: baggageClaim)
                }
            }
            .padding(JetsetterTheme.Spacing.medium)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(flight.identIata ?? flight.ident)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header Card (Airline + Status)

    private var headerCard: some View {
        VStack(spacing: JetsetterTheme.Spacing.small) {
            Text(flight.operatorName ?? "Unknown Airline")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(flight.identIata ?? flight.ident)
                .font(.largeTitle)
                .fontWeight(.bold)

            // Status pill
            Text(flight.status)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, JetsetterTheme.Spacing.medium)
                .padding(.vertical, JetsetterTheme.Spacing.small)
                .background(flight.status.flightStatusColor.opacity(0.15))
                .foregroundStyle(flight.status.flightStatusColor)
                .cornerRadius(20)

            // Progress bar (shown when flight is airborne)
            if flight.isAirborne, let progress = flight.progressPercent {
                flightProgressBar(percent: progress)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: - Route Card (ORD → JFK)

    private var routeCard: some View {
        HStack(alignment: .top) {
            airportColumn(
                code: flight.origin.codeIata ?? "—",
                city: flight.origin.displayName,
                alignment: .leading
            )

            Spacer()

            VStack(spacing: 4) {
                Image(systemName: "airplane")
                    .font(.title2)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                if let aircraftType = flight.aircraftType {
                    Text(aircraftType)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            airportColumn(
                code: flight.destination.codeIata ?? "—",
                city: flight.destination.displayName,
                alignment: .trailing
            )
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: - Timing Card

    private var timingCard: some View {
        VStack(spacing: 0) {
            timingRow(
                label: "Departs",
                scheduled: flight.scheduledOut,
                estimated: flight.estimatedOut,
                actual: flight.actualOut,
                delayMinutes: flight.departureDelayMinutes
            )

            Divider().padding(.horizontal, JetsetterTheme.Spacing.medium)

            timingRow(
                label: "Arrives",
                scheduled: flight.scheduledIn,
                estimated: flight.estimatedIn,
                actual: flight.actualIn,
                delayMinutes: flight.arrivalDelayMinutes
            )
        }
        .jetCard()
    }

    // MARK: - Gate Card

    private var gateCard: some View {
        HStack {
            gateColumn(
                label: "Departure Gate",
                gate: flight.gateOrigin,
                terminal: flight.terminalOrigin
            )

            Divider()
                .frame(height: 60)

            gateColumn(
                label: "Arrival Gate",
                gate: flight.gateDestination,
                terminal: flight.terminalDestination
            )
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: - Baggage Card

    private func baggageCard(claim: String) -> some View {
        HStack {
            Image(systemName: "suitcase.fill")
                .font(.title2)
                .foregroundStyle(JetsetterTheme.Colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Baggage Claim")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Carousel \(claim)")
                    .font(.headline)
            }

            Spacer()
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: - Subviews

    private func airportColumn(code: String, city: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(code)
                .font(.largeTitle)
                .fontWeight(.bold)
            Text(city)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func timingRow(
        label: String,
        scheduled: Date?,
        estimated: Date?,
        actual: Date?,
        delayMinutes: Int?
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // Show actual or estimated time as the primary time
                if let displayTime = actual ?? estimated ?? scheduled {
                    Text(timeFormatter.string(from: displayTime))
                        .font(.headline)
                } else {
                    Text("—")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                // Show scheduled time struck through if there is a delay
                if let scheduled = scheduled, let delay = delayMinutes, delay > 0 {
                    HStack(spacing: 4) {
                        Text(timeFormatter.string(from: scheduled))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .strikethrough()

                        Text("+\(delay)m")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(JetsetterTheme.Colors.warning)
                    }
                }
            }
        }
        .padding(JetsetterTheme.Card.padding)
    }

    private func gateColumn(label: String, gate: String?, terminal: String?) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(gate ?? "TBD")
                .font(.largeTitle)
                .fontWeight(.bold)

            if let terminal = terminal {
                Text("Terminal \(terminal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func flightProgressBar(percent: Int) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)

                    Capsule()
                        .fill(JetsetterTheme.Colors.accent)
                        .frame(width: geometry.size.width * CGFloat(percent) / 100, height: 6)
                }
            }
            .frame(height: 6)

            Text("\(percent)% complete")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, JetsetterTheme.Spacing.small)
    }
}

// MARK: - Preview

#Preview("On-Time Flight") {
    NavigationStack {
        FlightDetailView(flight: .sample)
    }
}

#Preview("Delayed Flight") {
    NavigationStack {
        FlightDetailView(flight: .sampleDelayed)
    }
}
