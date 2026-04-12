// File: Features/CurrencyTracker/CurrencyExpenseView.swift
// Currency converter card + expense tracker with donut chart (Feature 3).
// Scaffolded UI — full implementation in Feature 3 sprint.

import SwiftUI
import Charts

struct CurrencyExpenseView: View {

    @StateObject private var vm: CurrencyExpenseViewModel
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @State private var showAddExpense = false

    init(trip: Trip, homeCurrency: String = "USD", destinationCurrency: String = "JPY") {
        _vm = StateObject(wrappedValue: CurrencyExpenseViewModel(
            trip: trip,
            homeCurrency: homeCurrency,
            destinationCurrency: destinationCurrency
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
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
                    Text(vm.homeCurrency)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    TextField("0.00", text: $vm.converterInput)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                }

                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.destinationCurrency)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    if let converted = vm.convertedAmount {
                        Text(String(format: "%.2f", converted))
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
            }
        }
        .padding(16)
        .jetCard()
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
                            Text(String(format: "%@ %.2f", vm.homeCurrency, summary.totalSpentHome))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(summary.isOverBudget ? JetsetterTheme.Colors.danger : JetsetterTheme.Colors.textPrimary)
                            Text("total spent")
                                .font(.caption)
                                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        }
                        Spacer()
                        if let budget = vm.budget {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(String(format: "%@ %.0f", vm.homeCurrency, budget))
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
                Text(String(format: "%@ %.2f", expense.currency, expense.amount))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                if let converted = expense.convertedAmount {
                    Text(String(format: "≈ %@ %.2f", expense.homeCurrency, converted))
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .swipeActions(edge: .trailing) {
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

    @ObservedObject var vm: CurrencyExpenseViewModel
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
                        if let amt = Double(amount), !description.isEmpty {
                            vm.addExpense(amount: amt, category: category, description: description)
                            dismiss()
                        }
                    }
                    .disabled(Double(amount) == nil || description.isEmpty)
                }
            }
        }
    }
}

#Preview {
    CurrencyExpenseView(trip: .sample)
        .environmentObject(SubscriptionManager.shared)
}
