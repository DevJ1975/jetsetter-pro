// File: Features/RentalCar/RentalCarView.swift

import SwiftUI

struct RentalCarView: View {

    @State private var vm = RentalCarViewModel()

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
            .inAppWeb(url: $vm.externalWebURL, title: "Book")
        }
    }

    // MARK: - Search Form

    private var searchForm: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .frame(width: 24)
                TextField("Pick-up location (city or airport code)", text: $vm.pickupLocation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .onSubmit { Task { await vm.search() } }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                datePickerField(label: "Pick-Up", icon: "calendar",
                                selection: $vm.pickupDate, range: Date()...,
                                onChange: { vm.pickupDateChanged(to: $0) })

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                datePickerField(label: "Drop-Off", icon: "calendar.badge.checkmark",
                                selection: $vm.dropoffDate, range: vm.dropoffMinimumDate...,
                                onChange: { _ in vm.dropoffAdjustmentNote = nil })
            }

            if let note = vm.dropoffAdjustmentNote {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(note)
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .transition(.opacity)
            }

            HStack {
                Label("\(vm.numberOfDays) day\(vm.numberOfDays == 1 ? "" : "s")", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Rates shown on each brand's site")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                guard !vm.isLoading else { return }
                Task { await vm.search() }
            } label: {
                Label("Find Counters", systemImage: "magnifyingglass")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(JetsetterTheme.Colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.dropoffAdjustmentNote)
    }

    // MARK: - Result Content

    @ViewBuilder
    private var resultContent: some View {
        if vm.isLoading {
            loadingView
        } else if let error = vm.errorMessage {
            errorBanner(message: error)
        } else if vm.isOverFiltered {
            overFilteredView
        } else if vm.hasSearched && vm.counters.isEmpty {
            emptyStateView
        } else if vm.hasSearched {
            counterList
        } else {
            emptyPromptView
        }
    }

    // MARK: - Counter List

    private var counterList: some View {
        VStack(alignment: .leading, spacing: 16) {
            if vm.availableBrands.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        brandChip(nil, label: "All")
                        ForEach(vm.availableBrands, id: \.self) { brand in
                            brandChip(brand, label: brand.displayName)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            Text("\(vm.filteredCounters.count) counter\(vm.filteredCounters.count == 1 ? "" : "s") near \(vm.pickupLocation.uppercased())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            LazyVStack(spacing: 12) {
                ForEach(vm.filteredCounters) { counter in
                    NavigationLink {
                        RentalCarDetailView(counter: counter, params: RentalCarSearchParams(
                            pickupLocation: vm.pickupLocation,
                            pickupDate: vm.pickupDate,
                            dropoffDate: vm.dropoffDate
                        ))
                        .environment(vm)
                    } label: {
                        CounterRowCard(counter: counter)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(JetsetterTheme.Colors.accent)
            Text("Finding rental counters…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

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

    private var overFilteredView: some View {
        VStack(spacing: 12) {
            Text("No \(vm.selectedBrand?.displayName ?? "") counters here")
                .font(.headline)
            Button("Show all brands") { vm.selectedBrand = nil }
                .buttonStyle(.bordered)
                .tint(JetsetterTheme.Colors.accent)
        }
        .padding(.top, 40)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.secondary.opacity(0.4))
            Text("No counters found")
                .font(.headline)
            Text("Try the nearest airport code or a larger city.")
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
            Text("Rental Counters Near You")
                .font(.title3).bold()
            Text("Enter an airport code or city to see Enterprise, Hertz, National, Avis, Budget and more, with distance, phone and a one-tap booking page.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 48)
    }

    // MARK: - Helpers

    private func brandChip(_ brand: RentalBrand?, label: String) -> some View {
        let isSelected = vm.selectedBrand == brand
        let tint = brand.map { Color(hex: $0.colorHex) } ?? JetsetterTheme.Colors.accent
        return Button {
            vm.selectedBrand = isSelected ? nil : brand
        } label: {
            Text(label)
                .font(.caption).bold()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? tint : Color(.secondarySystemBackground))
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

// MARK: - Counter Row Card

struct CounterRowCard: View {
    let counter: RentalCounter

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: counter.brand.colorHex).opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "car.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(hex: counter.brand.colorHex))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(counter.brand.displayName)
                        .font(.caption).bold()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hex: counter.brand.colorHex).opacity(0.15))
                        .foregroundStyle(Color(hex: counter.brand.colorHex))
                        .clipShape(Capsule())
                    Label(counter.formattedDistance, systemImage: "location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(counter.name)
                    .font(.subheadline).bold()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !counter.address.isEmpty {
                    Text(counter.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
        .padding(14)
        .jetCard()
    }
}

// MARK: - Previews

#Preview("Empty State") {
    RentalCarView()
}

#Preview("Counter Card") {
    NavigationStack {
        CounterRowCard(counter: RentalCounter.samples[0])
            .padding()
            .background(Color(.systemGroupedBackground))
    }
}
