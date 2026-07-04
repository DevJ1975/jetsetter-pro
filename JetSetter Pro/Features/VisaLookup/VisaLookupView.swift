// File: Features/VisaLookup/VisaLookupView.swift
//
// Visa & entry requirements for US passport holders. Auto-detects destination
// from the user's next trip and shows the badge, requirements, fees, and
// caveats with a single source-of-truth list at the bottom.

import SwiftUI

struct VisaLookupView: View {

    @State private var selected: VisaRequirement = VisaRequirements.find(
        query: nextTripDestination() ?? "FR"
    ) ?? VisaRequirements.forUSPassport.first!

    @State private var showPicker = false
    @State private var webURL: URL?   // in-app web sheet target (§7.7)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                requirementCard
                passportCard
                if !selected.additionalNotes.isEmpty { notesCard }
                disclaimerCard
            }
            .padding(16)
            .padding(.bottom, 32)
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
    }

    // MARK: - Cards

    private var heroCard: some View {
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

    private var requirementCard: some View {
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

    private var passportCard: some View {
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

    private var notesCard: some View {
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

    private static func nextTripDestination() -> String? {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let trips = try? decoder.decode([Trip].self, from: data) else { return nil }
        return trips
            .filter { $0.startDate > Date() }
            .sorted { $0.startDate < $1.startDate }
            .first?
            .destination
    }
}

// MARK: - Picker sheet

private struct DestinationPickerSheet: View {
    @Binding var selected: VisaRequirement
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
                                    if item.id == selected.id {
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
