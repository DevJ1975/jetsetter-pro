// File: Features/TravelEssentials/TravelEssentialsView.swift
//
// Country-specific essentials: emergency numbers, tipping etiquette, electrical
// plug standards, water safety, scams, and phrases. Auto-selects the user's
// next trip destination but can be browsed by country.

import SwiftUI

struct TravelEssentialsView: View {

    // Optional on purpose: when the next-trip destination can't be resolved to a
    // known country we must NOT fall back to an arbitrary country — showing the
    // wrong emergency numbers / water-safety advice is dangerous. `nil` renders a
    // neutral "pick your destination" prompt instead.
    @State private var country: CountryEssentials? =
        TravelEssentialsData.find(query: TripsDestinationLookup.nextTripDestination() ?? "")

    @State private var showPicker = false
    @State private var copiedNumber: String?   // toast after copying (§7.7 — no dialer hand-off)

    var body: some View {
        ScrollView {
            if let country {
                VStack(spacing: 16) {
                    countryHero(country)
                    emergencyCard(country)
                    tippingCard(country)
                    electricalCard(country)
                    waterCard(country)
                    if !country.commonScams.isEmpty { scamsCard(country) }
                    if !country.phrases.isEmpty { phrasesCard(country) }
                }
                .padding(16)
                .padding(.bottom, 32)
            } else {
                emptyState
                    .padding(16)
            }
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Travel Essentials")
        .overlay(alignment: .bottom) {
            if let number = copiedNumber {
                Text("Copied \(number)")
                    .font(.footnote.bold())
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: copiedNumber)
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
            CountryPickerSheet(selectedCountry: $country)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe.badge.chevron.backward")
                .font(.system(size: 56))
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .padding(.top, 48)
            Text("Pick your destination")
                .font(.title2.bold())
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            Text("Choose a country to see local emergency numbers, tipping etiquette, plug types, and water-safety advice.")
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button { showPicker = true } label: {
                Label("Choose country", systemImage: "globe")
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

    // MARK: - Hero

    private func countryHero(_ country: CountryEssentials) -> some View {
        VStack(spacing: 8) {
            Text(country.flagEmoji)
                .font(.system(size: 72))
            Text(country.name)
                .font(.title.bold())
            Button { showPicker = true } label: {
                Label("Change country", systemImage: "globe")
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

    // MARK: - Cards

    private func emergencyCard(_ country: CountryEssentials) -> some View {
        cardWrapper(title: "EMERGENCY", systemImage: "exclamationmark.triangle.fill", tint: .red) {
            VStack(spacing: 8) {
                if let general = country.emergency.general {
                    callRow(label: "All Services", number: general, primary: true)
                }
                callRow(label: "Police",    number: country.emergency.police)
                callRow(label: "Ambulance", number: country.emergency.ambulance)
                callRow(label: "Fire",      number: country.emergency.fire)
                if let hotline = country.emergency.touristHotline {
                    callRow(label: "Tourist Help", number: hotline)
                }
            }
        }
    }

    private func tippingCard(_ country: CountryEssentials) -> some View {
        cardWrapper(title: "TIPPING", systemImage: "dollarsign.circle.fill", tint: JetsetterTheme.Colors.success) {
            VStack(alignment: .leading, spacing: 10) {
                detailRow(label: "Restaurants", value: country.tipping.restaurantPercent)
                detailRow(label: "Taxis",       value: country.tipping.taxiPercent)
                detailRow(label: "Hotel staff", value: country.tipping.hotelPerDay)
                if let note = country.tipping.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func electricalCard(_ country: CountryEssentials) -> some View {
        cardWrapper(title: "ELECTRICAL", systemImage: "bolt.fill", tint: .orange) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(country.electrical.plugTypes, id: \.self) { plug in
                        plugBadge(plug)
                    }
                    Spacer()
                }
                detailRow(label: "Voltage", value: country.electrical.voltage)
                if country.electrical.needsAdapterForUS {
                    Label("US travelers need a Type \(country.electrical.plugTypes.joined(separator: "/")) adapter", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                } else {
                    Label("US plugs work without an adapter", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(JetsetterTheme.Colors.success)
                }
            }
        }
    }

    private func waterCard(_ country: CountryEssentials) -> some View {
        cardWrapper(title: "TAP WATER", systemImage: "drop.fill", tint: country.waterSafe ? JetsetterTheme.Colors.success : .red) {
            VStack(alignment: .leading, spacing: 6) {
                Text(country.waterSafe ? "Safe to drink" : "Not safe — use bottled")
                    .font(.headline)
                    .foregroundStyle(country.waterSafe ? JetsetterTheme.Colors.success : .red)
                if let note = country.waterNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
        }
    }

    private func scamsCard(_ country: CountryEssentials) -> some View {
        cardWrapper(title: "WATCH OUT", systemImage: "eye.trianglebadge.exclamationmark.fill", tint: .yellow) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(country.commonScams, id: \.self) { scam in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .padding(.top, 2)
                        Text(scam)
                            .font(.subheadline)
                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    }
                }
            }
        }
    }

    private func phrasesCard(_ country: CountryEssentials) -> some View {
        cardWrapper(title: "USEFUL PHRASES", systemImage: "character.bubble.fill", tint: JetsetterTheme.Colors.accent) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(country.phrases, id: \.self) { phrase in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phrase.english)
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        HStack {
                            Text(phrase.local)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                            if let p = phrase.pronunciation, p != "—" {
                                Spacer()
                                Text(p)
                                    .font(.caption.italic())
                                    .foregroundStyle(JetsetterTheme.Colors.accent)
                            }
                        }
                    }
                    if phrase != country.phrases.last { Divider() }
                }
            }
        }
    }

    // MARK: - Reusable bits

    @ViewBuilder
    private func cardWrapper<Content: View>(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.bold())
                Text(title)
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(tint)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func callRow(label: String, number: String, primary: Bool = false) -> some View {
        Button {
            // iOS can't place a PSTN call in-app (§7.7) — copy the number instead.
            InAppActions.copyPhoneNumber(number)
            copiedNumber = number
            Task {
                try? await Task.sleep(for: .seconds(2))
                copiedNumber = nil
            }
        } label: {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "phone.fill")
                        .font(.caption.bold())
                    Text(number)
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                }
                .foregroundStyle(primary ? .white : .red)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(primary ? Color.red : Color.red.opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
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

    private func plugBadge(_ type: String) -> some View {
        VStack(spacing: 2) {
            Text("Type \(type)")
                .font(.system(.caption, design: .monospaced).weight(.black))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Country picker

private struct CountryPickerSheet: View {

    @Binding var selectedCountry: CountryEssentials?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [CountryEssentials] {
        if searchText.isEmpty { return TravelEssentialsData.countries }
        return TravelEssentialsData.countries.filter {
            $0.name.lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { entry in
                Button {
                    selectedCountry = entry
                    dismiss()
                } label: {
                    HStack {
                        Text(entry.flagEmoji)
                            .font(.system(size: 28))
                        Text(entry.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if entry.id == selectedCountry?.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(JetsetterTheme.Colors.accent)
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search countries")
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Helper

private enum TripsDestinationLookup {
    static func nextTripDestination() -> String? {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let trips = try? decoder.decode([Trip].self, from: data) else { return nil }
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
}

#Preview {
    NavigationStack {
        TravelEssentialsView()
    }
}
