// File: Features/PackingList/SmartPackingListView.swift
// Smart Packing List — AI-generated, categorized, checkable packing list
// with progress ring, delete, and add-item sheet (Feature 2).
//
// Rows are toggles ("Phone charger, Not packed"); they used to be views with
// `.onTapGesture`, which VoiceOver couldn't tell were checkable. Deleting is a
// long-press context menu plus a "Delete" VoiceOver action: the old
// `.swipeActions` never fired, because swipe actions only work on `List` rows
// and these sit in a `ScrollView` (kept so the card look stays the same).

import SwiftUI

struct SmartPackingListView: View {

    @State private var vm: PackingListViewModel
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var promptBadgeSize: CGFloat = 96
    @ScaledMetric(relativeTo: .largeTitle) private var promptIconSize: CGFloat = 40
    @ScaledMetric(relativeTo: .title2) private var ringSize: CGFloat = 80

    init(trip: Trip) {
        _vm = State(wrappedValue: PackingListViewModel(trip: trip))
    }

    // No NavigationStack here: this screen (through `PackingListRouterView`)
    // is pushed onto More's stack, and its own stack nested a second one inside
    // it (doubled bars, broken back swipe). The routed sheet in ContentView
    // wraps it with `.inSheetNavigation()`.
    var body: some View {
        Group {
            // While generating, rows stream in from the on-device model; show
            // them as they land and keep the spinner only until the first arrives.
            if vm.isLoading || (vm.isGenerating && (vm.packingList?.items.isEmpty ?? true)) {
                loadingView
            } else if let list = vm.packingList {
                packingListContent(list)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if vm.isGenerating { generatingBanner }
                    }
            } else {
                generatePromptView
            }
        }
        .navigationTitle("Packing List")
        .navigationBarTitleDisplayMode(.large)
        .background(JetsetterTheme.Colors.background)
        .toolbar { toolbarContent }
        .task {
            await vm.load()
            // Siri's "build my packing list" lands here once the screen exists
            // (cold-launch safe). Regenerating keeps packed state and custom items.
            if case .generatePackingList(let tripID) = router.pendingAction,
               tripID == nil || tripID == vm.trip.id {
                router.consume(.generatePackingList(tripID: tripID))
                if vm.packingList == nil { await vm.generateList() } else { await vm.regenerateList() }
            }
        }
        .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
        .confirmationDialog(
            "Regenerate packing list?",
            isPresented: $vm.showRegenerateConfirm,
            titleVisibility: .visible
        ) {
            Button("Regenerate") { Task { await vm.regenerateList() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("We'll rebuild the AI suggestions. Your packed check-offs and custom items are kept.")
        }
        .sheet(isPresented: $vm.showAddItem) {
            AddPackingItemSheet(vm: vm)
        }
        .premiumGate(feature: "Smart Packing List")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if vm.packingList != nil {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    vm.showRegenerateConfirm = true
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.system(.subheadline, weight: .semibold))
                }
                .disabled(vm.isGenerating)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { vm.showAddItem = true } label: {
                    Image(systemName: "plus")
                        .font(.system(.callout, weight: .semibold))
                }
                .accessibilityLabel("Add item")
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
                Text(vm.isGenerating ? "Writing your list on this iPhone…" : "Loading…")
                    .font(.system(.subheadline, weight: .semibold))
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

    // MARK: - Generating banner (streamed results)

    private var generatingBanner: some View {
        HStack(spacing: 10) {
            ProgressView().tint(JetsetterTheme.Colors.accent)
            Text("Still packing… items appear as they're written on this iPhone")
                .font(.footnote.weight(.medium))
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Generate Prompt

    /// Centred while it fits; scrolls at large text sizes so the Generate
    /// button can't be pushed off screen.
    private var generatePromptView: some View {
        ViewThatFits(in: .vertical) {
            generatePromptContent
            ScrollView { generatePromptContent }
        }
    }

    private var generatePromptContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(JetsetterTheme.Colors.accent.opacity(0.10))
                    .frame(width: promptBadgeSize, height: promptBadgeSize)
                Image(systemName: "sparkles")
                    .font(.system(size: promptIconSize))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Smart Packing List")
                    .font(JetsetterTheme.Typography.pageTitle)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text("We'll generate a personalized list based on your destination's 7-day weather forecast, planned activities, airline baggage rules, and trip duration.")
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Context chips (stacked at accessibility sizes so they don't overflow)
            let chips = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            chips {
                contextChip(icon: "cloud.sun.fill",  label: "Weather")
                contextChip(icon: "figure.walk",     label: "Activities")
                contextChip(icon: "airplane",        label: "Airline rules")
            }

            Button {
                Task { await vm.generateList() }
            } label: {
                Label("Generate My List", systemImage: "sparkles")
                    .font(.system(.callout, weight: .bold))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .frame(minWidth: 260)
                    .background(JetsetterTheme.Colors.accentFill)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .tripDayReadableWidth()
    }

    private func contextChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
                .accessibilityHidden(true)
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
            .tripDayReadableWidth()
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
                    .animation(reduceMotion ? nil : .spring(response: 0.5), value: list.completionRatio)
                VStack(spacing: 1) {
                    Text("\(Int(list.completionRatio * 100))%")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("packed")
                        .font(.caption2)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
                .padding(8)
            }
            .frame(width: ringSize, height: ringSize)

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Packing progress")
        .accessibilityValue(
            "\(Int(list.completionRatio * 100)) percent. "
            + "\(list.items.filter { $0.isPacked }.count) packed, "
            + "\(list.items.filter { !$0.isPacked }.count) remaining, "
            + "\(list.items.count) items total"
        )
    }

    private func statRow(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(label)
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
        }
    }

    // MARK: - Category Section

    private func categorySection(_ category: PackingCategory, items: [SmartPackingItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: category.systemImage).font(.caption.bold())
                    .accessibilityHidden(true)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(category.rawValue), \(items.filter { $0.isPacked }.count) of \(items.count) packed")
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 1) {
                ForEach(items) { item in
                    packingItemRow(item)
                        .contextMenu {
                            Button(role: .destructive) {
                                vm.deleteItem(id: item.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .accessibilityAction(named: Text("Delete")) {
                            vm.deleteItem(id: item.id)
                        }
                }
            }
            .jetCard()
        }
    }

    // MARK: - Item Row

    private func packingItemRow(_ item: SmartPackingItem) -> some View {
        Toggle(isOn: Binding(get: { item.isPacked }, set: { _ in vm.toggleItem(id: item.id) })) {
            packingItemLabel(item)
        }
        .toggleStyle(ChecklistToggleStyle(
            onColor: JetsetterTheme.Colors.success,
            // 0.4 opacity drew the empty circle at about 1.9:1 against the
            // card; 0.7 keeps it lighter than a checked one at about 3.4:1,
            // above the 3:1 WCAG asks of a control's outline.
            offColor: JetsetterTheme.Colors.textSecondary.opacity(0.7)
        ))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func packingItemLabel(_ item: SmartPackingItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(item.quantity > 1 ? "\(item.name) ×\(item.quantity)" : item.name)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(
                        item.isPacked
                            ? JetsetterTheme.Colors.textSecondary
                            : JetsetterTheme.Colors.textPrimary
                    )
                    .strikethrough(item.isPacked)
                if item.isCustom {
                    Text("Custom")
                        .font(.system(.caption2, weight: .semibold))
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
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
        }
    }
}

// MARK: - Add Item Sheet

struct AddPackingItemSheet: View {

    @Bindable var vm: PackingListViewModel
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("e.g. Hiking boots", text: $vm.newItemName)
                        .focused($focused)
                    Stepper(value: $vm.newItemQuantity, in: 1...99) {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text("\(vm.newItemQuantity)")
                                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        }
                    }
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
                        vm.newItemQuantity = 1
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
            if let trip = selectedTrip ?? bestTrip() {
                SmartPackingListView(trip: trip)
            } else {
                noTripsView
            }
        }
        .onAppear { loadTrips() }
    }

    /// Picks the most relevant trip for the packing list:
    ///   1. A trip in progress today (startDate...endDate contains today).
    ///   2. Otherwise the soonest upcoming trip.
    ///   3. Otherwise the most recent past trip (so the view is never empty when
    ///      trips exist).
    /// All comparisons use start-of-day to avoid a same-day timestamp boundary bug.
    private func bestTrip() -> Trip? {
        guard !trips.isEmpty else { return nil }
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        let sorted = trips.sorted { $0.startDate < $1.startDate }

        if let inProgress = sorted.first(where: {
            cal.startOfDay(for: $0.startDate) <= today &&
            today <= cal.startOfDay(for: $0.endDate)
        }) {
            return inProgress
        }
        if let upcoming = sorted.first(where: { cal.startOfDay(for: $0.startDate) >= today }) {
            return upcoming
        }
        return sorted.last
    }

    private var noTripsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.largeTitle)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .accessibilityHidden(true)
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
    NavigationStack {
        SmartPackingListView(trip: .sample)
    }
    .environment(SubscriptionManager.shared)
}
