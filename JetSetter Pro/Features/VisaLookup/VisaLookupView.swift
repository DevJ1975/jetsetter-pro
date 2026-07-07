// File: Features/VisaLookup/VisaLookupView.swift
//
// Visa & entry requirements for US passport holders. Auto-detects destination
// from the user's next trip and shows the badge, requirements, fees, and
// caveats with a single source-of-truth list at the bottom.

import SwiftUI

struct VisaLookupView: View {

    // Optional on purpose: when the next-trip destination can't be resolved to a
    // known country we must NOT fall back to an arbitrary country — showing the
    // wrong entry/visa requirements is dangerous. `nil` renders a neutral
    // "select a destination" prompt (and auto-opens the picker) instead.
    @State private var selected: VisaRequirement? =
        VisaRequirements.find(query: nextTripDestination() ?? "")

    @State private var showPicker = false
    @State private var webURL: URL?   // in-app web sheet target (§7.7)

    var body: some View {
        ScrollView {
            if let selected {
                VStack(spacing: 16) {
                    heroCard(selected)
                    requirementCard(selected)
                    passportCard(selected)
                    if !selected.additionalNotes.isEmpty { notesCard(selected) }
                    disclaimerCard
                }
                .padding(16)
                .padding(.bottom, 32)
            } else {
                emptyState
                    .padding(16)
            }
        }
        .background(JetsetterTheme.Colors.background)
        .inAppWeb(url: $webURL, title: "Travel.State.Gov")
        .navigationTitle("Visa Requirements")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showPicker = true } label: {
                    Image(systemName: "globe")
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            DestinationPickerSheet(selected: $selected)
        }
        .onAppear {
            // Never leave the user staring at a blank screen — if we couldn't
            // resolve their destination, open the picker so they choose one.
            if selected == nil { showPicker = true }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe.badge.chevron.backward")
                .font(.system(size: 56))
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .padding(.top, 48)
            Text("Select a destination")
                .font(.title2.bold())
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            Text("Choose a country to see visa and entry requirements for US passport holders.")
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button { showPicker = true } label: {
                Label("Choose destination", systemImage: "globe")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(JetsetterTheme.Colors.accent.opacity(0.12))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cards

    private func heroCard(_ selected: VisaRequirement) -> some View {
        VStack(spacing: 8) {
            Text(selected.flag)
                .font(.system(size: 64))
            Text(selected.countryName)
                .font(.title.bold())
            Text("For US passport holders")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button { showPicker = true } label: {
                Label("Change destination", systemImage: "globe")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(JetsetterTheme.Colors.accent.opacity(0.12))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func requirementCard(_ selected: VisaRequirement) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: selected.requirementKind.systemImage)
                    .font(.title3.bold())
                Text(selected.requirementKind.rawValue.uppercased())
                    .font(.system(size: 12, weight: .black))
                    .tracking(1.5)
            }
            .foregroundStyle(Color(hex: selected.requirementKind.colorHex))

            VStack(alignment: .leading, spacing: 10) {
                if let days = selected.maxStayDays {
                    detailRow(label: "Max stay", value: "\(days) days")
                }
                if let fee = selected.entryFee {
                    detailRow(label: "Fee", value: fee)
                }
                if selected.onwardTicketRequired {
                    detailRow(label: "Onward ticket", value: "Required")
                }
                // Schengen countries share a single 90-in-180 allowance across the
                // whole area, so a per-country "90 days" is misleading. If the
                // selected country is in Schengen, compute the *real* remaining
                // days from the user's stored trip history in the trailing
                // 180-day window instead of restating the flat limit.
                if Self.isSchengen(selected.destination) {
                    let remaining = Self.schengenDaysRemaining()
                    detailRow(
                        label: "Schengen days left",
                        value: "\(remaining) of \(Self.schengenAllowanceDays) days"
                    )
                    Text("Shared across all Schengen states in any rolling 180-day window, based on your saved trips.")
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(hex: selected.requirementKind.colorHex).opacity(0.3), lineWidth: 1)
        )
    }

    private func passportCard(_ selected: VisaRequirement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PASSPORT", systemImage: "doc.text.fill")
            VStack(alignment: .leading, spacing: 10) {
                detailRow(
                    label: "Validity required",
                    value: selected.passportValidityMonths == 0
                        ? "Valid through stay"
                        : "\(selected.passportValidityMonths) months after entry"
                )
                detailRow(label: "Blank pages required", value: "\(selected.blankPagesRequired)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func notesCard(_ selected: VisaRequirement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("GOOD TO KNOW", systemImage: "lightbulb.fill")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(selected.additionalNotes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                            .padding(.top, 8)
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private var disclaimerCard: some View {
        Button {
            webURL = URL(string: "https://travel.state.gov/content/travel/en/international-travel/International-Travel-Country-Information-Pages.html")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Always verify with State Department")
                        .font(.subheadline.bold())
                    Text("Requirements change. Open travel.state.gov →")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jetCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reusable

    private func sectionLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.caption.bold())
            Text(text)
                .font(JetsetterTheme.Typography.label)
                .tracking(1.5)
        }
        .foregroundStyle(JetsetterTheme.Colors.accent)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Trip lookup

    /// Decodes the user's stored trips from the same UserDefaults key the rest
    /// of the app uses. Returns `[]` when nothing is stored or decoding fails.
    private static func storedTrips() -> [Trip] {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips") else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Trip].self, from: data)) ?? []
    }

    private static func nextTripDestination() -> String? {
        let trips = storedTrips()
        guard !trips.isEmpty else { return nil }
        let now = Date()

        // Prefer the trip that's happening right now (startDate <= now < endDate)
        // — the previous filter (startDate > now) skipped the in-progress trip.
        if let inProgress = trips
            .filter({ $0.startDate <= now && now < $0.endDate })
            .sorted(by: { $0.startDate < $1.startDate })
            .first {
            return inProgress.destination
        }

        // Otherwise the soonest upcoming trip that hasn't ended yet.
        return trips
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .first?
            .destination
    }

    // MARK: - Schengen 90/180 computation

    /// Flat per-visit allowance shared across the whole Schengen area.
    static let schengenAllowanceDays = 90
    /// Rolling window the allowance is measured against.
    private static let schengenWindowDays = 180

    /// ISO 2-letter codes for the Schengen members represented in the dataset.
    /// (Ireland is deliberately excluded — it is not part of Schengen.)
    private static let schengenCodes: Set<String> = [
        "FR", "IT", "ES", "DE", "NL", "CH", "AT", "GR", "PT"
    ]

    static func isSchengen(_ isoCode: String) -> Bool {
        schengenCodes.contains(isoCode.uppercased())
    }

    /// Real "days remaining" against the 90-in-180 rule, computed from stored
    /// trips. Sums whole days spent in *any* Schengen country that fall inside
    /// the trailing 180-day window ending today, then subtracts from 90.
    ///
    /// A trip is only counted when its free-text destination resolves
    /// unambiguously (via `VisaRequirements.find`) to a Schengen member — this
    /// reuses the same conservative matcher the picker relies on, so we never
    /// over-count on a fuzzy destination string.
    static func schengenDaysRemaining(asOf reference: Date = Date()) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: reference)
        guard let windowStart = calendar.date(
            byAdding: .day, value: -(schengenWindowDays - 1), to: today
        ) else {
            return schengenAllowanceDays
        }

        var used = 0
        for trip in storedTrips() {
            guard let requirement = VisaRequirements.find(query: trip.destination),
                  isSchengen(requirement.destination) else { continue }

            // Clamp the trip to the rolling window before counting.
            let tripStart = calendar.startOfDay(for: trip.startDate)
            let tripEnd = calendar.startOfDay(for: trip.endDate)
            let overlapStart = max(tripStart, windowStart)
            let overlapEnd = min(tripEnd, today)
            guard overlapStart <= overlapEnd else { continue }

            // Inclusive day count (a same-day trip still consumes one day).
            let days = (calendar.dateComponents([.day], from: overlapStart, to: overlapEnd).day ?? 0) + 1
            used += days
        }

        return max(0, min(schengenAllowanceDays, schengenAllowanceDays - used))
    }
}

// MARK: - Picker sheet

private struct DestinationPickerSheet: View {
    @Binding var selected: VisaRequirement?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [VisaRequirement] {
        if search.isEmpty { return VisaRequirements.forUSPassport }
        return VisaRequirements.forUSPassport.filter {
            $0.countryName.lowercased().contains(search.lowercased())
        }
    }

    private var grouped: [(kind: RequirementKind, items: [VisaRequirement])] {
        let dict = Dictionary(grouping: filtered) { $0.requirementKind }
        return [.visaFree, .eTA, .eVisa, .visaOnArrival, .visaRequired, .otherDocsRequired]
            .compactMap { k in dict[k].map { (kind: k, items: $0) } }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.kind) { group in
                    Section(group.kind.rawValue) {
                        ForEach(group.items) { item in
                            Button {
                                selected = item
                                dismiss()
                            } label: {
                                HStack {
                                    Text(item.flag).font(.title2)
                                    Text(item.countryName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if item.id == selected?.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(JetsetterTheme.Colors.accent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search destinations")
            .navigationTitle("Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Color helper

private extension RequirementKind {
    var colorHex: String { color }
}

#Preview {
    NavigationStack { VisaLookupView() }
}
