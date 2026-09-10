// File: Features/RentalCar/RentalCarDetailView.swift

import SwiftUI
import MapKit

struct RentalCarDetailView: View {

    let counter: RentalCounter
    let params: RentalCarSearchParams
    @Environment(RentalCarViewModel.self) private var vm
    @Environment(\.openURL) private var openURL

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapCard
                headerCard
                rentalDatesCard
                contactCard
                bookButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(counter.brand.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Map

    private var mapCard: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: counter.coordinate,
            latitudinalMeters: 1_500,
            longitudinalMeters: 1_500
        ))) {
            Marker(counter.name, systemImage: "car.fill", coordinate: counter.coordinate)
                .tint(Color(hex: counter.brand.colorHex))
        }
        .mapControlVisibility(.hidden)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                brandBadge
                Spacer()
                Label(counter.formattedDistance + " from pickup point", systemImage: "location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(counter.name)
                .font(.title3).bold()
                .foregroundStyle(.primary)
            if !counter.address.isEmpty {
                Text(counter.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .jetCard()
    }

    // MARK: - Rental Dates

    private var rentalDatesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your Rental Dates", systemImage: "calendar")
                .font(.headline)

            HStack(spacing: 0) {
                dateColumn(label: "Pick-Up", date: params.pickupDate)
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Spacer()
                dateColumn(label: "Drop-Off", date: params.dropoffDate)
            }

            Divider()

            HStack {
                Text("Enter these on \(counter.brand == .other ? "the booking site" : counter.brand.displayName + ".com") to see rates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(params.numberOfDays) day\(params.numberOfDays == 1 ? "" : "s")")
                    .font(.subheadline).bold()
            }
        }
        .padding(16)
        .jetCard()
    }

    // MARK: - Contact

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("At the Counter", systemImage: "info.circle.fill")
                .font(.headline)

            HStack(spacing: 12) {
                if let phoneURL = counter.phoneURL, let phone = counter.phoneNumber {
                    Button { openURL(phoneURL) } label: {
                        actionTile(icon: "phone.fill", title: "Call", subtitle: phone)
                    }
                    .buttonStyle(.plain)
                }
                Button { vm.directions(to: counter) } label: {
                    actionTile(icon: "arrow.triangle.turn.up.right.diamond.fill", title: "Directions", subtitle: "Apple Maps")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .jetCard()
    }

    // MARK: - Book

    @ViewBuilder
    private var bookButton: some View {
        if let url = counter.bookingURL {
            Button {
                vm.book(counter)
            } label: {
                HStack {
                    Image(systemName: "safari")
                    Text(counter.brand == .other ? "Open Booking Site" : "See Rates on \(counter.brand.displayName).com")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(hex: counter.brand.colorHex))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityHint(url.host ?? "")
        }
    }

    // MARK: - Sub-Components

    private var brandBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "car.fill").font(.caption2)
            Text(counter.brand.displayName).font(.caption).bold()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: counter.brand.colorHex).opacity(0.15))
        .foregroundStyle(Color(hex: counter.brand.colorHex))
        .clipShape(Capsule())
    }

    private func dateColumn(label: String, date: Date) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.subheadline).bold()
        }
    }

    private func actionTile(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(JetsetterTheme.Colors.accent)
            Text(title)
                .font(.subheadline).bold()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Flow Layout (wrapping HStack for chips)

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

// MARK: - Previews

#Preview {
    NavigationStack {
        RentalCarDetailView(counter: RentalCounter.samples[0], params: RentalCarSearchParams(pickupLocation: "ORD"))
            .environment(RentalCarViewModel())
    }
}
