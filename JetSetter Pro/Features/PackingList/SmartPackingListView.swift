// File: Features/PackingList/SmartPackingListView.swift
// Smart Packing List — AI-generated, categorized, checkable packing list
// with progress ring, swipe-to-delete, and add-item sheet (Feature 2).

import SwiftUI

struct SmartPackingListView: View {

    @StateObject private var vm: PackingListViewModel
    @EnvironmentObject private var subscriptions: SubscriptionManager

    init(trip: Trip) {
        _vm = StateObject(wrappedValue: PackingListViewModel(trip: trip))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading || vm.isGenerating {
                    loadingView
                } else if let list = vm.packingList {
                    packingListContent(list)
                } else {
                    generatePromptView
                }
            }
            .navigationTitle("Packing List")
            .navigationBarTitleDisplayMode(.large)
            .background(JetsetterTheme.Colors.background)
            .toolbar { toolbarContent }
            .task { await vm.load() }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
            .sheet(isPresented: $vm.showAddItem) {
                AddPackingItemSheet(vm: vm)
            }
        }
        .premiumGate(feature: "Smart Packing List")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if vm.packingList != nil {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    Task { await vm.regenerateList() }
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
                .disabled(vm.isGenerating)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { vm.showAddItem = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(JetsetterTheme.Colors.surfaceElevated, lineWidth: 3)
                    .frame(width: 56, height: 56)
                ProgressView()
                    .tint(JetsetterTheme.Colors.accent)
                    .scaleEffect(1.4)
            }
            VStack(spacing: 4) {
                Text(vm.isGenerating ? "Generating with AI…" : "Loading…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                if vm.isGenerating {
                    Text("Checking weather, activities & baggage rules")
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Generate Prompt

    private var generatePromptView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(JetsetterTheme.Colors.accent.opacity(0.10))
                    .frame(width: 96, height: 96)
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }

            VStack(spacing: 8) {
                Text("AI Packing List")
                    .font(JetsetterTheme.Typography.pageTitle)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text("We'll generate a personalized list based on your destination's 7-day weather forecast, planned activities, airline baggage rules, and trip duration.")
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Context chips
            HStack(spacing: 8) {
                contextChip(icon: "cloud.sun.fill",  label: "Weather")
                contextChip(icon: "figure.walk",     label: "Activities")
                contextChip(icon: "airplane",        label: "Airline rules")
            }

            Button {
                Task { await vm.generateList() }
            } label: {
                Label("Generate My List", systemImage: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: 260)
                    .padding(.vertical, 14)
                    .background(JetsetterTheme.Colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func contextChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(.caption.bold())
        }
        .foregroundStyle(JetsetterTheme.Colors.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(JetsetterTheme.Colors.accent.opacity(0.10))
        .clipShape(Capsule())
    }

    // MARK: - Packing List Content

    private func packingListContent(_ list: PackingListResult) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                progressRing(list)

                ForEach(list.groupedByCategory, id: \.category) { group in
                    categorySection(group.category, items: group.items)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Progress Ring

    private func progressRing(_ list: PackingListResult) -> some View {
        HStack(spacing: 20) {
            // Ring
            ZStack {
                Circle()
                    .stroke(JetsetterTheme.Colors.surfaceElevated, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: list.completionRatio)
                    .stroke(
                        list.completionRatio >= 1.0 ? JetsetterTheme.Colors.success : JetsetterTheme.Colors.accent,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5), value: list.completionRatio)
                VStack(spacing: 1) {
                    Text("\(Int(list.completionRatio * 100))%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text("packed")
                        .font(.caption2)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
            .frame(width: 80, height: 80)

            // Stats
            VStack(alignment: .leading, spacing: 6) {
                statRow(icon: "checkmark.circle.fill",
                        color: JetsetterTheme.Colors.success,
                        label: "\(list.items.filter { $0.isPacked }.count) packed")
                statRow(icon: "circle",
                        color: JetsetterTheme.Colors.textSecondary,
                        label: "\(list.items.filter { !$0.isPacked }.count) remaining")
                statRow(icon: "bag.fill",
                        color: JetsetterTheme.Colors.accent,
                        label: "\(list.items.count) items total")
            }

            Spacer()
        }
        .padding(20)
        .jetCard()
    }

    private func statRow(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
        }
    }

    // MARK: - Category Section

    private func categorySection(_ category: PackingCategory, items: [SmartPackingItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: category.systemImage).font(.caption.bold())
                Text(category.rawValue.uppercased())
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
                Spacer()
                Text("\(items.filter { $0.isPacked }.count)/\(items.count)")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            .foregroundStyle(Color(hex: category.colorHex))
            .padding(.leading, 4)

            VStack(spacing: 1) {
                ForEach(items) { item in
                    packingItemRow(item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                vm.deleteItem(id: item.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .jetCard()
        }
    }

    // MARK: - Item Row

    private func packingItemRow(_ item: SmartPackingItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.isPacked ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(
                    item.isPacked
                        ? JetsetterTheme.Colors.success
                        : JetsetterTheme.Colors.textSecondary.opacity(0.4)
                )
                .animation(.easeInOut(duration: 0.15), value: item.isPacked)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.quantity > 1 ? "\(item.name) ×\(item.quantity)" : item.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(
                            item.isPacked
                                ? JetsetterTheme.Colors.textSecondary
                                : JetsetterTheme.Colors.textPrimary
                        )
                        .strikethrough(item.isPacked)
                    if item.isCustom {
                        Text("Custom")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(JetsetterTheme.Colors.accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                if let note = item.notes {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { vm.toggleItem(id: item.id) }
    }
}

// MARK: - Add Item Sheet

struct AddPackingItemSheet: View {

    @ObservedObject var vm: PackingListViewModel
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("e.g. Hiking boots", text: $vm.newItemName)
                        .focused($focused)
                }
                Section("Category") {
                    Picker("Category", selection: $vm.newItemCategory) {
                        ForEach(PackingCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.newItemName = ""
                        vm.showAddItem = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { vm.commitAddItem() }
                        .disabled(vm.newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Packing List Router (used from MoreView — picks the next upcoming trip)

/// Loads the user's trips from UserDefaults and routes to the packing list for the
/// next upcoming trip, or shows a picker when multiple active trips exist.
struct PackingListRouterView: View {

    @State private var trips: [Trip] = []
    @State private var selectedTrip: Trip?

    private static let tripsKey     = "jetsetter_trips"
    private static let dateStrategy = JSONDecoder.DateDecodingStrategy.iso8601

    var body: some View {
        Group {
            if let trip = selectedTrip ?? trips.first(where: { $0.startDate >= Date() }) ?? trips.first {
                SmartPackingListView(trip: trip)
            } else {
                noTripsView
            }
        }
        .onAppear { loadTrips() }
    }

    private var noTripsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            Text("No Trips Yet")
                .font(JetsetterTheme.Typography.pageTitle)
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            Text("Add a trip to generate a packing list.")
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JetsetterTheme.Colors.background)
    }

    private func loadTrips() {
        guard let data = UserDefaults.standard.data(forKey: Self.tripsKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = Self.dateStrategy
        trips = (try? decoder.decode([Trip].self, from: data)) ?? []
    }
}

// MARK: - Preview

#Preview {
    SmartPackingListView(trip: .sample)
        .environmentObject(SubscriptionManager.shared)
}
