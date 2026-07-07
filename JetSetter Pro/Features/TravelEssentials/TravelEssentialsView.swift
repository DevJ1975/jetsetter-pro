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
    @State private var copiedNumber: String?   // toast after copy (secondary long-press action)
    @Environment(\.openURL) private var openURL

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
                // Phrased around the destination's own standard rather than a
                // US-origin assumption — a user flying UK→France or EU→US should
                // not be told "US plugs work". The `needsAdapterForUS` flag still
                // usefully distinguishes the (common) Type A/B origin from the
                // rest, so we surface it as a hint, not an absolute statement.
                Label(
                    "Type \(country.electrical.plugTypes.joined(separator: "/")) sockets — compare to your home standard",
                    systemImage: "powerplug.fill"
                )
                .font(.caption.bold())
                .foregroundStyle(.orange)
                if !country.electrical.needsAdapterForUS {
                    Label("Same Type A/B plugs used in North America — no adapter needed if that's your home standard", systemImage: "checkmark.circle.fill")
                        .font(.caption)
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
            // Primary action: hand off to the system dialer. `tel:` URLs are fully
            // supported — in an emergency the user should not have to copy the
            // number, leave the app, open Phone, and paste. Copy stays available
            // as a long-press fallback (dialer strips characters it can't dial).
            call(number)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Call \(label), \(number)")
        .accessibilityHint("Double tap to dial. Touch and hold to copy the number.")
        .contextMenu {
            Button {
                call(number)
            } label: {
                Label("Call \(number)", systemImage: "phone.fill")
            }
            Button {
                copy(number)
            } label: {
                Label("Copy number", systemImage: "doc.on.doc")
            }
        }
    }

    /// Opens the system dialer for a printed emergency number. Strips spaces,
    /// hyphens, and parentheses so multi-part numbers (e.g. "050-3816-2787")
    /// still produce a valid `tel:` URL. Falls back to copying when the number
    /// can't be turned into a dialable URL (e.g. non-numeric hotline text).
    private func call(_ number: String) {
        let allowed = CharacterSet(charactersIn: "+0123456789")
        let digits = number.unicodeScalars.filter { allowed.contains($0) }
        let sanitized = String(String.UnicodeScalarView(digits))
        guard !sanitized.isEmpty, let url = URL(string: "tel://\(sanitized)") else {
            copy(number)
            return
        }
        openURL(url) { accepted in
            // If the device can't place calls (e.g. iPad/no cellular), fall back
            // to copying so the number is still one paste away.
            if !accepted { copy(number) }
        }
    }

    /// Secondary action: copy the number and surface a confirmation toast.
    private func copy(_ number: String) {
        InAppActions.copyPhoneNumber(number)
        copiedNumber = number
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedNumber = nil
        }
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

    /// Common alternate names/codes → ISO id, so "Turkey", "Holland", "UK",
    /// "UAE", "Korea" etc. resolve to the catalog entry even though the display
    /// name differs (e.g. "Türkiye", "Netherlands", "United Kingdom").
    private static let aliases: [String: String] = [
        "turkey": "TR", "holland": "NL", "uk": "GB", "britain": "GB",
        "great britain": "GB", "england": "GB", "uae": "AE", "emirates": "AE",
        "korea": "KR", "south korea": "KR", "usa": "US", "america": "US",
        "united states of america": "US"
    ]

    /// Diacritic- and case-insensitive fold so "Turkey" matches "Türkiye" and
    /// "Sao Paulo" would match "São ...".
    private func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [CountryEssentials] {
        let query = fold(searchText)
        guard !query.isEmpty else { return TravelEssentialsData.countries }

        // An alias hit takes priority so short queries like "uk"/"uae" resolve
        // to the intended country rather than incidental substring matches.
        if let iso = Self.aliases[query],
           let match = TravelEssentialsData.countries.first(where: { $0.id == iso }) {
            return [match]
        }

        return TravelEssentialsData.countries.filter { country in
            fold(country.name).contains(query) || country.id.lowercased().hasPrefix(query)
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
