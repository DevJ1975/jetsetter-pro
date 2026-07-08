// File: Features/EmailImport/EmailImportViewModel.swift
//
// Drives the Email Intelligence screen: intake (paste / file / photo /
// forwarding inbox) → parse → review selection → commit.

import Foundation
import SwiftUI

@MainActor
final class EmailImportViewModel: ObservableObject {

    // MARK: - Input

    @Published var inputText = ""
    @Published var syncMeetingsToCalendar = true

    // MARK: - State

    @Published var isWorking = false
    @Published var parsed: ParsedTravelEmail?
    @Published var selectedIDs: Set<UUID> = []
    @Published var statusMessage: String?
    @Published var isStatusError = false
    @Published var summary: TravelEmailCommitService.Summary?
    @Published var forwardingAlias: String?

    var providerLabel: String { TravelEmailParsingService.shared.providerStatusLabel }

    var hasSelection: Bool { !selectedIDs.isEmpty }

    // MARK: - Intake

    func parsePastedText() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await run {
            let result = try await TravelEmailParsingService.shared.parse(emailText: text)
            self.apply(result)
        }
    }

    func importFile(at url: URL) async {
        await run {
            let text = try await TravelEmailIngestService.shared.text(fromFileAt: url)
            let result = try await TravelEmailParsingService.shared.parse(emailText: text)
            self.apply(result)
        }
    }

    func importImage(_ image: UIImage) async {
        await run {
            let text = try await TravelEmailIngestService.shared.text(fromImage: image)
            let result = try await TravelEmailParsingService.shared.parse(emailText: text)
            self.apply(result)
        }
    }

    /// Pulls anything waiting in the forwarding inbox (signed-in users).
    func checkForwardingInbox() async {
        await run {
            let (result, count) = try await TravelEmailIngestService.shared.fetchAndParseInbox()
            if count == 0 {
                self.status("No new forwarded emails.", isError: false)
            } else {
                self.status("Parsed \(count) forwarded email\(count == 1 ? "" : "s").", isError: false)
            }
            self.apply(result)
        }
    }

    func loadForwardingAlias() async {
        forwardingAlias = await TravelEmailIngestService.shared.forwardingAlias()
    }

    // MARK: - Review selection

    func isSelected(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func discardReview() {
        parsed = nil
        selectedIDs = []
        statusMessage = nil
    }

    // MARK: - Commit

    func commitSelection() async {
        guard let parsed, hasSelection else { return }
        isWorking = true
        let options = TravelEmailCommitService.Options(
            syncMeetingsToCalendar: syncMeetingsToCalendar,
            scheduleFlightAlerts: true
        )
        let result = await TravelEmailCommitService.shared.commit(
            parsed,
            selectedIDs: selectedIDs,
            options: options
        )
        summary = result
        self.parsed = nil
        selectedIDs = []
        inputText = ""
        statusMessage = nil
        isWorking = false
    }

    // MARK: - Helpers

    private func run(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        statusMessage = nil
        summary = nil
        do {
            try await work()
        } catch {
            status(error.localizedDescription, isError: true)
        }
        isWorking = false
    }

    private func status(_ message: String, isError: Bool) {
        statusMessage = message
        isStatusError = isError
    }

    private func apply(_ result: ParsedTravelEmail) {
        guard !result.isEmpty else {
            if parsed == nil {
                status("No travel details found — is this a booking, invite, or airline email?", isError: true)
            }
            return
        }
        var merged = parsed ?? ParsedTravelEmail()
        merged.merge(result)
        parsed = merged

        // New entities start selected.
        selectedIDs.formUnion(result.flights.map(\.id))
        selectedIDs.formUnion(result.hotels.map(\.id))
        selectedIDs.formUnion(result.carRentals.map(\.id))
        selectedIDs.formUnion(result.meetings.map(\.id))
        selectedIDs.formUnion(result.disruptions.map(\.id))
    }
}
