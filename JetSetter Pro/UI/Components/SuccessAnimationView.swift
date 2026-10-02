// File: UI/Components/SuccessAnimationView.swift
//
// Reusable success animation overlay. Drop into a `.sheet` or `.fullScreenCover`
// for any user action that "succeeded" — adding to wallet, booking a ride,
// confirming an expense, etc.
//
//   SuccessAnimationView(
//       title: "Added to Apple Wallet",
//       subtitle: "Open Wallet to see your boarding pass",
//       referenceNumber: nil
//   )
//
// Features:
//   • dark blurred background
//   • springy green circle with path-drawn checkmark (~0.6s)
//   • 10 confetti particles fading up (~1.2s)
//   • title / subtitle / optional monospaced reference number
//   • auto-dismisses after 2.5s OR on tap
//
// Accessibility:
//   • Reduce Motion: the badge, checkmark and text appear in their final state
//     and there is no confetti.
//   • VoiceOver hears one element ("Rebooked on DL402. Confirmation sent…")
//     with a Close action. It doesn't auto-dismiss while VoiceOver is running:
//     2.5 s is too short to hear the reference number, and a timed dismissal
//     fails WCAG 2.2.1.

import SwiftUI

struct SuccessAnimationView: View {

    // MARK: - Inputs

    let title: String
    let subtitle: String
    let referenceNumber: String?
    var onDismiss: (() -> Void)? = nil

    // MARK: - Animation State

    @State private var circleScale: CGFloat = 0.2
    @State private var checkmarkTrim: CGFloat = 0
    @State private var textOpacity: Double = 0
    @State private var confettiStart: Date? = nil
    @State private var didAutoDismiss = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 96

    // MARK: - Confetti Particles (stable per appearance)

    private let confetti: [ConfettiParticle] = (0..<10).map { _ in ConfettiParticle.random() }

    var body: some View {
        ZStack {
            // Dim + blur backdrop
            Color.black.opacity(0.55)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            // Confetti layer (none with Reduce Motion)
            if !reduceMotion {
                TimelineView(.animation) { context in
                    let elapsed = elapsedTime(at: context.date)
                    Canvas { ctx, size in
                        drawConfetti(in: ctx, size: size, elapsed: elapsed)
                    }
                    .allowsHitTesting(false)
                }
                .accessibilityHidden(true)
            }

            // Card
            VStack(spacing: 18) {
                checkmarkBadge
                    .padding(.top, 4)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(.title2, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)

                    if let referenceNumber, !referenceNumber.isEmpty {
                        Text(referenceNumber)
                            .speechSpellsOutCharacters()
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .padding(.top, 4)
                    }
                }
                .opacity(textOpacity)
            }
            .padding(.horizontal, 32)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isModal)
            .accessibilityHint("Double-tap to close")
            .accessibilityAction { triggerDismiss() }
            .accessibilityAction(named: Text("Close")) { triggerDismiss() }
        }
        .contentShape(Rectangle())
        .onTapGesture { triggerDismiss() }
        .onAppear { startAnimations() }
    }

    // MARK: - Checkmark Badge

    private var checkmarkBadge: some View {
        ZStack {
            Circle()
                .fill(Color.green)
                .frame(width: badgeSize, height: badgeSize)
                .shadow(color: Color.green.opacity(0.45), radius: 20, y: 6)

            CheckmarkPath()
                .trim(from: 0, to: checkmarkTrim)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
                .frame(width: badgeSize / 2, height: badgeSize * 0.375)
        }
        .scaleEffect(circleScale)
        .accessibilityHidden(true)
    }

    // MARK: - Animation Lifecycle

    private func startAnimations() {
        if reduceMotion {
            // Final state straight away: no pop, no draw, no fade, no confetti.
            circleScale = 1.0
            checkmarkTrim = 1.0
            textOpacity = 1.0
        } else {
            animateIn()
        }

        // Auto-dismiss after 2.5s, except under VoiceOver (see the file note):
        // there the traveler closes it with a double-tap once it's been read.
        guard !voiceOverEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            triggerDismiss()
        }
    }

    private func animateIn() {
        confettiStart = Date()

        // Pop the circle in with a spring
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
            circleScale = 1.0
        }

        // Draw the checkmark path
        withAnimation(.easeOut(duration: 0.35).delay(0.18)) {
            checkmarkTrim = 1.0
        }

        // Fade the text in
        withAnimation(.easeOut(duration: 0.4).delay(0.35)) {
            textOpacity = 1.0
        }
    }

    private func triggerDismiss() {
        guard !didAutoDismiss else { return }
        didAutoDismiss = true
        onDismiss?()
    }

    // MARK: - Confetti Rendering

    private func elapsedTime(at date: Date) -> Double {
        guard let start = confettiStart else { return 0 }
        return date.timeIntervalSince(start)
    }

    private func drawConfetti(in context: GraphicsContext, size: CGSize, elapsed: Double) {
        let duration = 1.2
        let progress = min(max(elapsed / duration, 0), 1)
        guard progress > 0 else { return }
        let eased = 1 - pow(1 - progress, 2)

        for particle in confetti {
            let startX = size.width * 0.5 + particle.horizontalOffset
            let startY = size.height * 0.5 + 40
            let endY = startY - (140 + particle.verticalDrift)
            let y = startY + (endY - startY) * eased
            let x = startX + sin(eased * .pi * 2 * particle.wobbleFrequency) * particle.wobbleAmplitude
            let rotation = Angle.degrees(eased * particle.rotationSpeed)
            let alpha = 1.0 - progress

            var path = Path()
            let rect = CGRect(x: -particle.size.width / 2, y: -particle.size.height / 2,
                              width: particle.size.width, height: particle.size.height)
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1.5, height: 1.5))

            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: x, y: y)
            transform = transform.rotated(by: rotation.radians)

            context.drawLayer { layer in
                layer.opacity = alpha
                layer.fill(path.applying(transform), with: .color(particle.color))
            }
        }
    }
}

// MARK: - Checkmark Path

private struct CheckmarkPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05)
        let middle = CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY)
        let end = CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.05)
        path.move(to: start)
        path.addLine(to: middle)
        path.addLine(to: end)
        return path
    }
}

// MARK: - Confetti Particle

private struct ConfettiParticle {
    let color: Color
    let size: CGSize
    let horizontalOffset: CGFloat
    let verticalDrift: CGFloat
    let wobbleFrequency: Double
    let wobbleAmplitude: CGFloat
    let rotationSpeed: Double

    static func random() -> ConfettiParticle {
        let palette: [Color] = [
            .green, .yellow, .orange, .pink, .blue, .purple, .mint, .teal
        ]
        return ConfettiParticle(
            color: palette.randomElement() ?? .green,
            size: CGSize(
                width: CGFloat.random(in: 5...8),
                height: CGFloat.random(in: 9...14)
            ),
            horizontalOffset: CGFloat.random(in: -120...120),
            verticalDrift: CGFloat.random(in: 0...80),
            wobbleFrequency: Double.random(in: 0.6...1.4),
            wobbleAmplitude: CGFloat.random(in: 8...28),
            rotationSpeed: Double.random(in: 180...540)
        )
    }
}

// MARK: - Preview

#Preview("With Reference Number") {
    SuccessAnimationView(
        title: "Ride Booked",
        subtitle: "Marcus is on his way",
        referenceNumber: "GHI-4421"
    )
}

#Preview("Without Reference") {
    SuccessAnimationView(
        title: "Added to Apple Wallet",
        subtitle: "Open Wallet to see your boarding pass",
        referenceNumber: nil
    )
}
