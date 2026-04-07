// File: UI/Components/ComingSoonView.swift

import SwiftUI

// MARK: - ComingSoonView

/// Reusable placeholder shown for features that are not yet built.
/// Replaced with the real feature view once that phase is complete.
struct ComingSoonView: View {

    let featureName: String
    let icon: String
    let description: String

    var body: some View {
        VStack(spacing: JetsetterTheme.Spacing.large) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.5))

            VStack(spacing: JetsetterTheme.Spacing.small) {
                Text(featureName)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(description)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JetsetterTheme.Spacing.xlarge)
            }

            Text("Coming Soon")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, JetsetterTheme.Spacing.medium)
                .padding(.vertical, JetsetterTheme.Spacing.small)
                .background(JetsetterTheme.Colors.accent.opacity(0.12))
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .cornerRadius(20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(featureName)
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        ComingSoonView(
            featureName: "Example Feature",
            icon: "star.fill",
            description: "This feature is currently under development."
        )
    }
}
