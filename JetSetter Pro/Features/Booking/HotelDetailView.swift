// File: Features/Booking/HotelDetailView.swift

import SwiftUI

// MARK: - HotelDetailView

/// Shows all room types and rates for a selected hotel property.
struct HotelDetailView: View {

    let hotel: HotelProperty
    let searchParams: HotelSearchParams

    @State private var selectedRateForConfirmation: RoomRate? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: JetsetterTheme.Spacing.medium) {
                headerCard
                stayInfoCard

                // Room list
                VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
                    Text("Available Rooms")
                        .font(.headline)
                        .padding(.horizontal, JetsetterTheme.Spacing.medium)

                    ForEach(hotel.rooms, id: \.id) { room in
                        roomCard(room: room)
                    }
                }
            }
            .padding(JetsetterTheme.Spacing.medium)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Hotel Details")
        .navigationBarTitleDisplayMode(.inline)
        // Use sheet(item:) so SwiftUI owns the rate's lifetime — no nil-rate flash
        .sheet(item: $selectedRateForConfirmation) { rate in
            BookingConfirmationView(hotel: hotel, rate: rate, searchParams: searchParams)
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: JetsetterTheme.Spacing.small) {
            // Property icon placeholder (replace with Kingfisher image when property images available)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(JetsetterTheme.Colors.primary.opacity(0.08))
                    .frame(height: 140)

                Image(systemName: "building.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(JetsetterTheme.Colors.primary.opacity(0.3))
            }

            VStack(spacing: JetsetterTheme.Spacing.xsmall) {
                Text(hotel.name ?? "Property \(hotel.propertyId)")
                    .font(.headline)

                if let score = hotel.score {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(String(format: "%.1f", score))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lowestRate = hotel.lowestNightlyRate {
                    Text("From \(hotel.lowestRateCurrency) \(String(format: "%.0f", lowestRate)) / night")
                        .font(.subheadline)
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .fontWeight(.semibold)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: - Stay Info Card

    private var stayInfoCard: some View {
        HStack {
            stayInfoColumn(label: "Check-in", value: searchParams.checkInString)
            Divider().frame(height: 40)
            stayInfoColumn(label: "Check-out", value: searchParams.checkOutString)
            Divider().frame(height: 40)
            stayInfoColumn(label: "Nights", value: "\(searchParams.numberOfNights)")
            Divider().frame(height: 40)
            stayInfoColumn(label: "Guests", value: "\(searchParams.adults)")
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    private func stayInfoColumn(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Room Card

    private func roomCard(room: HotelRoom) -> some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            Text(room.roomName ?? "Room")
                .font(.headline)
                .padding(.horizontal, JetsetterTheme.Card.padding)
                .padding(.top, JetsetterTheme.Card.padding)

            ForEach(room.rates) { rate in
                rateRow(rate: rate, roomName: room.roomName ?? "Room")
            }
        }
        .jetCard()
    }

    // MARK: - Rate Row

    private func rateRow(rate: RoomRate, roomName: String) -> some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .top, spacing: JetsetterTheme.Spacing.medium) {
                VStack(alignment: .leading, spacing: 4) {
                    // Refundable badge
                    if let refundable = rate.refundable {
                        Text(refundable ? "Free cancellation" : "Non-refundable")
                            .font(.caption)
                            .foregroundStyle(refundable ? JetsetterTheme.Colors.success : JetsetterTheme.Colors.danger)
                    }

                    if let available = rate.availableRooms, available <= 3 {
                        Text("Only \(available) left!")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.warning)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(rate.formattedNightlyPrice)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("/ night")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Total: \(rate.formattedTotalPrice)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, JetsetterTheme.Card.padding)
            .padding(.vertical, JetsetterTheme.Spacing.small)

            // Select button
            Button {
                selectedRateForConfirmation = rate
            } label: {
                Text("Select Room")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, JetsetterTheme.Spacing.small)
                    .background(JetsetterTheme.Colors.accent)
            }
            .padding(.bottom, JetsetterTheme.Spacing.small)
            .padding(.horizontal, JetsetterTheme.Card.padding)
        }
    }
}

// MARK: - BookingConfirmationView

/// Summary sheet shown after the user selects a room, before final booking.
struct BookingConfirmationView: View {

    let hotel: HotelProperty
    let rate: RoomRate
    let searchParams: HotelSearchParams

    @Environment(\.dismiss) private var dismiss
    @State private var isBooking: Bool = false
    @State private var bookingComplete: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: JetsetterTheme.Spacing.large) {
                if bookingComplete {
                    bookingSuccessView
                } else {
                    bookingSummaryView
                }
            }
            .padding(JetsetterTheme.Spacing.large)
            .navigationTitle("Confirm Booking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !bookingComplete {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var bookingSummaryView: some View {
        VStack(spacing: JetsetterTheme.Spacing.large) {
            Spacer()

            Image(systemName: "building.2.fill")
                .font(.system(size: 52))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.5))

            VStack(spacing: JetsetterTheme.Spacing.small) {
                Text(hotel.name ?? "Property \(hotel.propertyId)")
                    .font(.title2).fontWeight(.bold)

                Text("\(searchParams.checkInString) → \(searchParams.checkOutString)")
                    .font(.subheadline).foregroundStyle(.secondary)

                Text("\(searchParams.numberOfNights) nights · \(searchParams.adults) guest\(searchParams.adults == 1 ? "" : "s")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            VStack(spacing: JetsetterTheme.Spacing.xsmall) {
                Text("Total")
                    .font(.caption).foregroundStyle(.secondary)
                Text(rate.formattedTotalPrice)
                    .font(.largeTitle).fontWeight(.bold)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }
            .padding(JetsetterTheme.Spacing.medium)
            .frame(maxWidth: .infinity)
            .background(JetsetterTheme.Colors.accent.opacity(0.08))
            .cornerRadius(12)

            Spacer()

            Button {
                // TODO: Implement POST /v3/itinerary booking call with Expedia Rapid API
                Task {
                    isBooking = true
                    try? await Task.sleep(for: .seconds(1))
                    isBooking = false
                    bookingComplete = true
                }
            } label: {
                Group {
                    if isBooking {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Confirm & Book")
                            .fontWeight(.semibold)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(JetsetterTheme.Spacing.medium)
                .background(JetsetterTheme.Colors.accent)
                .cornerRadius(14)
            }
            .disabled(isBooking)
        }
    }

    private var bookingSuccessView: some View {
        VStack(spacing: JetsetterTheme.Spacing.large) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(JetsetterTheme.Colors.success)

            Text("Booking Confirmed!")
                .font(.title).fontWeight(.bold)

            Text("Your reservation at Property \(hotel.propertyId) has been confirmed. Check your email for the full details.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Done") { dismiss() }
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(JetsetterTheme.Spacing.medium)
                .background(JetsetterTheme.Colors.success)
                .cornerRadius(14)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HotelDetailView(
            hotel: HotelProperty.sampleProperties[0],
            searchParams: HotelSearchParams()
        )
    }
}
