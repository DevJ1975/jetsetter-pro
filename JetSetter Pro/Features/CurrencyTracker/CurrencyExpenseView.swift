// File: Features/CurrencyTracker/CurrencyExpenseView.swift
// Currency converter card + expense tracker with donut chart (Feature 3).
// Scaffolded UI — full implementation in Feature 3 sprint.

import SwiftUI
import Charts

struct CurrencyExpenseView: View {

    @State private var vm: CurrencyExpenseViewModel
    @Environment(SubscriptionManager.self) private var subscriptions
    @State private var showAddExpense = false

    init(trip: Trip, homeCurrency: String = "USD", destinationCurrency: String = "JPY") {
        _vm = State(wrappedValue: CurrencyExpenseViewModel(
            trip: trip,
            homeCurrency: homeCurrency,
            destinationCurrency: destinationCurrency
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    errorBanner
                    converterCard
                    budgetCard
                    spendChartCard
                    expensesList
                }
                .padding(16)
            }
            .background(JetsetterTheme.Colors.background)
            .navigationTitle("Currency & Expenses")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddExpense = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $showAddExpense) {
                AddExpenseSheet(vm: vm)
            }
        }
        .premiumGate(feature: "Currency + Expense Tracker")
    }

    // MARK: - Converter Card

    private var converterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CURRENCY CONVERTER")
                .font(JetsetterTheme.Typography.label)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .tracking(1.5)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.inputCurrency)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    TextField("0.00", text: $vm.converterInput)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                }

                Button {
                    vm.toggleDirection()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap conversion direction")

                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.outputCurrency)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    if let converted = vm.convertedAmount {
                        Text(Self.formatAmount(converted, code: vm.outputCurrency, includeCode: false))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                    } else {
                        Text("—")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                }
            }

            if vm.exchangeRates == nil {
                Text("Fetching live rates…")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            } else if let rates = vm.exchangeRates, !rates.isFresh {
                // Cached rates older than the freshness window (typically because
                // the device is offline). Surface the age so users know a
                // conversion may be stale.
                Label(
                    "Rates from \(rates.fetchedAt.formatted(.relative(presentation: .named))) — may be out of date",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.caption)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
        .padding(16)
        .jetCard()
    }

    // MARK: - Error Banner

    /// Surfaces a rate-load failure with a retry affordance. Without this the
    /// converter/summary silently show "—" / undercounts while `errorMessage`
    /// was set but never read.
    @ViewBuilder
    private var errorBanner: some View {
        if let message = vm.errorMessage {
            Button {
                Task { await vm.retry() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(JetsetterTheme.Colors.danger)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if vm.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .jetCard()
            }
            .buttonStyle(.plain)
            .disabled(vm.isLoading)
        }
    }

    // MARK: - Budget Card

    private var budgetCard: some View {
        Group {
            if let summary = vm.budgetSummary {
                VStack(alignment: .leading, spacing: 12) {
                    Text("TRIP SPEND")
                        .font(JetsetterTheme.Typography.label)
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .tracking(1.5)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Self.formatAmount(summary.totalSpentHome, code: vm.homeCurrency))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(summary.isOverBudget ? JetsetterTheme.Colors.danger : JetsetterTheme.Colors.textPrimary)
                            Text("total spent")
                                .font(.caption)
                                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        }
                        Spacer()
                        if let budget = vm.budget {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(Self.formatAmount(budget, code: vm.homeCurrency))
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                                Text("budget")
                                    .font(.caption)
                                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                            }
                        }
                    }

                    if let progress = summary.budgetProgress {
                        ProgressView(value: progress)
                            .tint(summary.isOverBudget ? JetsetterTheme.Colors.danger : JetsetterTheme.Colors.accent)
                    }
                }
                .padding(16)
                .jetCard()
            }
        }
    }

    // MARK: - Donut Chart

    private var spendChartCard: some View {
        Group {
            if let summary = vm.budgetSummary, !summary.spendByCategory.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("SPEND BY CATEGORY")
                        .font(JetsetterTheme.Typography.label)
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .tracking(1.5)

                    Chart(SpendCategory.allCases.filter { summary.spendByCategory[$0] != nil }, id: \.self) { cat in
                        SectorMark(
                            angle: .value("Amount", summary.spendByCategory[cat] ?? 0),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(Color(hex: cat.colorHex))
                        .cornerRadius(4)
                    }
                    .frame(height: 180)
                }
                .padding(16)
                .jetCard()
            }
        }
    }

    // MARK: - Expenses List

    private var expensesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT EXPENSES")
                .font(JetsetterTheme.Typography.label)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .tracking(1.5)
                .padding(.leading, 4)

            if vm.expenses.isEmpty {
                Text("No expenses yet. Tap + to add one.")
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .jetCard()
            } else {
                VStack(spacing: 1) {
                    ForEach(vm.expenses.sorted { $0.date > $1.date }) { expense in
                        expenseRow(expense)
                    }
                }
                .jetCard()
            }
        }
    }

    // MARK: - Currency Formatting

    /// Formats a money amount using the correct number of fraction digits for the
    /// given ISO currency code (e.g. JPY/KRW/VND → 0 decimals, USD/EUR → 2), so
    /// zero-decimal currencies don't render misleading ".00" fractions.
    /// When `includeCode` is true the ISO code is shown as a prefix ("USD 1,500.00").
    static func formatAmount(_ amount: Double, code: String, includeCode: Bool = true) -> String {
        MoneyFormatting.formatAmount(amount, code: code, includeCode: includeCode)
    }

    private func expenseRow(_ expense: CurrencyExpense) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: expense.category.colorHex).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: expense.category.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: expense.category.colorHex))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.description)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text(expense.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Self.formatAmount(expense.amount, code: expense.currency))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                if let converted = expense.convertedAmount {
                    Text("≈ " + Self.formatAmount(converted, code: expense.homeCurrency))
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                vm.deleteExpense(id: expense.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - AddExpenseSheet (Inline)

private struct AddExpenseSheet: View {

    @Bindable var vm: CurrencyExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var amount = ""
    @State private var description = ""
    @State private var category: SpendCategory = .food

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount (\(vm.destinationCurrency))") {
                    TextField("0.00", text: $amount).keyboardType(.decimalPad)
                }
                Section("Details") {
                    TextField("Description", text: $description)
                    Picker("Category", selection: $category) {
                        ForEach(SpendCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let amt = CurrencyExpenseViewModel.parseDecimal(amount), !description.isEmpty {
                            vm.addExpense(amount: amt, category: category, description: description)
                            dismiss()
                        }
                    }
                    .disabled(CurrencyExpenseViewModel.parseDecimal(amount) == nil || description.isEmpty)
                }
            }
        }
    }
}

// MARK: - Router

/// Picks the next upcoming trip (or the most recent past trip) for the user's
/// home currency tracker. Surfaces an empty-state when there are no trips.
struct CurrencyExpenseRouterView: View {

    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        if let trip = nextOrLatestTrip() {
            CurrencyExpenseView(
                trip: trip,
                homeCurrency: preferences.currency.isEmpty ? "USD" : preferences.currency,
                destinationCurrency: destinationCurrency(for: trip)
            )
        } else {
            ContentUnavailableView(
                "No Active Trip",
                systemImage: "airplane.circle",
                description: Text("Create a trip in the Itinerary tab to start tracking expenses.")
            )
        }
    }

    private func nextOrLatestTrip() -> Trip? {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips") else { return nil }
        guard let trips = try? JSONCoding.iso8601Decoder.decode([Trip].self, from: data) else { return nil }

        let now = Date()
        let upcoming = trips.filter { $0.endDate >= now }.sorted { $0.startDate < $1.startDate }
        if let next = upcoming.first { return next }
        return trips.sorted { $0.endDate > $1.endDate }.first
    }

    /// Maps the country/city portion of `Trip.destination` to its currency code.
    ///
    /// Matching happens in two passes to avoid the false-positive substring hits
    /// that a naive `contains` produces (e.g. the key "uk" matching "Fukuoka"):
    ///   1. Multi-word keys ("hong kong", "new zealand") are matched as
    ///      substrings, since they are unambiguous.
    ///   2. Single-word keys are matched against whitespace/punctuation-delimited
    ///      tokens, so "uk" only matches the standalone token "uk".
    /// When the curated map misses, we fall back to `Locale`'s region→currency
    /// resolution before finally defaulting to the home currency.
    private func destinationCurrency(for trip: Trip) -> String {
        let lower = trip.destination.lowercased()
        let map: [String: String] = [
            "japan": "JPY", "tokyo": "JPY", "osaka": "JPY", "kyoto": "JPY",
            "united kingdom": "GBP", "uk": "GBP", "london": "GBP",
            "france": "EUR", "paris": "EUR",
            "germany": "EUR", "berlin": "EUR", "munich": "EUR",
            "italy": "EUR", "rome": "EUR", "milan": "EUR",
            "spain": "EUR", "madrid": "EUR", "barcelona": "EUR",
            "netherlands": "EUR", "amsterdam": "EUR",
            "portugal": "EUR", "lisbon": "EUR", "porto": "EUR",
            "ireland": "EUR", "dublin": "EUR",
            "greece": "EUR", "athens": "EUR",
            "switzerland": "CHF", "zurich": "CHF",
            "canada": "CAD", "toronto": "CAD", "vancouver": "CAD",
            "mexico": "MXN", "cdmx": "MXN", "cancun": "MXN",
            "brazil": "BRL", "rio": "BRL", "sao paulo": "BRL",
            "australia": "AUD", "sydney": "AUD", "melbourne": "AUD",
            "new zealand": "NZD", "auckland": "NZD",
            "china": "CNY", "shanghai": "CNY", "beijing": "CNY",
            "hong kong": "HKD",
            "singapore": "SGD",
            "south korea": "KRW", "seoul": "KRW",
            "thailand": "THB", "bangkok": "THB",
            "vietnam": "VND", "hanoi": "VND",
            "india": "INR", "mumbai": "INR", "delhi": "INR",
            "uae": "AED", "dubai": "AED", "abu dhabi": "AED",
            "south africa": "ZAR", "cape town": "ZAR",
            "argentina": "ARS", "buenos aires": "ARS",
            "turkey": "TRY", "istanbul": "TRY",
            "egypt": "EGP", "cairo": "EGP"
        ]

        // Tokenize on anything that isn't a letter so "Fukuoka, Japan" -> ["fukuoka", "japan"].
        let tokens = Set(lower.split { !$0.isLetter }.map(String.init))

        // Pass 1: unambiguous multi-word keys via substring.
        for (key, currency) in map where key.contains(" ") && lower.contains(key) {
            return currency
        }
        // Pass 2: single-word keys via exact token match (no substring bleed).
        for (key, currency) in map where !key.contains(" ") && tokens.contains(key) {
            return currency
        }

        // Fallback: try to resolve a currency from the region name via Locale
        // before defaulting to home, so unmapped destinations (e.g. Poland)
        // still track in a plausible local currency.
        if let resolved = currencyFromLocale(tokens: tokens) {
            return resolved
        }

        return preferences.currency.isEmpty ? "USD" : preferences.currency
    }

    /// Attempts to resolve an ISO currency code from region tokens by matching
    /// each token against the localized display name of every known region.
    private func currencyFromLocale(tokens: Set<String>) -> String? {
        guard !tokens.isEmpty else { return nil }
        let english = Locale(identifier: "en_US")
        for regionCode in Locale.Region.isoRegions {
            let identifier = regionCode.identifier
            guard let name = english.localizedString(forRegionCode: identifier)?.lowercased()
            else { continue }
            // Match the full region name as a token set intersection so
            // "united states" matches destination "United States".
            let nameTokens = Set(name.split { !$0.isLetter }.map(String.init))
            guard !nameTokens.isEmpty, nameTokens.isSubset(of: tokens) else { continue }
            var components = Locale.Components(locale: english)
            components.region = regionCode
            if let currency = Locale(components: components).currency?.identifier {
                return currency
            }
        }
        return nil
    }
}

#Preview {
    CurrencyExpenseView(trip: .sample)
        .environment(SubscriptionManager.shared)
}
