// File: Features/Settings/LovedOnesSettingsView.swift
//
// Editor for the traveler's "loved ones" — the people IRIS offers to text on
// takeoff and landing. Add via the system Contacts picker or by hand, toggle
// which milestones each person hears about, and remove with a swipe.

import SwiftUI
import ContactsUI

struct LovedOnesSettingsView: View {

    @State private var store = LovedOnesStore.shared

    @State private var showContactPicker = false
    @State private var manualName = ""
    @State private var manualNumber = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                addCard
                if store.isEmpty {
                    emptyState
                } else {
                    contactsList
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Loved Ones")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showContactPicker) {
            ContactPicker { name, number in
                store.add(name: name, phoneNumber: number)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Add

    private var addCard: some View {
        VStack(spacing: 12) {
            Button {
                showContactPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Add from Contacts")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(JetsetterTheme.Colors.accent.opacity(0.12))
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .frame(width: 20)
                TextField("Name", text: $manualName)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            }
            .premiumInput()

            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .frame(width: 20)
                TextField("Phone number", text: $manualNumber)
                    .keyboardType(.phonePad)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            }
            .premiumInput()

            Button {
                addManualContact()
            } label: {
                Text("Add Contact")
                    .font(.subheadline).bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(JetsetterTheme.Colors.accent)
                    .foregroundStyle(Color(hex: "#0A0A10"))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(!canAddManualContact)
        }
        .padding(16)
        .jetCard()
    }

    /// True once the name is non-empty and the phone field holds a plausible
    /// dial-able number (at least 7 digits — the shortest real subscriber
    /// number). Guards against "555", names typed into the number field, etc.
    private var canAddManualContact: Bool {
        !manualName.trimmingCharacters(in: .whitespaces).isEmpty
        && Self.dialDigits(manualNumber).count >= 7
    }

    /// Validates, then adds the manual contact — skipping if an existing
    /// contact already has the same normalized number so nobody gets texted
    /// twice on takeoff/landing.
    private func addManualContact() {
        guard canAddManualContact else { return }
        let normalized = Self.dialDigits(manualNumber)
        let isDuplicate = store.contacts.contains { Self.dialDigits($0.phoneNumber) == normalized }
        if !isDuplicate {
            store.add(name: manualName, phoneNumber: manualNumber)
        }
        manualName = ""
        manualNumber = ""
    }

    /// Reduces a phone string to its dialable digits (keeping a single leading
    /// "+" for country codes) so two spellings of the same number compare equal.
    private static func dialDigits(_ raw: String) -> String {
        let hasPlus = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        let digits = raw.filter(\.isNumber)
        return hasPlus ? "+" + digits : digits
    }

    // MARK: - List

    private var contactsList: some View {
        VStack(spacing: 12) {
            ForEach(store.contacts) { contact in
                contactRow(contact)
            }
        }
    }

    private func contactRow(_ contact: LovedOne) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(.subheadline).bold()
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text(contact.phoneNumber)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
                Spacer()
                Button(role: .destructive) {
                    store.remove(contact)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(JetsetterTheme.Colors.danger)
                }
            }

            Divider().background(JetsetterTheme.Colors.separator)

            Toggle(isOn: binding(for: contact, keyPath: \.notifyOnTakeoff)) {
                Label("On takeoff", systemImage: "airplane.departure")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            .tint(JetsetterTheme.Colors.accent)

            Toggle(isOn: binding(for: contact, keyPath: \.notifyOnLanding)) {
                Label("On landing", systemImage: "airplane.arrival")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            .tint(JetsetterTheme.Colors.accent)
        }
        .padding(16)
        .jetCard()
    }

    /// Two-way binding that writes a single field of a stored contact back
    /// through the store so the change persists.
    private func binding(for contact: LovedOne,
                         keyPath: WritableKeyPath<LovedOne, Bool>) -> Binding<Bool> {
        Binding(
            get: { contact[keyPath: keyPath] },
            set: { newValue in
                var updated = contact
                updated[keyPath: keyPath] = newValue
                store.update(updated)
            }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.slash")
                .font(.largeTitle)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            Text("No contacts yet")
                .font(.subheadline).bold()
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            Text("Add the people you'd like IRIS to text when your flight takes off and lands.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .jetCard()
    }
}

// MARK: - Contacts picker bridge

/// Wraps the system contact picker. Runs out-of-process, so it needs no
/// Contacts permission prompt — the user explicitly picks one person.
private struct ContactPicker: UIViewControllerRepresentable {

    let onPick: (_ name: String, _ phoneNumber: String) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (_ name: String, _ phoneNumber: String) -> Void
        init(onPick: @escaping (_ name: String, _ phoneNumber: String) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController,
                           didSelect contactProperty: CNContactProperty) {
            let contact = contactProperty.contact
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "Contact"
            let number = (contactProperty.value as? CNPhoneNumber)?.stringValue ?? ""
            onPick(name, number)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "Contact"
            let number = contact.phoneNumbers.first?.value.stringValue ?? ""
            onPick(name, number)
        }
    }
}
