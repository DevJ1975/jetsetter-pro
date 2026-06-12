// File: Features/IRIS/IRISMemoryView.swift
//
// Transparency screen: shows everything IRIS remembers about the user and
// lets them delete individual entries or wipe all. Trust-building UI.

import SwiftUI

struct IRISMemoryView: View {

    @StateObject private var memory = IRISMemory.shared
    @State private var showWipeConfirm = false

    private var grouped: [(category: IRISPreference.Category, items: [IRISPreference])] {
        let dict = Dictionary(grouping: memory.preferences) { $0.category }
        return IRISPreference.Category.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                if memory.preferences.isEmpty {
                    emptyCard
                } else {
                    ForEach(grouped, id: \.category) { section in
                        sectionView(category: section.category, items: section.items)
                    }
                    wipeButton
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("What IRIS Remembers")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(
            "Wipe IRIS's memory?",
            isPresented: $showWipeConfirm,
            titleVisibility: .visible
        ) {
            Button("Forget everything", role: .destructive) {
                memory.forgetEverything()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("IRIS will lose all stored preferences. This can't be undone.")
        }
    }

    // MARK: - Sections

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(rainbowGradient)
                    .frame(width: 22, height: 22)
                Text("IRIS")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(rainbowGradient)
                    .tracking(2)
            }
            Text("Everything IRIS knows about how you travel is shown below. You can delete any entry or wipe her memory entirely.")
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func sectionView(category: IRISPreference.Category, items: [IRISPreference]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: category.systemImage)
                    .font(.caption.bold())
                Text(category.displayName.uppercased())
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            .padding(.leading, 4)

            VStack(spacing: 1) {
                ForEach(items) { item in
                    row(item)
                }
            }
            .jetCard()
        }
    }

    private func row(_ item: IRISPreference) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text("Saved \(item.createdAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            Spacer()
            // Confidence dot
            Circle()
                .fill(confidenceColor(item.confidence))
                .frame(width: 8, height: 8)
            Button {
                memory.delete(item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption.bold())
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("IRIS hasn't learned anything yet")
                .font(.headline)
            Text("Tell her about your preferences in chat — dietary needs, seat choices, hotel style — and she'll keep track here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    private var wipeButton: some View {
        Button(role: .destructive) {
            showWipeConfirm = true
        } label: {
            Label("Wipe IRIS's memory", systemImage: "trash.fill")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.85...: return JetsetterTheme.Colors.success
        case 0.6..<0.85: return JetsetterTheme.Colors.accent
        default: return .secondary
        }
    }

    private var rainbowGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "#E84040"), Color(hex: "#E8A020"), Color(hex: "#FFEB00"),
                Color(hex: "#1DB97D"), Color(hex: "#3B9EF0"), Color(hex: "#7B3FBF")
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }
}
