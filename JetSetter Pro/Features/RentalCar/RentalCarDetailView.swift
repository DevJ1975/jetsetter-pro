// File: Features/RentalCar/RentalCarDetailView.swift

import SwiftUI

struct RentalCarDetailView: View {

    let vehicle: RentalVehicle
    @EnvironmentObject private var vm: RentalCarViewModel
    @State private var showBookingConfirmation = false
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                rentalDatesCard
                vehicleSpecsCard
                featuresList
                pricingBreakdownCard
                bookButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(vehicle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showBookingConfirmation) {
            RentalBookingConfirmationView(vehicle: vehicle) {
                vm.book(vehicle: vehicle)
                showBookingConfirmation = false
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 12) {
            // Provider badge + class badge
            HStack {
                providerBadge()
                Spacer()
                vehicleClassBadge
            }

            // Vehicle icon
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: vehicle.provider.colorHex).opacity(0.12))
                    .frame(height: 120)
                Image(systemName: vehicle.vehicleClass.systemImage)
                    .font(.system(size: 64))
                    .foregroundStyle(Color(hex: vehicle.provider.colorHex))
            }

            // Name + daily rate
            VStack(spacing: 4) {
                Text(vehicle.displayName)
                    .font(.title2).bold()
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(vehicle.formattedDailyRate + " / day")
                    .font(.headline)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }

            // Mileage policy pill
            Label(vehicle.mileageDescription, systemImage: "speedometer")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(JetsetterTheme.Colors.accent.opacity(0.12))
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .clipShape(Capsule())
        }
        .padding(16)
        .jetCard()
    }

    // MARK: - Rental Dates Card

    private var rentalDatesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Rental Period", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 0) {
                dateColumn(label: "Pick-Up", date: vehicle.pickupDate)
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Spacer()
                dateColumn(label: "Drop-Off", date: vehicle.dropoffDate)
            }

            Divider()

            HStack {
                Label(vehicle.locationName, systemImage: "mappin.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(vehicle.numberOfDays) day\(vehicle.numberOfDays == 1 ? "" : "s")")
                    .font(.subheadline).bold()
                    .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .jetCard()
    }

    // MARK: - Vehicle Specs Card

    private var vehicleSpecsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Vehicle Specs", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                specTile(icon: "person.2.fill",
                         value: "\(vehicle.passengerCapacity) Passengers",
                         label: "Seats")
                specTile(icon: "bag.fill",
                         value: "\(vehicle.baggageCapacity) Bags",
                         label: "Baggage")
                specTile(icon: vehicle.isAutomatic ? "car.side.fill" : "gearshifter",
                         value: vehicle.isAutomatic ? "Automatic" : "Manual",
                         label: "Transmission")
                specTile(icon: vehicle.hasAirConditioning ? "snowflake" : "xmark.circle",
                         value: vehicle.hasAirConditioning ? "Included" : "Not Available",
                         label: "A/C")
            }
        }
        .padding(16)
        .jetCard()
    }

    // MARK: - Features List

    @ViewBuilder
    private var featuresList: some View {
        if !vehicle.features.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Features", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)

                FlowLayout(spacing: 8) {
                    ForEach(vehicle.features, id: \.self) { feature in
                        Label(feature, systemImage: "checkmark")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(JetsetterTheme.Colors.success.opacity(0.12))
                            .foregroundStyle(JetsetterTheme.Colors.success)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(16)
            .jetCard()
        }
    }

    // MARK: - Pricing Breakdown Card

    private var pricingBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Price Breakdown", systemImage: "dollarsign.circle.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            priceRow(label: "Daily Rate", value: vehicle.formattedDailyRate)
            priceRow(label: "× \(vehicle.numberOfDays) day\(vehicle.numberOfDays == 1 ? "" : "s")",
                     value: vehicle.formattedTotalRate)
            priceRow(label: "Taxes & Fees", value: vehicle.formattedTaxes)

            Divider()

            HStack {
                Text("Total")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(vehicle.formattedTotalWithTaxes)
                    .font(.title3).bold()
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }

            if vehicle.isRefundable {
                Label("Free cancellation available", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.success)
            } else {
                Label("Non-refundable rate", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.warning)
            }
        }
        .padding(16)
        .jetCard()
    }

    // MARK: - Book Button

    private var bookButton: some View {
        Button {
            showBookingConfirmation = true
        } label: {
            HStack {
                Image(systemName: "car.fill")
                Text("Book with \(vehicle.provider.displayName)")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(hex: vehicle.provider.colorHex))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Sub-Components

    private func providerBadge(_ provider: RentalProvider? = nil) -> some View {
        let p = provider ?? vehicle.provider
        return HStack(spacing: 4) {
            Image(systemName: p.systemImage)
                .font(.caption2)
            Text(p.displayName)
                .font(.caption).bold()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: p.colorHex).opacity(0.15))
        .foregroundStyle(Color(hex: p.colorHex))
        .clipShape(Capsule())
    }

    private var vehicleClassBadge: some View {
        Text(vehicle.vehicleClass.displayName)
            .font(.caption).bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(JetsetterTheme.Colors.accent.opacity(0.12))
            .foregroundStyle(JetsetterTheme.Colors.accent)
            .clipShape(Capsule())
    }

    private func dateColumn(label: String, date: Date) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.subheadline).bold()
                .foregroundStyle(.primary)
            Text(date, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func specTile(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(JetsetterTheme.Colors.accent)
            Text(value)
                .font(.subheadline).bold()
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func priceRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Computed helpers on RentalVehicle (for detail view display)

private extension RentalVehicle {
    var formattedTotalRate: String {
        totalRate.formatted(.currency(code: currency))
    }
}

// MARK: - Flow Layout (wrapping HStack for feature chips)

/// Simple wrapping layout — chips flow left to right, wrap to next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Booking Confirmation Sheet

struct RentalBookingConfirmationView: View {
    let vehicle: RentalVehicle
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Vehicle summary
                    VStack(spacing: 8) {
                        Image(systemName: vehicle.vehicleClass.systemImage)
                            .font(.system(size: 56))
                            .foregroundStyle(Color(hex: vehicle.provider.colorHex))
                        Text(vehicle.displayName)
                            .font(.title2).bold()
                        Text(vehicle.provider.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 16)

                    // Booking details
                    VStack(spacing: 12) {
                        confirmRow(icon: "mappin.circle", label: "Pick-up", value: vehicle.locationName)
                        confirmRow(icon: "calendar",     label: "Pick-up Date",
                                   value: vehicle.pickupDate.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                        confirmRow(icon: "calendar.badge.clock", label: "Drop-off Date",
                                   value: vehicle.dropoffDate.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                        confirmRow(icon: "dollarsign.circle", label: "Total",
                                   value: vehicle.formattedTotalWithTaxes)
                    }
                    .padding(16)
                    .jetCard()
                    .padding(.horizontal, 16)

                    // Note
                    Text("Tapping \"Continue to \(vehicle.provider.displayName)\" will open the \(vehicle.provider.displayName) app (or App Store if not installed) to complete your booking.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    // CTA
                    Button {
                        onConfirm()
                    } label: {
                        Label("Continue to \(vehicle.provider.displayName)", systemImage: "arrow.up.right.square")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: vehicle.provider.colorHex))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Confirm Rental")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func confirmRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
    }
}

// MARK: - Previews

#Preview("Economy") {
    NavigationStack {
        RentalCarDetailView(vehicle: .sampleEconomy)
            .environmentObject(RentalCarViewModel())
    }
}

#Preview("SUV") {
    NavigationStack {
        RentalCarDetailView(vehicle: .sampleSUV)
            .environmentObject(RentalCarViewModel())
    }
}
