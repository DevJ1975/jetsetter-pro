// File: Features/ExpenseExport/ExpenseConnectionsView.swift
//
// Settings hub for connecting/disconnecting expense export providers. Lives
// under Settings or Premium-gated under MoreView.

import SwiftUI

struct ExpenseConnectionsView: View {

    @State private var connectionStates: [String: Bool] = [:]
    @State private var showExpensifyAuth: Bool = false
    @State private var pendingOAuthProvider: (any ExpenseExportProvider)?
    @State private var oauthInFlight: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                ForEach(ExpenseExportRegistry.allProviders, id: \.id) { provider in
                    providerCard(provider)
                }
                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Expense Connections")
        .navigationBarTitleDisplayMode(.large)
        .task { await refreshConnectionStates() }
        .sheet(isPresented: $showExpensifyAuth) {
            ExpensifyAuthSheet { saved in
                Task { await refreshConnectionStates() }
            }
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link.circle.fill").font(.caption.bold())
                Text("CONNECTED ACCOUNTS")
                    .font(JetsetterTheme.Typography.label).tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            Text("Link the platforms where you submit business expenses. Credentials are stored only in your iPhone's Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func providerCard(_ provider: any ExpenseExportProvider) -> some View {
        let connected = connectionStates[provider.id] ?? false
        return HStack(spacing: 12) {
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
                Text(provider.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if connected {
                    Label("Connected", systemImage: "checkmark.seal.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(JetsetterTheme.Colors.success)
                }
            }
            Spacer()
            if provider.authKind == .none {
                Text("Always available")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if connected {
                Button("Disconnect", role: .destructive) {
                    Task {
                        await provider.disconnect()
                        await refreshConnectionStates()
                    }
                }
                .font(.caption.bold())
            } else {
                Button("Connect") {
                    Task { await connect(provider) }
                }
                .font(.caption.bold())
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .disabled(oauthInFlight)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    // MARK: - Connect routing

    private func connect(_ provider: any ExpenseExportProvider) async {
        errorMessage = nil
        switch provider.authKind {
        case .none:
            return
        case .apiKey:
            if provider.id == "expensify" {
                showExpensifyAuth = true
            }
        case .oauth2:
            oauthInFlight = true
            defer { oauthInFlight = false }
            do {
                _ = try await provider.connect()
                await refreshConnectionStates()
            } catch ExpenseExportError.userCancelled {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshConnectionStates() async {
        var map: [String: Bool] = [:]
        for provider in ExpenseExportRegistry.allProviders {
            map[provider.id] = await provider.isConnected()
        }
        connectionStates = map
    }
}

// MARK: - Expensify auth sheet

struct ExpensifyAuthSheet: View {

    let onSaved: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var partnerUserID: String = ""
    @State private var partnerUserSecret: String = ""
    @State private var userEmail: String = ""
    @State private var saveError: String?

    private var canSave: Bool {
        !partnerUserID.isEmpty && !partnerUserSecret.isEmpty && userEmail.contains("@")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Create a partner user pair at expensify.com → Settings → Integration Server. Then enter the values below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Account") {
                    TextField("Your Expensify email", text: $userEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Integration credentials") {
                    TextField("Partner User ID", text: $partnerUserID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Partner User Secret", text: $partnerUserSecret)
                }
                if let saveError = saveError {
                    Section {
                        Text(saveError).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Connect Expensify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try ExpensifyProvider.shared.saveCredentials(
                                partnerUserID: partnerUserID,
                                partnerUserSecret: partnerUserSecret,
                                userEmail: userEmail
                            )
                            onSaved(true)
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
