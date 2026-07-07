// File: Features/ExpenseExport/ExpenseExportView.swift

import SwiftUI

struct ExpenseExportView: View {

    @State private var allExpenses: [Expense] = []
    @State private var trip: Trip?
    @State private var selectedExpenseIDs: Set<UUID> = []
    @State private var isSubmitting: Bool = false
    @State private var resultMessage: String?
    @State private var showResultBanner: Bool = false
    @State private var isError: Bool = false
    @State private var successOverlay: SuccessPayload? = nil
    @State private var hasLoadedOnce: Bool = false
    /// IDs seen on the previous load, so reloads can tell newly-added expenses
    /// (which default to selected) from ones the user deliberately deselected.
    @State private var knownExpenseIDs: Set<UUID> = []

    @Environment(\.scenePhase) private var scenePhase

    private struct SuccessPayload: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let referenceNumber: String
    }

    @State private var providers: [any ExpenseExportProvider] = [EmailPDFProvider.shared]

    private var matchingExpenses: [Expense] {
        guard let trip = trip else { return allExpenses }
        // Treat the trip as a set of whole calendar days, independent of any
        // time-of-day carried by start/endDate and robust across DST.
        let cal = Calendar.current
        let start = cal.startOfDay(for: trip.startDate)
        let endIncl = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: trip.endDate)) ?? trip.endDate
        return allExpenses.filter { $0.date >= start && $0.date < endIncl }
    }

    private var selectedExpenses: [Expense] {
        matchingExpenses.filter { selectedExpenseIDs.contains($0.id) }
    }

    /// Per-currency subtotals for the selected expenses. Summing raw `amount`
    /// values across mixed currencies would be nonsense, so we group first.
    private var totalsByCurrency: [(currency: String, amount: Double)] {
        Dictionary(grouping: selectedExpenses, by: \.currency)
            .map { (currency: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.currency < $1.currency }
    }

    /// A single presentable string, e.g. "USD 120.00 · EUR 80.00".
    private var totalSelectedDisplay: String {
        let totals = totalsByCurrency
        guard !totals.isEmpty else { return format(0, currency: "USD") }
        return totals
            .map { format($0.amount, currency: $0.currency) }
            .joined(separator: "  ·  ")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                tripCard
                if matchingExpenses.isEmpty {
                    emptyCard
                } else {
                    summaryCard
                    expensesList
                    providerSection
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Submit Expenses")
        .navigationBarTitleDisplayMode(.large)
        .task {
            load()
            providers = await ExpenseExportRegistry.connectedProviders()
        }
        .onChange(of: scenePhase) { _, phase in
            // Expenses (and connections) may have changed while backgrounded or
            // on another screen; re-read the snapshots when we come back to the
            // foreground. load() reconciles the selection rather than resetting it.
            guard phase == .active, hasLoadedOnce else { return }
            load()
            Task { providers = await ExpenseExportRegistry.connectedProviders() }
        }
        .overlay(alignment: .top) {
            if showResultBanner, let msg = resultMessage {
                banner(message: msg, isError: isError)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if let payload = successOverlay {
                SuccessAnimationView(
                    title: payload.title,
                    subtitle: payload.subtitle,
                    referenceNumber: payload.referenceNumber,
                    onDismiss: { successOverlay = nil }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: showResultBanner)
        .animation(.easeInOut(duration: 0.25), value: successOverlay?.id)
    }

    // MARK: - Sections

    private var tripCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "airplane.circle.fill").font(.caption.bold())
                Text(trip == nil ? "ALL EXPENSES" : "TRIP")
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)

            if let trip = trip {
                Text(trip.name).font(.headline)
                Text("\(trip.destination)  ·  \(trip.startDate, format: .dateTime.month().day()) – \(trip.endDate, format: .dateTime.month().day().year())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No active trip — showing all expenses")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private var summaryCard: some View {
        HStack(spacing: 16) {
            stat(label: "MATCHING", value: "\(matchingExpenses.count)")
            Divider().frame(height: 36)
            stat(label: "SELECTED", value: "\(selectedExpenseIDs.count)")
            Divider().frame(height: 36)
            stat(label: "TOTAL", value: totalSelectedDisplay)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    private func stat(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .black))
                .tracking(1.3)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var expensesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle.fill").font(.caption.bold())
                    Text("EXPENSES").font(JetsetterTheme.Typography.label).tracking(1.5)
                }
                .foregroundStyle(JetsetterTheme.Colors.accent)
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected { selectedExpenseIDs.removeAll() }
                    else { selectedExpenseIDs = Set(matchingExpenses.map(\.id)) }
                }
                .font(.caption.bold())
                .foregroundStyle(JetsetterTheme.Colors.accent)
            }
            .padding(.leading, 4)

            VStack(spacing: 1) {
                ForEach(matchingExpenses.sorted(by: { $0.date > $1.date })) { expense in
                    row(expense)
                }
            }
            .jetCard()
        }
    }

    private var allSelected: Bool {
        !matchingExpenses.isEmpty && selectedExpenseIDs.count == matchingExpenses.count
    }

    private func row(_ expense: Expense) -> some View {
        let selected = selectedExpenseIDs.contains(expense.id)
        return Button {
            if selected { selectedExpenseIDs.remove(expense.id) }
            else        { selectedExpenseIDs.insert(expense.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? JetsetterTheme.Colors.accent : JetsetterTheme.Colors.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(expense.merchant)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text("\(expense.category.displayName)  ·  \(expense.date, format: .dateTime.month(.abbreviated).day())")
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
                Spacer()
                Text(format(expense.amount, currency: expense.currency))
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill").font(.caption.bold())
                Text("SUBMIT TO").font(JetsetterTheme.Typography.label).tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            .padding(.leading, 4)

            ForEach(providers, id: \.id) { provider in
                providerCard(provider)
            }
            NavigationLink {
                ExpenseConnectionsView()
            } label: {
                HStack {
                    Image(systemName: "link.circle")
                    Text("Connect more providers")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .font(.caption.bold())
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }
        }
    }

    private func providerCard(_ provider: any ExpenseExportProvider) -> some View {
        Button {
            Task { await submit(via: provider) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: provider.brandColorHex))
                        .frame(width: 44, height: 44)
                    Image(systemName: provider.systemImage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text(provider.tagline)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
                Spacer()
                if isSubmitting {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.bold())
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .jetCard()
        }
        .buttonStyle(.plain)
        .disabled(selectedExpenseIDs.isEmpty || isSubmitting)
        .opacity(selectedExpenseIDs.isEmpty ? 0.5 : 1.0)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No expenses to submit")
                .font(.headline)
            Text("Log expenses in the Expenses tab — they'll appear here, ready to send.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24).frame(maxWidth: .infinity)
        .jetCard()
    }

    private func banner(message: String, isError: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .foregroundStyle(isError ? JetsetterTheme.Colors.danger : JetsetterTheme.Colors.success)
            Text(message)
                .font(.subheadline)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.1), radius: 8)
    }

    // MARK: - Logic

    private func load() {
        // Trip = next or current
        if let data = UserDefaults.standard.data(forKey: "jetsetter_trips") {
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            let trips = (try? d.decode([Trip].self, from: data)) ?? []
            let now = Date()
            trip = trips
                .filter { $0.endDate >= now }
                .sorted { $0.startDate < $1.startDate }
                .first
                ?? trips.sorted { $0.endDate > $1.endDate }.first
        }
        // Expenses
        if let data = UserDefaults.standard.data(forKey: "jetsetter_expenses") {
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            allExpenses = (try? d.decode([Expense].self, from: data)) ?? []
        }

        let matchingIDs = Set(matchingExpenses.map(\.id))
        if hasLoadedOnce {
            // On reload, preserve the user's manual choices: keep any still-valid
            // selection, drop IDs whose expense disappeared, and select any newly
            // matching expenses so fresh entries default to included (matching the
            // initial "select all" behaviour).
            let newlyMatched = matchingIDs.subtracting(knownExpenseIDs)
            selectedExpenseIDs = selectedExpenseIDs
                .intersection(matchingIDs)
                .union(newlyMatched)
        } else {
            // First appearance: pre-select everything that matches.
            selectedExpenseIDs = matchingIDs
        }
        knownExpenseIDs = Set(allExpenses.map(\.id))
        hasLoadedOnce = true
    }

    private func submit(via provider: any ExpenseExportProvider) async {
        guard !selectedExpenses.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        // The provider list is fetched once when the screen appears. A token can
        // expire or the user can disconnect elsewhere in the meantime, so confirm
        // the provider is still connected before submitting. This surfaces a
        // clean "reconnect" prompt and refreshes the button list instead of
        // letting submit() throw a raw notConnected error.
        if await !provider.isConnected() {
            providers = await ExpenseExportRegistry.connectedProviders()
            isError = true
            resultMessage = "\(provider.displayName) is no longer connected. Reconnect it and try again."
            showBannerBriefly()
            return
        }

        do {
            let result = try await provider.submit(trip: trip, expenses: selectedExpenses)
            let succeeded = result.successCount
            let failed = result.failedCount

            if succeeded == 0 {
                // Nothing went through — surface as an error.
                isError = true
                let failedItems = failed + result.skippedCount
                resultMessage = "Couldn't send \(failedItems) expense\(failedItems == 1 ? "" : "s") via \(result.providerName). Try again."
            } else if failed > 0 {
                // Partial success — warn but don't celebrate.
                isError = true
                resultMessage = "Sent \(succeeded), \(failed) failed via \(result.providerName) — try again."
            } else {
                // Pure success: everything requested went through.
                isError = false
                resultMessage = "Sent \(succeeded) expense\(succeeded == 1 ? "" : "s") via \(result.providerName)."
                // Show the celebratory confirmation for any real remote submission
                // — not just demo builds. EmailPDF has no remote reference to
                // surface, so it keeps the lightweight banner.
                if !(provider is EmailPDFProvider) {
                    successOverlay = SuccessPayload(
                        title: "Submitted to \(result.providerName)",
                        subtitle: "Report created for \(succeeded) expense\(succeeded == 1 ? "" : "s")",
                        // Prefer the provider's real remote ID (meaningful on the
                        // expense platform) over an invented placeholder.
                        referenceNumber: primaryReferenceNumber(from: result)
                    )
                    return
                }
            }
        } catch ExpenseExportError.userCancelled {
            return  // silent
        } catch {
            isError = true
            resultMessage = error.localizedDescription
        }
        showBannerBriefly()
    }

    /// A reference number to show in the confirmation overlay. Prefers the
    /// provider's real remote ID (which the user can look up on the expense
    /// platform); when a batch produced several, we show the first submitted one
    /// with a "+N more" hint. Falls back to a generated tag only if no remote ID
    /// came back.
    private func primaryReferenceNumber(from result: ExportBatchResult) -> String {
        let remoteIDs: [String] = result.perExpense.values.compactMap {
            if case .submitted(let remoteID) = $0 { return remoteID }
            return nil
        }
        guard let first = remoteIDs.first else {
            return "JS-\(Int.random(in: 1000...9999))-\(Int.random(in: 10...99))"
        }
        if remoteIDs.count > 1 {
            return "\(first)  +\(remoteIDs.count - 1) more"
        }
        return first
    }

    private func showBannerBriefly() {
        showResultBanner = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { showResultBanner = false }
        }
    }

    // MARK: - Helpers

    private func format(_ amount: Double, currency: String) -> String {
        String(format: "%@ %.2f", currency, amount)
    }
}

#Preview {
    NavigationStack { ExpenseExportView() }
}
