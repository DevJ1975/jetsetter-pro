// File: Features/EmailImport/EmailImportView.swift
//
// Email Intelligence — paste or import a travel email, review what the AI
// extracted, and add it to the wallet, itinerary, and calendar in one tap.

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct EmailImportView: View {

    @StateObject private var viewModel = EmailImportViewModel()
    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?

    private var importableTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .text, .emailMessage]
        if let ics = UTType(filenameExtension: "ics") { types.append(ics) }
        if let eml = UTType(filenameExtension: "eml") { types.append(eml) }
        return types
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                headerCard

                if viewModel.parsed == nil {
                    inputCard
                    forwardingCard
                } else {
                    reviewSection
                }

                if let message = viewModel.statusMessage {
                    statusBanner(message, isError: viewModel.isStatusError)
                }

                if let summary = viewModel.summary {
                    summaryCard(summary)
                }
            }
            .padding(16)
        }
        .background(JetsetterTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Email Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadForwardingAlias()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: importableTypes
        ) { result in
            if case .success(let url) = result {
                Task { await viewModel.importFile(at: url) }
            }
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await viewModel.importImage(image)
                }
                photoItem = nil
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.title3)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                Text("Turn emails into your itinerary")
                    .font(JetsetterTheme.Typography.cardTitle)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            }
            Text("Paste or import flight confirmations, hotel bookings, car rentals, meeting invites, or airline delay notices — AI extracts the details and files them into your wallet, itinerary, and calendar.")
                .font(.caption)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            GoldTag(text: viewModel.providerLabel, icon: "lock.shield")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: - Input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EMAIL TEXT")
                .font(JetsetterTheme.Typography.label)
                .tracking(1.2)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)

            TextEditor(text: $viewModel.inputText)
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .font(.system(size: 14))
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                .premiumInput()

            Button {
                Task { await viewModel.parsePastedText() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(viewModel.isWorking ? "Reading…" : "Extract Travel Details")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(JetsetterTheme.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(viewModel.isWorking || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            HStack(spacing: 10) {
                importButton(icon: "doc.fill", label: "PDF / .eml") {
                    showFileImporter = true
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    importButtonLabel(icon: "photo.fill", label: "Screenshot")
                }
            }
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    private func importButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            importButtonLabel(icon: icon, label: label)
        }
    }

    private func importButtonLabel(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(label).font(.caption).bold()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(JetsetterTheme.Colors.accent.opacity(0.12))
        .foregroundStyle(JetsetterTheme.Colors.accent)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Forwarding inbox

    private var forwardingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                Text("FORWARD YOUR CONFIRMATIONS")
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.2)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }

            if let alias = viewModel.forwardingAlias {
                Text("Forward booking emails to your private address and they'll appear here on your next visit:")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                Text(verbatim: "\(alias)@in.jetsetterpro.app")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .textSelection(.enabled)

                Button {
                    Task { await viewModel.checkForwardingInbox() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill").font(.caption)
                        Text("Check for forwarded emails").font(.caption).bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(JetsetterTheme.Colors.accent.opacity(0.12))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .disabled(viewModel.isWorking)
            } else {
                Text("Sign in (Settings → Account) to get a private forwarding address — booking emails you forward will be parsed on your device the next time you open the app.")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: - Review

    @ViewBuilder
    private var reviewSection: some View {
        if let parsed = viewModel.parsed {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("FOUND \(parsed.entityCount) ITEM\(parsed.entityCount == 1 ? "" : "S")")
                        .font(JetsetterTheme.Typography.label)
                        .tracking(1.2)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    Spacer()
                    Button("Discard") { viewModel.discardReview() }
                        .font(.caption.bold())
                        .foregroundStyle(JetsetterTheme.Colors.danger)
                }

                ForEach(parsed.flights) { flight in
                    reviewRow(
                        id: flight.id,
                        icon: "airplane",
                        title: flight.flightNumber + rangeSuffix(flight.departureAirport, flight.arrivalAirport),
                        subtitle: [flight.airline, flight.departureLocal.map(pretty), flight.seat.map { "Seat \($0)" }]
                            .compactMap { $0 }.joined(separator: " · "),
                        confidence: flight.confidence
                    )
                }
                ForEach(parsed.hotels) { hotel in
                    reviewRow(
                        id: hotel.id,
                        icon: "bed.double.fill",
                        title: hotel.name,
                        subtitle: [hotel.checkInLocal.map { "In \(pretty($0))" }, hotel.checkOutLocal.map { "Out \(pretty($0))" }]
                            .compactMap { $0 }.joined(separator: " · "),
                        confidence: hotel.confidence
                    )
                }
                ForEach(parsed.carRentals) { car in
                    reviewRow(
                        id: car.id,
                        icon: "car.fill",
                        title: car.company + (car.vehicleClass.map { " — \($0)" } ?? ""),
                        subtitle: [car.pickupLocation, car.pickupLocal.map(pretty)]
                            .compactMap { $0 }.joined(separator: " · "),
                        confidence: car.confidence
                    )
                }
                ForEach(parsed.meetings) { meeting in
                    reviewRow(
                        id: meeting.id,
                        icon: "person.2.fill",
                        title: meeting.title,
                        subtitle: [meeting.startLocal.map(pretty), meeting.location]
                            .compactMap { $0 }.joined(separator: " · "),
                        confidence: meeting.confidence
                    )
                }
                ForEach(parsed.disruptions) { notice in
                    reviewRow(
                        id: notice.id,
                        icon: "exclamationmark.triangle.fill",
                        title: "\(notice.kind.replacingOccurrences(of: "_", with: " ").capitalized) — \(notice.flightNumber)",
                        subtitle: notice.details ?? "",
                        confidence: notice.confidence
                    )
                }

                if !parsed.meetings.isEmpty {
                    Toggle(isOn: $viewModel.syncMeetingsToCalendar) {
                        Text("Add meetings to Calendar")
                            .font(.caption.bold())
                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    }
                    .tint(JetsetterTheme.Colors.accent)
                }

                Text("Times are as stated in the email (no timezone conversion) — double-check anything that crosses timezones.")
                    .font(.system(size: 10))
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary.opacity(0.8))

                Button {
                    Task { await viewModel.commitSelection() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text("Add \(viewModel.selectedIDs.count) to JetSetter")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(viewModel.hasSelection ? JetsetterTheme.Colors.success : JetsetterTheme.Colors.textSecondary.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!viewModel.hasSelection || viewModel.isWorking)
            }
            .padding(JetsetterTheme.Card.padding)
            .jetCard()
        }
    }

    private func reviewRow(id: UUID, icon: String, title: String, subtitle: String, confidence: Double) -> some View {
        Button {
            viewModel.toggle(id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: viewModel.isSelected(id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(viewModel.isSelected(id) ? JetsetterTheme.Colors.success : JetsetterTheme.Colors.textSecondary.opacity(0.5))

                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()

                if confidence < 0.7 {
                    GoldTag(text: "CHECK", icon: "questionmark")
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status + summary

    private func statusBanner(_ message: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "info.circle.fill")
            Text(message).font(.caption)
            Spacer()
        }
        .foregroundStyle(isError ? JetsetterTheme.Colors.danger : JetsetterTheme.Colors.accent)
        .padding(12)
        .background((isError ? JetsetterTheme.Colors.danger : JetsetterTheme.Colors.accent).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func summaryCard(_ summary: TravelEmailCommitService.Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(JetsetterTheme.Colors.success)
                Text("Done")
                    .font(JetsetterTheme.Typography.cardTitle)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            }
            ForEach(summary.lines, id: \.self) { line in
                Text("• " + line)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            if summary.calendarEvents > 0 {
                Text("• \(summary.calendarEvents) calendar event\(summary.calendarEvents == 1 ? "" : "s") created")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: - Formatting helpers

    private func rangeSuffix(_ from: String?, _ to: String?) -> String {
        let route = [from, to].compactMap { $0 }.joined(separator: " → ")
        return route.isEmpty ? "" : " · \(route)"
    }

    private func pretty(_ local: String) -> String {
        guard let date = TravelDateParser.date(from: local) else { return local }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = local.count > 10 ? .short : .none
        return f.string(from: date)
    }
}

#Preview {
    NavigationStack {
        EmailImportView()
    }
}
