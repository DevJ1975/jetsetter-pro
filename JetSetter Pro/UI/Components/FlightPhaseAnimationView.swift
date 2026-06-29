// File: UI/Components/FlightPhaseAnimationView.swift
//
// A Canvas + TimelineView scene that animates the current FLIGHT PHASE —
// boarding at the gate, the takeoff roll, climb, cruise, descent, and landing.
// Driven off InFlightTrackingService.snapshot.phase (the on-device sensor-
// fusion state machine) or a phase derived from a tracked flight's status.
//
// Matches the 60fps Canvas idiom of FlightAnimationView.swift so the two feel
// like one family of components.

import SwiftUI

struct FlightPhaseAnimationView: View {

    let phase: FlightPhase
    var height: CGFloat = 180

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas { canvas, size in
                draw(&canvas, size: size, time: context.date.timeIntervalSince1970)
            } symbols: {
                planeSymbol
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [JetsetterTheme.Colors.accent.opacity(0.10), .clear],
                startPoint: .top, endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(alignment: .topLeading) { phaseBadge }
        .accessibilityLabel("Flight phase: \(phase.label)")
    }

    // MARK: - Phase label badge

    private var phaseBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: phase.systemImage)
            Text(phase.label)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(JetsetterTheme.Colors.accent.opacity(0.85),
                    in: Capsule())
        .padding(JetsetterTheme.Spacing.small)
    }

    // MARK: - Scene drawing

    private func draw(_ canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let onGround = isGroundPhase
        if onGround { drawRunway(&canvas, size: size) }
        else { drawClouds(&canvas, size: size, time: time) }

        let state = planeState(size: size, time: time)
        canvas.translateBy(x: state.point.x, y: state.point.y)
        canvas.rotate(by: .radians(state.angle))
        if let resolved = canvas.resolveSymbol(id: 1) {
            canvas.draw(resolved, at: .zero)
        }
    }

    private var planeSymbol: some View {
        Image(systemName: "airplane")
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: JetsetterTheme.Colors.accent.opacity(0.6), radius: 6)
            .tag(1)
    }

    // MARK: - Phase → plane position & angle

    private var isGroundPhase: Bool {
        switch phase {
        case .parked, .taxi, .takeoffRoll, .landing, .arrived: return true
        default: return false
        }
    }

    /// Returns the plane's screen position and rotation for the current phase.
    /// `angle` follows FlightAnimationView's convention: 0 = pointing right
    /// (screen x → right, y → down).
    private func planeState(size: CGSize, time: Double) -> (point: CGPoint, angle: Double) {
        let w = size.width, h = size.height
        let groundY = h - 34
        let loop = { (period: Double) in time.truncatingRemainder(dividingBy: period) / period }

        switch phase {
        case .parked, .arrived:
            // Idle at the gate with a gentle bob.
            let bob = sin(time * 1.4) * 2
            return (CGPoint(x: w * 0.30, y: groundY + bob), 0)

        case .taxi:
            // Crawl slowly across the apron.
            let p = loop(8)
            return (CGPoint(x: w * (0.18 + 0.5 * p), y: groundY), 0)

        case .takeoffRoll:
            // Accelerate down the runway, nose lifting at the end.
            let p = ease(loop(3.2))
            let x = w * (0.12 + 0.7 * p)
            let lift = p > 0.7 ? (p - 0.7) / 0.3 : 0
            return (CGPoint(x: x, y: groundY - lift * 18), -0.22 * lift)

        case .climb:
            // Travel up and to the right.
            let p = ease(loop(4.5))
            return (CGPoint(x: w * (0.12 + 0.7 * p), y: h * (0.85 - 0.6 * p)), -0.35)

        case .cruise:
            // Level near the top, drifting slightly for life.
            let drift = sin(time * 0.7) * (w * 0.04)
            return (CGPoint(x: w * 0.5 + drift, y: h * 0.3 + sin(time * 1.1) * 4), 0)

        case .descent:
            // Descend toward the right.
            let p = ease(loop(4.5))
            return (CGPoint(x: w * (0.2 + 0.65 * p), y: h * (0.28 + 0.5 * p)), 0.3)

        case .finalApproach:
            // Steeper, lower approach to the runway threshold.
            let p = ease(loop(4.0))
            return (CGPoint(x: w * (0.25 + 0.6 * p), y: h * (0.45 + 0.42 * p)), 0.28)

        case .landing:
            // Flare and roll out along the runway, nose slightly up.
            let p = ease(loop(3.5))
            return (CGPoint(x: w * (0.3 + 0.55 * p), y: groundY), -0.08)
        }
    }

    // MARK: - Decor

    private func drawRunway(_ canvas: inout GraphicsContext, size: CGSize) {
        let y = size.height - 24
        var ground = Path()
        ground.addRect(CGRect(x: 0, y: y, width: size.width, height: 24))
        canvas.fill(ground, with: .color(JetsetterTheme.Colors.accent.opacity(0.12)))

        // Dashed centerline.
        var line = Path()
        line.move(to: CGPoint(x: 12, y: y + 12))
        line.addLine(to: CGPoint(x: size.width - 12, y: y + 12))
        canvas.stroke(line,
                      with: .color(.white.opacity(0.4)),
                      style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [10, 12]))
    }

    private func drawClouds(_ canvas: inout GraphicsContext, size: CGSize, time: Double) {
        // A few slow-drifting clouds wrapping across the frame for depth.
        let seeds: [(y: CGFloat, scale: CGFloat, speed: Double)] = [
            (size.height * 0.22, 1.0, 18),
            (size.height * 0.55, 0.7, 26),
            (size.height * 0.75, 1.2, 34)
        ]
        for (i, s) in seeds.enumerated() {
            let period = s.speed
            let p = time.truncatingRemainder(dividingBy: period) / period
            // Drift right→left, wrapping with margin so they slide off-screen.
            let x = size.width * (1.1 - 1.3 * p) + CGFloat(i) * 30
            let wCloud = 46 * s.scale
            let hCloud = 18 * s.scale
            var cloud = Path()
            cloud.addEllipse(in: CGRect(x: x, y: s.y, width: wCloud, height: hCloud))
            cloud.addEllipse(in: CGRect(x: x + wCloud * 0.35, y: s.y - hCloud * 0.4,
                                        width: wCloud * 0.7, height: hCloud * 1.1))
            canvas.fill(cloud, with: .color(.white.opacity(0.10)))
        }
    }

    // MARK: - Math

    /// Smoothstep easing for natural acceleration/deceleration along a loop.
    private func ease(_ t: Double) -> Double {
        0.5 - cos(.pi * max(0, min(1, t))) / 2
    }
}

// MARK: - Preview

#Preview("Phases") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach([FlightPhase.parked, .taxi, .takeoffRoll, .climb,
                     .cruise, .descent, .finalApproach, .landing, .arrived], id: \.self) { phase in
                FlightPhaseAnimationView(phase: phase, height: 140)
            }
        }
        .padding()
    }
    .background(Color(white: 0.08))
}
