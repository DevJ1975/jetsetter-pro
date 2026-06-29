// File: Features/IRIS/IRISConfirmationCard.swift
//
// The confirm-before-commit surface. When an IRIS write tool stages an
// `IRISPendingAction`, this card appears above the input bar so the user is
// always the one who triggers a data change. Confirm runs the action's commit
// closure; Cancel discards it.

import SwiftUI

struct IRISConfirmationCard: View {

    let action: IRISPendingAction
    var isCommitting: Bool
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                Text("Confirm")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }

            Text(action.summary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .foregroundStyle(.white.opacity(0.85))
                }
                .disabled(isCommitting)

                Button(action: onConfirm) {
                    ZStack {
                        if isCommitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(confirmLabel)
                                .font(.subheadline.weight(.bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(JetsetterTheme.Colors.accent)
                    )
                    .foregroundStyle(.white)
                }
                .disabled(isCommitting)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(JetsetterTheme.Colors.accent.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Per-kind affordances

    private var icon: String {
        switch action.kind {
        case .logExpense:          return "dollarsign.circle.fill"
        case .checkIn:             return "checkmark.seal.fill"
        case .addTrip:             return "suitcase.fill"
        case .trackFlight:         return "airplane"
        case .generatePackingList: return "checklist"
        case .submitExpenses:      return "paperplane.fill"
        }
    }

    private var confirmLabel: String {
        switch action.kind {
        case .logExpense:          return "Log it"
        case .checkIn:             return "Check in"
        case .addTrip:             return "Add trip"
        case .trackFlight:         return "Track"
        case .generatePackingList: return "Generate"
        case .submitExpenses:      return "Submit"
        }
    }
}
