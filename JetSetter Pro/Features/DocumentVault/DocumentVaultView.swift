// File: Features/DocumentVault/DocumentVaultView.swift
// Secure Travel Document Vault — Face ID / Touch ID gated, encrypted storage (Feature 4).
// Scaffolded UI — full implementation in Feature 4 sprint.

import SwiftUI
import PhotosUI

struct DocumentVaultView: View {

    @State private var vm = DocumentVaultViewModel()
    @Environment(SubscriptionManager.self) private var subscriptions
    @State private var showEmergencyMode = false
    @State private var showAddDocument = false

    var body: some View {
        NavigationStack {
            Group {
                if !vm.isAuthenticated {
                    authGateView
                } else if vm.isLoading {
                    loadingView
                } else {
                    vaultContent
                }
            }
            .navigationTitle("Document Vault")
            .navigationBarTitleDisplayMode(.large)
            .background(JetsetterTheme.Colors.background)
            .toolbar { if vm.isAuthenticated { toolbarContent } }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
            .sheet(isPresented: $showEmergencyMode) {
                EmergencyModeView(documents: vm.documents, numbers: vm.decryptedNumbers)
            }
            .sheet(isPresented: $showAddDocument) {
                AddDocumentSheet(vm: vm)
            }
        }
        .premiumGate(feature: "Document Vault")
    }

    // MARK: - Auth Gate

    private var authGateView: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(JetsetterTheme.Colors.accent.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "faceid")
                    .font(.system(size: 48))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }

            VStack(spacing: 8) {
                Text("Document Vault")
                    .font(JetsetterTheme.Typography.pageTitle)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text("Authenticate with Face ID or Touch ID to access your encrypted travel documents.")
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button { Task { await vm.authenticate() } } label: {
                Label("Unlock Vault", systemImage: "lock.open.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: 240)
                    .padding(.vertical, 14)
                    .background(JetsetterTheme.Colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button { showEmergencyMode = true } label: {
                Label("Emergency Mode", systemImage: "sos")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.danger)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        ProgressView().tint(JetsetterTheme.Colors.accent).scaleEffect(1.4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Vault Content

    private var vaultContent: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                // Advisory only — shown when the OS looks jailbroken/compromised,
                // where the Keychain + AES-at-rest guarantees are weaker. Never
                // blocks access (DeviceIntegrity heuristics can false-positive).
                if DeviceIntegrity.isCompromised {
                    securityAdvisoryBanner
                }

                // Emergency access banner
                emergencyBanner

                if vm.documents.isEmpty {
                    emptyVaultView
                } else {
                    ForEach(vm.documents) { doc in
                        DocumentCard(doc: doc)
                    }
                }
            }
            .padding(16)
        }
    }

    private var emergencyBanner: some View {
        Button { showEmergencyMode = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sos")
                    .font(.title3)
                    .foregroundStyle(JetsetterTheme.Colors.danger)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Emergency Mode")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text("Quickly access critical info offline")
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold())
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            .padding(14)
            .background(JetsetterTheme.Colors.danger.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(JetsetterTheme.Colors.danger.opacity(0.25), lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Non-blocking warning surfaced when the device appears compromised.
    private var securityAdvisoryBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title3)
                .foregroundStyle(JetsetterTheme.Colors.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("Device security warning")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text("This device appears to be jailbroken. Your encrypted documents are less protected here — avoid storing sensitive originals.")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(JetsetterTheme.Colors.warning.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(JetsetterTheme.Colors.warning.opacity(0.25), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyVaultView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill").font(.system(size: 44))
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            Text("No documents yet.\nTap + to add your passport, visa, or insurance.")
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .jetCard()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showAddDocument = true } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }
        }
    }
}

// MARK: - DocumentCard

private struct DocumentCard: View {
    let doc: VaultDocument

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: doc.documentType.colorHex).opacity(0.12))
                    .frame(width: 50, height: 50)
                Image(systemName: doc.documentType.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: doc.documentType.colorHex))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.documentType.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                if let country = doc.issuingCountry {
                    Text("Issued by: \(country)")
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
            Spacer()
            if let days = doc.daysUntilExpiry {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(days < 0 ? "EXPIRED" : "\(days)d")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(expiryColor(doc.expiryUrgency))
                    Text(days < 0 ? "" : "left")
                        .font(.caption2)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
        }
        .padding(14)
        .jetCard()
    }

    private func expiryColor(_ urgency: VaultDocument.ExpiryUrgency) -> Color {
        switch urgency {
        case .critical, .expired: return JetsetterTheme.Colors.danger
        case .warning:            return JetsetterTheme.Colors.warning
        case .notice:             return JetsetterTheme.Colors.accent
        case .safe:               return JetsetterTheme.Colors.success
        }
    }
}

// MARK: - EmergencyModeView

struct EmergencyModeView: View {

    let documents: [VaultDocument]
    /// Decrypted document numbers keyed by document id. `docNumberClear` is
    /// nil'd before persistence, so after a relaunch we must read the number
    /// from this in-session decrypted map instead of the document itself.
    let numbers: [UUID: String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Passport
                    if let passport = documents.first(where: { $0.documentType == .passport }) {
                        emergencyCard("Passport", icon: "person.text.rectangle.fill",
                                      colorHex: "#0055CC") {
                            if let country = passport.issuingCountry {
                                Text("Issuing Country: \(country)").font(.subheadline)
                            }
                            if let num = numbers[passport.id] ?? passport.docNumberClear {
                                Text("Number: \(num)").font(.system(.subheadline, design: .monospaced))
                            }
                            if let expiry = passport.expiryDate {
                                Text("Expires: \(expiry.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline)
                            }
                        }
                    }

                    // Insurance
                    if let insurance = documents.first(where: { $0.documentType == .travelInsurance }) {
                        emergencyCard("Travel Insurance", icon: "shield.fill", colorHex: "#CC3B1E") {
                            if let notes = insurance.notes { Text(notes).font(.subheadline) }
                        }
                    }

                    // Emergency Contacts
                    if let contacts = documents.first(where: { $0.documentType == .emergencyContact }) {
                        emergencyCard("Emergency Contacts", icon: "phone.fill", colorHex: "#E84040") {
                            if let notes = contacts.notes { Text(notes).font(.subheadline) }
                        }
                    }
                }
                .padding(16)
            }
            .background(JetsetterTheme.Colors.background)
            .navigationTitle("Emergency Mode")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func emergencyCard<Content: View>(
        _ title: String,
        icon: String,
        colorHex: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(Color(hex: colorHex))
                Text(title).font(.headline).foregroundStyle(JetsetterTheme.Colors.textPrimary)
            }
            content()
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .jetCard()
    }
}

// MARK: - AddDocumentSheet

/// Real entry form for adding a document to the vault. The user picks a type
/// and enters their own details (number, issuing country, expiry, notes, and an
/// optional photo) rather than accepting canned mock data. All `DocumentType`
/// cases are offered so emergency contacts, driver's licenses, and Global Entry
/// entries can be created. The clear-text number is handed to the view model,
/// which encrypts it at rest via `DocumentVaultStore`.
private struct AddDocumentSheet: View {

    @Bindable var vm: DocumentVaultViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var documentType: DocumentType = .passport
    @State private var docNumber: String = ""
    @State private var issuingCountry: String = ""
    @State private var hasExpiry: Bool = true
    @State private var expiryDate: Date = Date().addingTimeInterval(86_400 * 365)
    @State private var notes: String = ""

    // Optional photo of the physical document.
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var photoData: Data? = nil
    @State private var isSaving = false

    /// A number field is meaningful for most document types but not for a plain
    /// emergency-contact card, whose useful content is the notes field.
    private var showsNumberField: Bool {
        documentType != .emergencyContact
    }

    /// Emergency contacts, insurance, and vaccination records are the types
    /// where free-form notes carry the primary value, so surface a clearer label.
    private var notesPrompt: String {
        switch documentType {
        case .emergencyContact: return "Name and phone number"
        case .travelInsurance:  return "Provider, policy details, hotline"
        default:                return "Add a note…"
        }
    }

    private var canSave: Bool {
        if showsNumberField {
            return !docNumber.trimmingCharacters(in: .whitespaces).isEmpty
        }
        // Emergency contacts are saveable once notes carry the contact details.
        return !notes.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Document Type", selection: $documentType) {
                        ForEach(DocumentType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                }

                if showsNumberField {
                    Section("Document Number") {
                        TextField("e.g. X12345678", text: $docNumber)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                    }

                    Section("Issuing Country (optional)") {
                        TextField("e.g. United States", text: $issuingCountry)
                    }
                }

                Section("Expiry") {
                    Toggle("Has an expiry date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker(
                            "Expires",
                            selection: $expiryDate,
                            displayedComponents: .date
                        )
                    }
                }

                Section("Notes\(showsNumberField ? " (optional)" : "")") {
                    TextField(notesPrompt, text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("Photo (optional)") {
                    if let photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(.rect(cornerRadius: 10))
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images
                    ) {
                        Label(
                            photoData == nil ? "Add Photo" : "Replace Photo",
                            systemImage: "photo.on.rectangle"
                        )
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                    if photoData != nil {
                        Button(role: .destructive) {
                            photoData = nil
                            selectedPhotoItem = nil
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                        }
                    }
                }
            }
            .background(JetsetterTheme.Colors.background)
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave || isSaving)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    guard let newItem,
                          let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                    photoData = data
                }
            }
        }
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true

        let trimmedNumber = docNumber.trimmingCharacters(in: .whitespaces)
        let trimmedCountry = issuingCountry.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        let document = VaultDocument(
            id: UUID(),
            documentType: documentType,
            issuingCountry: trimmedCountry.isEmpty ? nil : trimmedCountry,
            docNumberEncrypted: nil,
            docNumberClear: (showsNumberField && !trimmedNumber.isEmpty) ? trimmedNumber : nil,
            expiryDate: hasExpiry ? expiryDate : nil,
            photoUrl: nil,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            createdAt: Date()
        )
        Task {
            await vm.addDocument(document, photo: photoData)
            dismiss()
        }
    }
}

#Preview {
    DocumentVaultView()
        .environment(SubscriptionManager.shared)
}
