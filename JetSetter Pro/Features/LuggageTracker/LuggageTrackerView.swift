// File: Features/LuggageTracker/LuggageTrackerView.swift

import SwiftUI

// MARK: - LuggageTrackerView

/// Main luggage tracking screen showing registered bags with live status.
struct LuggageTrackerView: View {

    @State private var viewModel = LuggageViewModel()
    @State private var isShowingAddBag: Bool = false
    @State private var toastDismissTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.bags.isEmpty {
                    emptyStateView
                } else {
                    bagList
                }
            }
            .navigationTitle("Luggage")
            .navigationBarTitleDisplayMode(.large)
            .inAppWeb(url: $viewModel.externalWebURL, title: "Find My")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAddBag = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                }
                // Refresh all trackable bags
                ToolbarItem(placement: .navigationBarLeading) {
                    if !viewModel.bags.filter({ $0.bagTagNumber != nil }).isEmpty {
                        Button {
                            Task { await viewModel.refreshAllTrackableBags() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(JetsetterTheme.Colors.accent)
                                .symbolEffect(.rotate, isActive: viewModel.isTracking)
                        }
                        .disabled(viewModel.isTracking)
                    }
                }
            }
            .sheet(isPresented: $isShowingAddBag) {
                AddBagView(viewModel: viewModel)
            }
            // Status toast
            .overlay(alignment: .bottom) {
                if let message = viewModel.statusMessage ?? viewModel.errorMessage {
                    let isError = viewModel.errorMessage != nil
                    statusToast(message: message, isError: isError)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            toastDismissTask?.cancel()
                            toastDismissTask = Task {
                                try? await Task.sleep(for: .seconds(3))
                                withAnimation {
                                    viewModel.statusMessage = nil
                                    viewModel.errorMessage = nil
                                }
                            }
                        }
                        .onDisappear {
                            toastDismissTask?.cancel()
                        }
                }
            }
            .animation(.easeInOut, value: viewModel.statusMessage)
            .animation(.easeInOut, value: viewModel.errorMessage)
            .onReceive(NotificationCenter.default.publisher(for: .jetSetterBagsActivated)) { _ in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    viewModel.loadBags()
                }
            }
        }
    }

    // MARK: - Bag List

    private var bagList: some View {
        List {
            ForEach(viewModel.bags) { bag in
                NavigationLink {
                    BagDetailView(bag: bag, viewModel: viewModel)
                } label: {
                    BagRowView(bag: bag, viewModel: viewModel)
                }
            }
            .onDelete { offsets in
                viewModel.deleteBag(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: JetsetterTheme.Spacing.large) {
            Spacer()

            Image(systemName: "suitcase.fill")
                .font(.system(size: 64))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))

            VStack(spacing: JetsetterTheme.Spacing.small) {
                Text("No Bags Registered")
                    .font(.headline)
                Text("Add your bags to track them via SITA WorldTracer or Apple Find My.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JetsetterTheme.Spacing.xlarge)
            }

            Button {
                isShowingAddBag = true
            } label: {
                Text("Add a Bag")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, JetsetterTheme.Spacing.large)
                    .padding(.vertical, JetsetterTheme.Spacing.small)
                    .background(JetsetterTheme.Colors.accent)
                    .clipShape(.rect(cornerRadius: 12))
            }

            Spacer()
        }
    }

    // MARK: - Status Toast

    private func statusToast(message: String, isError: Bool) -> some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? JetsetterTheme.Colors.danger : JetsetterTheme.Colors.success)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding(JetsetterTheme.Spacing.medium)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 14))
        .padding(.horizontal, JetsetterTheme.Spacing.medium)
        .padding(.bottom, JetsetterTheme.Spacing.large)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }
}

// MARK: - BagRowView

private struct BagRowView: View {

    let bag: Bag
    @Bindable var viewModel: LuggageViewModel

    private let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            // Top row — name + status badge
            HStack {
                Image(systemName: "suitcase.fill")
                    .foregroundStyle(Color(hex: bag.status.colorHex))

                Text(bag.nickname)
                    .font(.headline)

                Spacer()

                statusBadge
            }

            // Description
            if !bag.description.isEmpty {
                Text(bag.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Flight info
            if let airline = bag.airline, let flight = bag.flightNumber {
                Label("\(airline) · \(flight)", systemImage: "airplane")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Last location
            if let location = bag.lastLocation {
                Label(location, systemImage: "mappin.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Last checked
            if let lastChecked = bag.lastChecked {
                Text("Updated \(timeFormatter.localizedString(for: lastChecked, relativeTo: Date()))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Action buttons
            HStack(spacing: JetsetterTheme.Spacing.small) {
                // WorldTracer track button
                if bag.bagTagNumber != nil {
                    Button {
                        Task { await viewModel.trackBag(bag) }
                    } label: {
                        Label("Track Bag", systemImage: "location.magnifyingglass")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(JetsetterTheme.Colors.accent)
                            .clipShape(.rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isTracking)
                }

                // Find My deep link button (only if AirTag attached)
                if bag.hasAirTag {
                    Button {
                        viewModel.openFindMy()
                    } label: {
                        Label("Find My", systemImage: "airtag")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(JetsetterTheme.Colors.accent.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                // Bag tag number chip
                if let tag = bag.bagTagNumber {
                    Text("Tag: \(tag)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 6))
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: bag.status.systemImage)
                .font(.caption2)
            Text(bag.status.displayName)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: bag.status.colorHex).opacity(0.12))
        .foregroundStyle(Color(hex: bag.status.colorHex))
        .clipShape(.rect(cornerRadius: 8))
    }
}

// MARK: - AddBagView

private struct AddBagView: View {

    @Bindable var viewModel: LuggageViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var nickname: String = ""
    @State private var description: String = ""
    @State private var airline: String = ""
    @State private var flightNumber: String = ""
    @State private var bagTagNumber: String = ""
    @State private var hasAirTag: Bool = false

    /// Bag tag stripped of whitespace/spaces, mirroring SITAWorldTracerService.traceBag.
    private var cleanedTag: String {
        bagTagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: " ", with: "")
    }

    /// A tag is valid when empty (optional) or a 7–10 digit numeric string,
    /// matching the rule WorldTracer enforces before it will trace a bag.
    private var isTagValid: Bool {
        let cleaned = cleanedTag
        if cleaned.isEmpty { return true }
        return (7...10).contains(cleaned.count) && cleaned.allSatisfy(\.isNumber)
    }

    private var canSave: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isTagValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bag Details") {
                    TextField("Nickname (e.g. Blue Samsonite)", text: $nickname)
                    TextField("Description (color, size, type)", text: $description)
                }

                Section("Flight Info") {
                    TextField("Airline (optional)", text: $airline)
                    TextField("Flight number (optional)", text: $flightNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }

                Section("Tracking") {
                    TextField("Bag tag number (7–10 digits)", text: $bagTagNumber)
                        .keyboardType(.numberPad)

                    if !isTagValid {
                        Label("Enter a 7–10 digit bag tag number, or leave blank.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.danger)
                    }

                    Toggle(isOn: $hasAirTag) {
                        Label("AirTag attached", systemImage: "airtag")
                    }
                    .tint(JetsetterTheme.Colors.accent)
                }

                if !bagTagNumber.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(JetsetterTheme.Colors.accent)
                            Text("The 10-digit bag tag number is printed on your baggage receipt and the tag attached to your bag.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if hasAirTag {
                    Section {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(JetsetterTheme.Colors.accent)
                            Text("AirTag location data is only accessible through the Apple Find My app. Jetsetter will open Find My when you tap the Find My button.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add Bag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? JetsetterTheme.Colors.accent : .secondary)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let cleanedAirline = airline.trimmingCharacters(in: .whitespacesAndNewlines)
        // Flight numbers are entered uppercased in the UI; normalize casing and
        // whitespace here so persisted/displayed data matches the field intent.
        let cleanedFlight = flightNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let bag = Bag(
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            airline: cleanedAirline.isEmpty ? nil : cleanedAirline,
            flightNumber: cleanedFlight.isEmpty ? nil : cleanedFlight,
            bagTagNumber: cleanedTag.isEmpty ? nil : cleanedTag,
            hasAirTag: hasAirTag
        )
        viewModel.addBag(bag)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Empty State") {
    LuggageTrackerView()
}

#Preview("With Bags") {
    let vm = LuggageViewModel()
    Bag.sampleBags.forEach { vm.addBag($0) }
    return NavigationStack {
        List {
            ForEach(vm.bags) { bag in
                BagRowView(bag: bag, viewModel: vm)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Luggage")
    }
}
