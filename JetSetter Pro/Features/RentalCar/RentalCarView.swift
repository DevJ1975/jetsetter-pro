// File: Features/RentalCar/RentalCarView.swift

import SwiftUI
import Combine

struct RentalCarView: View {

    @StateObject private var vm = RentalCarViewModel()
    @State private var showFilters = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    searchForm
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    Divider()

                    resultContent
                        .padding(.top, 12)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Rental Cars")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if vm.hasSearched && !vm.vehicles.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort By", selection: $vm.sortOption) {
                                ForEach(RentalCarViewModel.SortOption.allCases, id: \.self) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                RentalCarFiltersView(vm: vm)
            }
        }
    }

    // MARK: - Search Form

    private var searchForm: some View {
        VStack(spacing: 12) {
            // Pickup location
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .frame(width: 24)
                TextField("Pick-up location (city or airport code)", text: $vm.pickupLocation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Same return location toggle
            Toggle(isOn: $vm.isSameReturnLocation) {
                Label("Return to same location", systemImage: "arrow.uturn.backward.circle")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .tint(JetsetterTheme.Colors.accent)
            .padding(.horizontal, 4)

            // Drop-off location (only when different)
            if !vm.isSameReturnLocation {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(JetsetterTheme.Colors.warning)
                        .frame(width: 24)
                    TextField("Drop-off location", text: $vm.dropoffLocation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Dates row
            HStack(spacing: 10) {
                datePickerField(label: "Pick-Up", icon: "calendar",
                                selection: $vm.pickupDate, range: Date()...,
                                onChange: { date in
                    if vm.dropoffDate <= date {
                        vm.dropoffDate = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
                    }
                })

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                datePickerField(label: "Drop-Off", icon: "calendar.badge.checkmark",
                                selection: $vm.dropoffDate, range: vm.dropoffMinimumDate...,
                                onChange: { _ in })
            }

            // Day count + provider pills
            HStack(spacing: 8) {
                Label("\(vm.numberOfDays) day\(vm.numberOfDays == 1 ? "" : "s")", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                ForEach(RentalProvider.allCases, id: \.self) { provider in
                    providerToggle(provider)
                }
            }

            // Search + Filter row
            HStack(spacing: 10) {
                Button {
                    guard !vm.isLoading else { return }
                    Task { await vm.search() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(JetsetterTheme.Colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showFilters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.headline)
                        .padding(13)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(JetsetterTheme.Colors.accent.opacity(0.3), lineWidth: 1)
                        )
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.isSameReturnLocation)
    }

    // MARK: - Result Content

    @ViewBuilder
    private var resultContent: some View {
        if vm.isLoading {
            loadingView
        } else if let error = vm.errorMessage {
            errorBanner(message: error)
        } else if vm.hasSearched && vm.sortedVehicles.isEmpty {
            emptyStateView
        } else if vm.hasSearched {
            vehicleList
        } else {
            emptyPromptView
        }
    }

    // MARK: - Vehicle List

    private var vehicleList: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Class filter chips
            if !vm.availableClasses.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        classChip(nil, label: "All")
                        ForEach(vm.availableClasses, id: \.self) { cls in
                            classChip(cls, label: cls.displayName)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Results count
            Text("\(vm.sortedVehicles.count) vehicle\(vm.sortedVehicles.count == 1 ? "" : "s") found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            // Vehicle cards
            LazyVStack(spacing: 12) {
                ForEach(vm.sortedVehicles) { vehicle in
                    NavigationLink {
                        RentalCarDetailView(vehicle: vehicle)
                            .environmentObject(vm)
                    } label: {
                        VehicleRowCard(vehicle: vehicle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(JetsetterTheme.Colors.accent)
            Text("Searching Enterprise, Hertz & National…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Empty / Error

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(JetsetterTheme.Colors.danger)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(14)
        .background(JetsetterTheme.Colors.danger.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.secondary.opacity(0.4))
            Text("No vehicles available")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Try adjusting your dates, location, or providers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Clear Search") { vm.clearSearch() }
                .buttonStyle(.bordered)
                .tint(JetsetterTheme.Colors.accent)
        }
        .padding(.horizontal, 32)
        .padding(.top, 60)
    }

    private var emptyPromptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "steeringwheel")
                .font(.system(size: 64))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))
            Text("Search Rental Cars")
                .font(.title3).bold()
                .foregroundStyle(.primary)
            Text("Enter a pick-up location and dates to compare cars from Enterprise, Hertz, and National.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 48)
    }

    // MARK: - Helper Views

    private func providerToggle(_ provider: RentalProvider) -> some View {
        let isSelected = vm.selectedProviders.contains(provider)
        return Button {
            if isSelected {
                if vm.selectedProviders.count > 1 {
                    vm.selectedProviders.remove(provider)
                }
            } else {
                vm.selectedProviders.insert(provider)
            }
        } label: {
            Text(provider.displayName)
                .font(.caption2).bold()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color(hex: provider.colorHex).opacity(0.15) : Color.clear)
                .foregroundStyle(isSelected ? Color(hex: provider.colorHex) : Color.secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color(hex: provider.colorHex).opacity(0.5) : Color.secondary.opacity(0.3),
                                lineWidth: 1)
                )
        }
    }

    private func classChip(_ cls: VehicleClass?, label: String) -> some View {
        let isSelected = vm.selectedClass == cls
        return Button {
            vm.selectedClass = isSelected ? nil : cls
        } label: {
            Text(label)
                .font(.caption).bold()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? JetsetterTheme.Colors.accent : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .clipShape(Capsule())
        }
    }

    private func datePickerField(label: String, icon: String,
                                  selection: Binding<Date>,
                                  range: PartialRangeFrom<Date>,
                                  onChange: @escaping (Date) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            DatePicker("", selection: selection, in: range, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .onChange(of: selection.wrappedValue) { onChange($1) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Vehicle Row Card

struct VehicleRowCard: View {
    let vehicle: RentalVehicle

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Vehicle icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: vehicle.provider.colorHex).opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: vehicle.vehicleClass.systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(Color(hex: vehicle.provider.colorHex))
            }

            VStack(alignment: .leading, spacing: 5) {
                // Provider + class
                HStack(spacing: 6) {
                    Text(vehicle.provider.displayName)
                        .font(.caption).bold()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hex: vehicle.provider.colorHex).opacity(0.15))
                        .foregroundStyle(Color(hex: vehicle.provider.colorHex))
                        .clipShape(Capsule())
                    Text(vehicle.vehicleClass.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Vehicle name
                Text(vehicle.displayName)
                    .font(.subheadline).bold()
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Capacity + mileage
                HStack(spacing: 10) {
                    Label("\(vehicle.passengerCapacity)", systemImage: "person.2")
                    Label("\(vehicle.baggageCapacity)", systemImage: "bag")
                    Label(vehicle.freeMileage ? "Unlimited" : "Limited miles",
                          systemImage: "speedometer")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                // Refundable badge
                if vehicle.isRefundable {
                    Label("Free cancellation", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(JetsetterTheme.Colors.success)
                }
            }

            Spacer(minLength: 0)

            // Price column
            VStack(alignment: .trailing, spacing: 2) {
                Text(vehicle.formattedDailyRate)
                    .font(.headline)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                Text("/ day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(vehicle.formattedTotalWithTaxes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .jetCard()
    }
}

// MARK: - Filters Sheet

struct RentalCarFiltersView: View {
    @ObservedObject var vm: RentalCarViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Providers") {
                    ForEach(RentalProvider.allCases, id: \.self) { provider in
                        Toggle(provider.displayName, isOn: Binding(
                            get: { vm.selectedProviders.contains(provider) },
                            set: { include in
                                if include {
                                    vm.selectedProviders.insert(provider)
                                } else if vm.selectedProviders.count > 1 {
                                    vm.selectedProviders.remove(provider)
                                }
                            }
                        ))
                        .tint(Color(hex: provider.colorHex))
                    }
                }

                Section("Vehicle Class") {
                    Picker("Class", selection: $vm.selectedClass) {
                        Text("Any Class").tag(Optional<VehicleClass>.none)
                        ForEach(VehicleClass.allCases, id: \.self) { cls in
                            Label(cls.displayName, systemImage: cls.systemImage)
                                .tag(Optional(cls))
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Sort") {
                    Picker("Sort By", selection: $vm.sortOption) {
                        ForEach(RentalCarViewModel.SortOption.allCases, id: \.self) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Filters & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Empty State") {
    RentalCarView()
}

#Preview("Vehicle Card") {
    NavigationStack {
        VehicleRowCard(vehicle: .sampleEconomy)
            .padding()
            .background(Color(.systemGroupedBackground))
    }
}
