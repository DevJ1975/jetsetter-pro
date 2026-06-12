// File: Features/IdentityVault/IdentityVaultView.swift
//
// Three integrations for trusted-traveler convenience:
//   1. Digital Driver's License — state picker + deep link to Apple Wallet
//      and the state's official mDL info page.
//   2. CLEAR — open the CLEAR app or sign up.
//   3. TSA PreCheck / Global Entry — deep link to the Trusted Traveler portal.

import SwiftUI

struct IdentityVaultView: View {

    @EnvironmentObject private var preferences: UserPreferences
    @State private var showStatePicker = false

    /// User's selected state. Defaults to Arizona (the first state to go live).
    /// Persisted between launches via UserDefaults.
    @State private var selectedState: DigitalIDState =
        DigitalIDStates.find(stateCode: UserDefaults.standard.string(forKey: "jetsetter_id_state") ?? "AZ")
        ?? DigitalIDStates.all.first!

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                digitalDriverLicenseCard
                clearCard
                trustedTravelerCard
            }
            .padding(16)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Identity & Trusted Traveler")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showStatePicker) {
            StatePickerSheet(selectedState: $selectedState)
        }
        .onChange(of: selectedState) { _, newValue in
            UserDefaults.standard.set(newValue.id, forKey: "jetsetter_id_state")
        }
    }

    // MARK: - Digital DL

    private var digitalDriverLicenseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("DIGITAL DRIVER'S LICENSE", icon: "person.text.rectangle.fill")

            VStack(spacing: 14) {
                // Hero banner
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#0066CC"), Color(hex: "#3B9EF0")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "person.text.rectangle.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple Wallet ID")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                        Text("Add your driver's license or state ID to Apple Wallet to breeze through TSA at supported airports.")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                }

                // State picker
                Button { showStatePicker = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("STATE")
                                .font(.system(size: 9, weight: .black))
                                .tracking(1.5)
                                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                            Text(selectedState.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                        }
                        Spacer()
                        if selectedState.isLive {
                            Text("LIVE")
                                .font(.system(size: 9, weight: .black))
                                .tracking(1.2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(JetsetterTheme.Colors.success.opacity(0.15))
                                .foregroundStyle(JetsetterTheme.Colors.success)
                                .clipShape(Capsule())
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption).bold()
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.systemFill))
                    )
                }
                .buttonStyle(.plain)

                // Action buttons
                VStack(spacing: 8) {
                    Button { openWallet() } label: {
                        actionRow(
                            icon: "wallet.pass.fill",
                            title: "Open Apple Wallet",
                            subtitle: "Add your ID from the Wallet app",
                            tint: .black,
                            iconTint: .white
                        )
                    }
                    .buttonStyle(.plain)

                    Button { open(selectedState.infoURL) } label: {
                        actionRow(
                            icon: "info.circle.fill",
                            title: "\(selectedState.name) Mobile ID info",
                            subtitle: selectedState.issuerName,
                            tint: Color(.systemFill),
                            iconTint: JetsetterTheme.Colors.accent
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Note
                Label("ID issuance happens through your state DMV. Apple Wallet then receives the pass.", systemImage: "lightbulb.fill")
                    .font(.caption2)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .padding(.top, 2)
            }
            .padding(16)
            .jetCard()
        }
    }

    // MARK: - CLEAR

    private var clearCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("CLEAR", icon: "checkmark.shield.fill")

            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#003C71"), Color(hex: "#006FBA")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("CLEAR Plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                        Text("Skip the security line at 100+ US airports with biometric verification.")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                }

                VStack(spacing: 8) {
                    Button { openCLEARApp() } label: {
                        actionRow(
                            icon: "iphone",
                            title: "Open CLEAR app",
                            subtitle: "Verify your identity",
                            tint: Color(hex: "#003C71"),
                            iconTint: .white
                        )
                    }
                    .buttonStyle(.plain)

                    Button { open(URL(string: "https://www.clearme.com/")!) } label: {
                        actionRow(
                            icon: "person.crop.circle.badge.plus",
                            title: "Enroll in CLEAR Plus",
                            subtitle: "$199/year, free 2-month trial",
                            tint: Color(.systemFill),
                            iconTint: JetsetterTheme.Colors.accent
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .jetCard()
        }
    }

    // MARK: - Trusted Traveler

    private var trustedTravelerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("TSA PRECHECK & GLOBAL ENTRY", icon: "airplane.circle.fill")

            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#1A2E40"), Color(hex: "#3B5A7A")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "airplane.circle.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Trusted Traveler Programs")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                        Text("TSA PreCheck for US screening. Global Entry adds expedited customs.")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                }

                VStack(spacing: 8) {
                    Button { open(URL(string: "https://ttp.cbp.dhs.gov/")!) } label: {
                        actionRow(
                            icon: "globe.americas.fill",
                            title: "Apply / renew",
                            subtitle: "Trusted Traveler Programs (CBP)",
                            tint: Color(.systemFill),
                            iconTint: JetsetterTheme.Colors.accent
                        )
                    }
                    .buttonStyle(.plain)

                    Button { open(URL(string: "https://universalenroll.dhs.gov/programs/tsa-precheck")!) } label: {
                        actionRow(
                            icon: "person.fill.badge.plus",
                            title: "Schedule TSA PreCheck enrollment",
                            subtitle: "Universal Enroll Center",
                            tint: Color(.systemFill),
                            iconTint: JetsetterTheme.Colors.accent
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .jetCard()
        }
    }

    // MARK: - Reusable bits

    private func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption).bold()
            Text(title)
                .font(JetsetterTheme.Typography.label)
                .tracking(1.5)
        }
        .foregroundStyle(JetsetterTheme.Colors.accent)
        .padding(.leading, 4)
    }

    private func actionRow(icon: String, title: String, subtitle: String, tint: Color, iconTint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconTint == .white ? Color.white.opacity(0.18) : iconTint.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint == .white ? .white : JetsetterTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(iconTint == .white ? .white.opacity(0.7) : JetsetterTheme.Colors.textSecondary)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption).bold()
                .foregroundStyle(iconTint == .white ? .white.opacity(0.7) : JetsetterTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint)
        )
    }

    // MARK: - URL helpers

    private func openWallet() {
        // shoebox:// is Apple Wallet's private URL scheme. Falls back to App
        // Store URL if Wallet is somehow not available (it always is on iOS).
        if let url = URL(string: "shoebox://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func openCLEARApp() {
        // CLEAR's app scheme; falls back to the App Store if not installed.
        if let url = URL(string: "clearme://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let store = URL(string: "https://apps.apple.com/app/clear-fast-airport-lines/id1436511754") {
            UIApplication.shared.open(store)
        }
    }

    private func open(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

// MARK: - State picker sheet

private struct StatePickerSheet: View {

    @Binding var selectedState: DigitalIDState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Live in Apple Wallet") {
                    ForEach(DigitalIDStates.all.filter { $0.isLive }) { state in
                        Button {
                            selectedState = state
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(state.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(state.issuerName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if state.id == selectedState.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(JetsetterTheme.Colors.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select State")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        IdentityVaultView()
            .environmentObject(UserPreferences.shared)
    }
}
