// File: Features/Disruption/DisruptionDashboardView.swift
// Premium Disruption AI dashboard — shows active disruption cards, alternative
// flights with price/duration, one-tap rebook CTA, hotel notification status,
// Uber reroute button, and insurance doc quick-access.

import SwiftUI

// MARK: - DisruptionDashboardView

struct DisruptionDashboardView: View {

    @StateObject private var vm = DisruptionViewModel()
    @EnvironmentObject private var subscriptions: SubscriptionManager

    var body: some View {
        NavigationStack {
            ZStack {
                JetsetterTheme.Colors.background.ignoresSafeArea()

                if vm.isLoading && vm.activeDisruptions.isEmpty && vm.resolvedDisruptions.isEmpty {
                    loadingView
                } else if vm.activeDisruptions.isEmpty && vm.resolvedDisruptions.isEmpty {
                    emptyView
                } else {
                    disruptionList
                }
            }
            .navigationTitle("Disruption Monitor")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
                Button("Dismiss") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
        .premiumGate(feature: "Trip Disruption AI")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await vm.manualPoll() }
            } label: {
                if vm.isPolling {
                    ProgressView().tint(JetsetterTheme.Colors.accent)
                } else {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
            }
            .disabled(vm.isPolling)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(JetsetterTheme.Colors.accent)
            Text("Checking your flights…")
                .font(JetsetterTheme.Typography.bodyMedium)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(JetsetterTheme.Colors.success.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(JetsetterTheme.Colors.success)
            }

            VStack(spacing: 8) {
                Text("All Flights On Track")
                    .font(JetsetterTheme.Typography.pageTitle)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text("No disruptions detected. We're monitoring your active trips every 10 minutes in the background.")
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button { Task { await vm.manualPoll() } } label: {
                Label("Check Now", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(JetsetterTheme.Colors.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Disruption List

    private var disruptionList: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: []) {
                if !vm.activeDisruptions.isEmpty {
                    sectionHeader(
                        "\(vm.activeDisruptions.count) ACTIVE DISRUPTION\(vm.activeDisruptions.count == 1 ? "" : "S")",
                        icon: "exclamationmark.triangle.fill",
                        color: JetsetterTheme.Colors.danger
                    )
                    ForEach(vm.activeDisruptions) { event in
                        DisruptionEventCard(event: event, vm: vm)
                    }
                }

                if !vm.resolvedDisruptions.isEmpty {
                    sectionHeader("RESOLVED", icon: "checkmark.circle.fill",
                                  color: JetsetterTheme.Colors.success)
                    ForEach(vm.resolvedDisruptions.prefix(5)) { event in
                        ResolvedDisruptionRow(event: event)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption.bold())
            Text(title).font(JetsetterTheme.Typography.label).tracking(1.5)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }
}

// MARK: - DisruptionEventCard

struct DisruptionEventCard: View {

    let event: DisruptionEvent
    @ObservedObject var vm: DisruptionViewModel

    @State private var isExpanded = false
    @State private var selectedAlt: AlternativeFlight? = nil

    var body: some View {
        VStack(spacing: 0) {
            headerSection.padding(16)

            if isExpanded {
                Divider().overlay(JetsetterTheme.Colors.separator)
                expandedSection.padding(16)
            }
        }
        .jetCard()
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Type badge + timestamp
            HStack {
                disruptionBadge
                Spacer()
                Text(event.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }

            // Flight row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.originalFlight.flightNumber)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text("\(event.originalFlight.origin)  →  \(event.originalFlight.destination)")
                        .font(.subheadline)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    Text(event.originalFlight.airline)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
                Spacer()
                // Delay badge
                if let delay = event.originalFlight.delayMinutes, delay > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("+\(delay)m")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(JetsetterTheme.Colors.warning)
                        Text("delay")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                }
            }

            // Response-action status strip
            responseActionsStrip

            // Expand toggle
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(isExpanded ? "Hide Options" : "View Options & Actions")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                }
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private var disruptionBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: event.eventType.systemImage).font(.caption.bold())
            Text(event.eventType.displayName.uppercased())
                .font(JetsetterTheme.Typography.label)
                .tracking(0.5)
        }
        .foregroundStyle(Color(hex: event.eventType.colorHex))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(hex: event.eventType.colorHex).opacity(0.12))
        .clipShape(Capsule())
    }

    private var responseActionsStrip: some View {
        HStack(spacing: 14) {
            responseIcon("airplane.departure",  active: event.responseActions.alternativesFound,  label: "Alts")
            responseIcon("building.2.fill",     active: event.responseActions.hotelNotified,      label: "Hotel")
            responseIcon("car.fill",            active: event.responseActions.uberRerouteReady,   label: "Uber")
            responseIcon("shield.fill",         active: event.responseActions.insuranceSurfaced,  label: "Insure")
        }
    }

    private func responseIcon(_ icon: String, active: Bool, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(active
                    ? JetsetterTheme.Colors.success
                    : JetsetterTheme.Colors.textSecondary.opacity(0.35))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(active
                    ? JetsetterTheme.Colors.success
                    : JetsetterTheme.Colors.textSecondary.opacity(0.35))
        }
    }

    // MARK: Expanded Section

    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Alternative flights
            if !event.alternatives.isEmpty {
                alternativeFlightsSection
            }

            // Action buttons
            actionButtonsSection

            // Resolve button
            Button { Task { await vm.resolveDisruption(event) } } label: {
                Text("Mark as Resolved")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(JetsetterTheme.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Alternative Flights

    private var alternativeFlightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALTERNATIVE FLIGHTS")
                .font(JetsetterTheme.Typography.label)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .tracking(1.5)

            ForEach(event.alternatives) { alt in
                AlternativeFlightCard(
                    flight: alt,
                    isSelected: selectedAlt?.id == alt.id
                ) { selectedAlt = (selectedAlt?.id == alt.id) ? nil : alt }
            }

            // Rebook CTA — only shown when user has tapped an alternative
            if let chosen = selectedAlt {
                Button { vm.openRebookingURL(for: event, alternative: chosen) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Rebook \(chosen.flightNumber) — \(chosen.priceFormatted)")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(JetsetterTheme.Colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: JetsetterTheme.Colors.accent.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedAlt?.id)
    }

    // MARK: Action Buttons

    private var actionButtonsSection: some View {
        VStack(spacing: 10) {
            if event.responseActions.uberRerouteReady {
                DisruptionActionButton(
                    title: "Open Uber to Updated Gate",
                    icon: "car.fill",
                    colorHex: "#1C2B3A"
                ) { vm.openUberReroute(for: event) }
            }

            if event.responseActions.hotelNotified, event.hotelContact != nil {
                DisruptionActionButton(
                    title: "Email Hotel About Late Arrival",
                    icon: "envelope.fill",
                    colorHex: "#0A7A5E"
                ) { Task { await vm.openHotelEmail(for: event) } }
            }

            if event.responseActions.insuranceSurfaced {
                DisruptionActionButton(
                    title: "View Travel Insurance",
                    icon: "shield.fill",
                    colorHex: "#7B3FBF"
                ) {
                    // Navigate to Document Vault — wire up NavigationPath in parent if needed
                }
            }
        }
    }
}

// MARK: - AlternativeFlightCard

struct AlternativeFlightCard: View {

    let flight: AlternativeFlight
    let isSelected: Bool
    let onTap: () -> Void

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Carrier code badge
                Text(flight.airline)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .frame(width: 44, height: 44)
                    .background(JetsetterTheme.Colors.surfaceElevated)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(flight.flightNumber)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    HStack(spacing: 4) {
                        Text(Self.timeFmt.string(from: flight.departure))
                        Text("→")
                        Text(Self.timeFmt.string(from: flight.arrival))
                        Text("·")
                        Text(flight.durationFormatted)
                    }
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(flight.priceFormatted)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text(flight.cabinClass)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                          ? JetsetterTheme.Colors.accent.opacity(0.10)
                          : JetsetterTheme.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? JetsetterTheme.Colors.accent : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ResolvedDisruptionRow

struct ResolvedDisruptionRow: View {

    let event: DisruptionEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(JetsetterTheme.Colors.success)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.eventType.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text(event.originalFlight.flightNumber + "  ·  "
                     + event.originalFlight.origin + " → " + event.originalFlight.destination)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }

            Spacer()

            Text(event.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
        .padding(14)
        .jetCard()
    }
}

// MARK: - DisruptionActionButton

private struct DisruptionActionButton: View {

    let title: String
    let icon: String
    let colorHex: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color(hex: colorHex))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DisruptionDashboardView()
            .environmentObject(SubscriptionManager.shared)
    }
}
