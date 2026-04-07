// File: Features/ExpenseTracker/ExpenseTrackerView.swift

import SwiftUI

// MARK: - ExpenseTrackerView

/// Main expense list screen with total summary, scan receipt, log mileage, and manual entry.
struct ExpenseTrackerView: View {

    @StateObject private var viewModel = ExpenseViewModel()
    @State private var isShowingScanReceipt: Bool = false
    @State private var isShowingAddManual: Bool = false
    @State private var isShowingLogMileage: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                totalSummaryCard
                expenseList
            }
            .navigationTitle("Expenses")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            isShowingScanReceipt = true
                        } label: {
                            Label("Scan Receipt", systemImage: "camera.fill")
                        }
                        Button {
                            isShowingLogMileage = true
                        } label: {
                            Label("Log Mileage", systemImage: "road.lanes")
                        }
                        Button {
                            isShowingAddManual = true
                        } label: {
                            Label("Add Manually", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                }
            }
            .sheet(isPresented: $isShowingScanReceipt) {
                ScanReceiptView(viewModel: viewModel)
            }
            .sheet(isPresented: $isShowingAddManual) {
                AddExpenseView(viewModel: viewModel)
            }
            .sheet(isPresented: $isShowingLogMileage) {
                LogMileageView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Total Summary Card

    private var totalSummaryCard: some View {
        VStack(spacing: JetsetterTheme.Spacing.small) {
            Text("Total Spent")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(String(format: "USD %.2f", viewModel.totalAmount))
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(JetsetterTheme.Colors.primary)

            // Category breakdown chips
            if !viewModel.expensesByCategory.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JetsetterTheme.Spacing.small) {
                        ForEach(
                            viewModel.expensesByCategory.sorted { $0.value > $1.value },
                            id: \.key
                        ) { category, total in
                            categoryChip(category: category, total: total)
                        }
                    }
                    .padding(.horizontal, JetsetterTheme.Spacing.medium)
                }
            }
        }
        .padding(.vertical, JetsetterTheme.Spacing.medium)
        .frame(maxWidth: .infinity)
        .background(.background)
    }

    private func categoryChip(category: ExpenseCategory, total: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: category.systemImage)
                .font(.caption2)
            Text(String(format: "$%.0f", total))
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(hex: category.colorHex).opacity(0.12))
        .foregroundStyle(Color(hex: category.colorHex))
        .cornerRadius(20)
    }

    // MARK: - Expense List

    @ViewBuilder
    private var expenseList: some View {
        if viewModel.expenses.isEmpty {
            emptyStateView
        } else {
            List {
                ForEach(viewModel.sortedExpenses) { expense in
                    ExpenseRowView(expense: expense)
                }
                .onDelete { offsets in
                    viewModel.deleteExpense(at: offsets)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: JetsetterTheme.Spacing.large) {
            Spacer()
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 60))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))

            VStack(spacing: JetsetterTheme.Spacing.small) {
                Text("No Expenses Yet")
                    .font(.headline)
                Text("Tap + to scan a receipt, log mileage, or add an expense manually.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JetsetterTheme.Spacing.xlarge)
            }
            Spacer()
        }
    }
}

// MARK: - ExpenseRowView

private struct ExpenseRowView: View {
    let expense: Expense

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: expense.category.systemImage)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(hex: expense.category.colorHex))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchant)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: JetsetterTheme.Spacing.xsmall) {
                    Text(expense.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(dateFormatter.string(from: expense.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let miles = expense.mileageDistance {
                    Text(String(format: "%.1f mi @ $%.2f/mi", miles, Expense.irsMileageRatePerMile))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(expense.formattedAmount)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AddExpenseView

/// Manual expense entry form sheet.
struct AddExpenseView: View {

    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String = ""
    @State private var merchant: String = ""
    @State private var category: ExpenseCategory = .other
    @State private var date: Date = Date()
    @State private var notes: String = ""

    private var canSave: Bool {
        !amount.isEmpty && Double(amount) != nil && !merchant.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    HStack {
                        Text("$").foregroundStyle(.secondary)
                        TextField("0.00", text: $amount).keyboardType(.decimalPad)
                    }
                }
                Section("Details") {
                    TextField("Merchant / Description", text: $merchant)
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section("Notes (optional)") {
                    TextField("Notes…", text: $notes)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(JetsetterTheme.Colors.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? JetsetterTheme.Colors.accent : .secondary)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let amountValue = Double(amount) else { return }
        viewModel.addExpense(Expense(
            amount: amountValue,
            category: category,
            merchant: merchant,
            date: date,
            notes: notes.isEmpty ? nil : notes
        ))
        dismiss()
    }
}

// MARK: - LogMileageView

/// Mileage entry form — from/to addresses + auto-calculated distance.
struct LogMileageView: View {

    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var fromAddress: String = ""
    @State private var toAddress: String = ""
    @State private var calculatedMiles: Double? = nil
    @State private var isCalculating: Bool = false
    @State private var notes: String = ""

    private var reimbursementAmount: String {
        guard let miles = calculatedMiles else { return "—" }
        return String(format: "USD %.2f", Expense.mileageAmount(for: miles))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    TextField("From (e.g. SFO Airport)", text: $fromAddress)
                    TextField("To (e.g. Park Hyatt San Francisco)", text: $toAddress)

                    Button {
                        Task { await calculateDistance() }
                    } label: {
                        HStack {
                            Text("Calculate Distance")
                            Spacer()
                            if isCalculating {
                                ProgressView()
                            } else if let miles = calculatedMiles {
                                Text(String(format: "%.1f mi", miles))
                                    .foregroundStyle(JetsetterTheme.Colors.accent)
                            }
                        }
                    }
                    .disabled(fromAddress.isEmpty || toAddress.isEmpty || isCalculating)
                }

                Section("Reimbursement") {
                    HStack {
                        Text("IRS Rate (\(String(format: "$%.2f/mi", Expense.irsMileageRatePerMile)))")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(reimbursementAmount)
                            .fontWeight(.semibold)
                    }
                }

                Section("Notes (optional)") {
                    TextField("Notes…", text: $notes)
                }
            }
            .navigationTitle("Log Mileage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(JetsetterTheme.Colors.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(calculatedMiles != nil ? JetsetterTheme.Colors.accent : .secondary)
                        .disabled(calculatedMiles == nil)
                }
            }
        }
    }

    private func calculateDistance() async {
        isCalculating = true
        calculatedMiles = await viewModel.calculateDistance(from: fromAddress, to: toAddress)
        isCalculating = false
    }

    private func save() {
        guard let miles = calculatedMiles else { return }
        viewModel.logMileage(
            fromAddress: fromAddress,
            toAddress: toAddress,
            distanceMiles: miles,
            notes: notes.isEmpty ? nil : notes
        )
        dismiss()
    }
}

// MARK: - Preview

#Preview("Empty State") {
    ExpenseTrackerView()
}

#Preview("With Expenses") {
    let vm = ExpenseViewModel()
    Expense.sampleExpenses.forEach { vm.addExpense($0) }
    return ExpenseTrackerView()
}
