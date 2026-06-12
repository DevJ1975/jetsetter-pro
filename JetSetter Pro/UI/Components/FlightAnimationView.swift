// File: UI/Components/FlightAnimationView.swift
//
// Reusable SwiftUI scene that shows an airplane traveling along a curved route
// between two airport markers. Used on:
//   • Home next-flight card (compact)
//   • FlightDetailView hero header (hero)
//
// The route's progress can be driven by real flight time (departure → arrival)
// or set to nil for a continuous looping animation that acts as visual flair.

import SwiftUI

struct FlightAnimationView: View {

    let originIATA: String
    let destinationIATA: String

    /// 0.0 = at origin gate, 1.0 = at destination gate. When nil, the view
    /// runs a continuous decorative loop driven by TimelineView.
    var progress: Double? = nil

    /// True when the flight is in its final approach window. Pulses the
    /// destination marker.
    var isArriving: Bool = false

    /// True when boarding is closing imminently. Pulses the origin marker
    /// and shows a red "gate" badge.
    var isGateClosing: Bool = false

    var style: Style = .compact

    enum Style {
        case compact   // ~80pt tall — fits inside cards
        case hero      // ~140pt tall — for detail views

        var height: CGFloat {
            switch self {
            case .compact: return 80
            case .hero:    return 140
            }
        }

        var planeSize: CGFloat {
            switch self {
            case .compact: return 18
            case .hero:    return 28
            }
        }

        var iataFont: Font {
            switch self {
            case .compact: return .system(size: 14, weight: .bold, design: .monospaced)
            case .hero:    return .system(size: 22, weight: .bold, design: .monospaced)
            }
        }

        var markerSize: CGFloat {
            switch self {
            case .compact: return 10
            case .hero:    return 16
            }
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas { canvas, size in
                draw(canvas: &canvas, size: size, date: context.date)
            } symbols: {
                symbolLayer
            }
        }
        .frame(height: style.height)
        .accessibilityLabel("Flight from \(originIATA) to \(destinationIATA)")
    }

    // MARK: - Canvas drawing

    private func draw(canvas: inout GraphicsContext, size: CGSize, date: Date) {
        let padding: CGFloat = 36
        let startX = padding
        let endX = size.width - padding
        let midY = size.height / 2

        // Curve apex above the line for a subtle "arc" look
        let curveHeight: CGFloat = style == .hero ? 28 : 18
        let apex = CGPoint(x: (startX + endX) / 2, y: midY - curveHeight)
        let start = CGPoint(x: startX, y: midY)
        let end = CGPoint(x: endX, y: midY)

        // Dashed route line
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: apex)
        canvas.stroke(
            path,
            with: .color(JetsetterTheme.Colors.accent.opacity(0.45)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 6])
        )

        // Progress for plane position
        let normalized = resolvedProgress(date: date)
        let planePos = quadPoint(t: normalized, start: start, control: apex, end: end)
        let nextPos = quadPoint(t: min(normalized + 0.01, 1.0), start: start, control: apex, end: end)
        let heading = atan2(nextPos.y - planePos.y, nextPos.x - planePos.x)

        // Origin marker (pulse if gate closing)
        let originPulse = isGateClosing ? pulse(date: date, period: 1.0) : 1.0
        canvas.fill(
            Path(ellipseIn: CGRect(
                x: start.x - style.markerSize / 2 - (originPulse - 1.0) * 6,
                y: start.y - style.markerSize / 2 - (originPulse - 1.0) * 6,
                width: style.markerSize + (originPulse - 1.0) * 12,
                height: style.markerSize + (originPulse - 1.0) * 12
            )),
            with: .color(isGateClosing
                         ? JetsetterTheme.Colors.danger.opacity(originPulse > 1.1 ? 0.4 : 0.85)
                         : JetsetterTheme.Colors.accent)
        )

        // Destination marker (pulse if arriving)
        let destPulse = isArriving ? pulse(date: date, period: 1.2) : 1.0
        canvas.fill(
            Path(ellipseIn: CGRect(
                x: end.x - style.markerSize / 2 - (destPulse - 1.0) * 6,
                y: end.y - style.markerSize / 2 - (destPulse - 1.0) * 6,
                width: style.markerSize + (destPulse - 1.0) * 12,
                height: style.markerSize + (destPulse - 1.0) * 12
            )),
            with: .color(isArriving
                         ? JetsetterTheme.Colors.success
                         : JetsetterTheme.Colors.accent)
        )

        // Plane: draw the symbol resolved from `symbols` block, rotated to heading
        canvas.translateBy(x: planePos.x, y: planePos.y)
        canvas.rotate(by: .radians(heading))
        if let resolved = canvas.resolveSymbol(id: 1) {
            canvas.draw(resolved, at: .zero)
        }
    }

    private var symbolLayer: some View {
        Image(systemName: "airplane")
            .font(.system(size: style.planeSize, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: JetsetterTheme.Colors.accent.opacity(0.6), radius: 6)
            .tag(1)
    }

    // MARK: - Math

    private func resolvedProgress(date: Date) -> Double {
        if let p = progress { return max(0, min(p, 1)) }
        // Decorative looping: 6 seconds per pass, pause briefly at endpoints.
        let cycle = 7.0
        let phase = date.timeIntervalSince1970.truncatingRemainder(dividingBy: cycle) / cycle
        // Ease in/out for natural feel
        if phase < 0.1 { return 0 }
        if phase > 0.9 { return 1 }
        let t = (phase - 0.1) / 0.8
        return 0.5 - cos(.pi * t) / 2  // smoothstep
    }

    private func quadPoint(t: Double, start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let one = 1.0 - t
        let x = one * one * start.x + 2 * one * t * control.x + t * t * end.x
        let y = one * one * start.y + 2 * one * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }

    /// Returns a value oscillating between 1.0 and ~1.5 over `period` seconds.
    private func pulse(date: Date, period: Double) -> Double {
        let phase = date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
        return 1.0 + 0.5 * abs(sin(phase * .pi))
    }
}

// MARK: - Labeled wrapper

/// Convenience wrapper that adds IATA code labels above the route. Used by
/// most call sites; FlightAnimationView itself is unlabeled for flexibility.
struct LabeledFlightAnimation: View {

    let originIATA: String
    let destinationIATA: String
    var progress: Double? = nil
    var isArriving: Bool = false
    var isGateClosing: Bool = false
    var style: FlightAnimationView.Style = .compact

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(originIATA)
                    .font(style.iataFont)
                    .foregroundStyle(.white)
                Spacer()
                Text(destinationIATA)
                    .font(style.iataFont)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 28)

            FlightAnimationView(
                originIATA: originIATA,
                destinationIATA: destinationIATA,
                progress: progress,
                isArriving: isArriving,
                isGateClosing: isGateClosing,
                style: style
            )
        }
    }
}

// MARK: - Preview

#Preview("Compact looping") {
    ZStack {
        Color(white: 0.08).ignoresSafeArea()
        LabeledFlightAnimation(originIATA: "SFO", destinationIATA: "NRT")
            .padding()
    }
}

#Preview("Hero arriving") {
    ZStack {
        Color(white: 0.08).ignoresSafeArea()
        LabeledFlightAnimation(
            originIATA: "JFK",
            destinationIATA: "LHR",
            progress: 0.92,
            isArriving: true,
            style: .hero
        )
        .padding()
    }
}

#Preview("Gate closing") {
    ZStack {
        Color(white: 0.08).ignoresSafeArea()
        LabeledFlightAnimation(
            originIATA: "SFO",
            destinationIATA: "LAX",
            progress: 0.05,
            isGateClosing: true,
            style: .hero
        )
        .padding()
    }
}
