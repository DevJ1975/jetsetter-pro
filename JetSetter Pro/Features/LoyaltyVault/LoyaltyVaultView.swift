// File: Features/LoyaltyVault/LoyaltyVaultView.swift

import SwiftUI

struct LoyaltyVaultView: View {

    @State private var vm = LoyaltyViewModel()
    @State private var showingEditor = false
    @State private var editingAccount: LoyaltyAccount?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard
                if vm.accounts.isEmpty {
                    emptyState
                } else {
                    ForEach(vm.groupedAccounts, id: \.kind) { group in
                        section(for: group.kind, accounts: group.accounts)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Miles & Loyalty")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingAccount = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            LoyaltyAccountEditor(
                existing: editingAccount,
                onSave: { vm.addOrUpdate($0) },
                onDelete: { editingAccount.map { vm.delete($0.id) } }
            )
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        HStack(spacing: 16) {
            summaryColumn(
                value: numberFormatted(vm.totalAirlineMiles),
                label: "TOTAL MILES",
                icon: "airplane",
                tint: JetsetterTheme.Colors.accent
            )
            Divider().frame(height: 50)
            summaryColumn(
                value: numberFormatted(vm.totalHotelPoints),
                label: "TOTAL POINTS",
                icon: "bed.double.fill",
                tint: JetsetterTheme.Colors.success
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    private func summaryColumn(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.caption.bold())
                Text(label)
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            // Animated count-up — `value` is the formatted target; we extract
            // the raw integer for the counter.
            let target = Int(value.filter(\.isNumber)) ?? 0
            AnimatedCounter(target: target, duration: 1.4)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    private func section(for kind: LoyaltyKind, accounts: [LoyaltyAccount]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                    .font(.caption.bold())
                Text(kind.displayName.uppercased())
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            .padding(.leading, 4)

            VStack(spacing: 1) {
                ForEach(accounts) { account in
                    accountRow(account)
                }
            }
            .jetCard()
        }
    }

    private func accountRow(_ account: LoyaltyAccount) -> some View {
        let program = LoyaltyProgramCatalog.find(id: account.programID)
        let brand = Color(hex: program?.brandHex ?? "#666666")

        return Button {
            editingAccount = account
            showingEditor = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(brand)
                        .frame(width: 44, height: 44)
                    Text(program?.id.prefix(2) ?? "—")
                        .font(.system(.caption, design: .monospaced).weight(.black))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(program?.name ?? "Unknown")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    HStack(spacing: 6) {
                        if !account.tier.isEmpty {
                            Text(account.tier.uppercased())
                                .font(.system(size: 9, weight: .black))
                                .tracking(1.2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(brand.opacity(0.15))
                                .foregroundStyle(brand)
                                .clipShape(Capsule())
                        }
                        Text("#\(account.memberNumber)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(numberFormatted(account.balance))
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    if let expiry = account.tierExpiration {
                        Text("Tier exp \(expiry, format: .dateTime.month().year())")
                            .font(.system(size: 9))
                            .foregroundStyle(expiry < Date().addingTimeInterval(90 * 86400)
                                             ? .orange
                                             : JetsetterTheme.Colors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))
            Text("No loyalty accounts yet")
                .font(.headline)
            Text("Track your airline miles, hotel points and rental car perks in one place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                editingAccount = nil
                showingEditor = true
            } label: {
                Label("Add Account", systemImage: "plus")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(JetsetterTheme.Colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    // MARK: - Helpers

    private func numberFormatted(_ n: Int) -> String {
        n.formatted(.number)
    }
}

// MARK: - Editor sheet

private struct LoyaltyAccountEditor: View {

    let existing: LoyaltyAccount?
    let onSave: (LoyaltyAccount) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var programID: String
    @State private var memberNumber: String
    @State private var balance: String
    @State private var tier: String
    @State private var hasTierExpiry: Bool
    @State private var tierExpiry: Date
    @State private var notes: String

    init(existing: LoyaltyAccount?, onSave: @escaping (LoyaltyAccount) -> Void, onDelete: @escaping () -> Void) {
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete
        _programID    = State(initialValue: existing?.programID ?? LoyaltyProgramCatalog.all.first!.id)
        _memberNumber = State(initialValue: existing?.memberNumber ?? "")
        _balance      = State(initialValue: existing.map { String($0.balance) } ?? "")
        _tier         = State(initialValue: existing?.tier ?? "")
        _hasTierExpiry = State(initialValue: existing?.tierExpiration != nil)
        _tierExpiry   = State(initialValue: existing?.tierExpiration ?? Date().addingTimeInterval(365 * 86400))
        _notes        = State(initialValue: existing?.notes ?? "")
    }

    private var canSave: Bool {
        !memberNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Program") {
                    Picker("Program", selection: $programID) {
                        ForEach(LoyaltyProgramCatalog.all) { program in
                            Text(program.name).tag(program.id)
                        }
                    }
                }
                Section("Member Details") {
                    TextField("Member number", text: $memberNumber)
                        .textInputAutocapitalization(.never)
                    TextField("Balance (miles or points)", text: $balance)
                        .keyboardType(.numberPad)
                }
                Section("Status Tier") {
                    TextField("Tier (Silver, Gold, etc.)", text: $tier)
                        .textInputAutocapitalization(.words)
                    Toggle("Has expiration date", isOn: $hasTierExpiry)
                    if hasTierExpiry {
                        DatePicker("Tier expires", selection: $tierExpiry, displayedComponents: .date)
                    }
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Delete account", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let account = LoyaltyAccount(
                            id: existing?.id ?? UUID(),
                            programID: programID,
                            memberNumber: memberNumber.trimmingCharacters(in: .whitespaces),
                            memberSince: existing?.memberSince,
                            balance: Int(balance) ?? 0,
                            tier: tier.trimmingCharacters(in: .whitespaces),
                            tierExpiration: hasTierExpiry ? tierExpiry : nil,
                            notes: notes.isEmpty ? nil : notes
                        )
                        onSave(account)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LoyaltyVaultView()
    }
}
