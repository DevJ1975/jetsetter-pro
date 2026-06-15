// File: UI/Components/AnimatedCounter.swift
//
// Counts up from 0 to a target Int/Double when it first appears. Drop-in:
//
//   AnimatedCounter(target: 247_830, duration: 1.2, format: .integer)
//   AnimatedCounter(target: 6_715.00, duration: 1.0, format: .currency("USD"))

import SwiftUI

enum CounterFormat {
    case integer
    case decimal(places: Int)
    case currency(String)   // currency code like "USD" or "JPY"
}

struct AnimatedCounter: View {

    let target: Double
    let duration: Double
    let format: CounterFormat

    @State private var started: Date?

    init(target: Int, duration: Double = 1.0, format: CounterFormat = .integer) {
        self.target = Double(target)
        self.duration = duration
        self.format = format
    }

    init(target: Double, duration: Double = 1.0, format: CounterFormat = .integer) {
        self.target = target
        self.duration = duration
        self.format = format
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let value = currentValue(at: context.date)
            Text(formatted(value))
                .contentTransition(.numericText())
        }
        .onAppear {
            started = Date()
        }
    }

    private func currentValue(at date: Date) -> Double {
        guard let started = started else { return 0 }
        let elapsed = date.timeIntervalSince(started)
        guard elapsed > 0 else { return 0 }
        if elapsed >= duration { return target }
        // Ease-out cubic for a natural deceleration.
        let t = elapsed / duration
        let eased = 1 - pow(1 - t, 3)
        return target * eased
    }

    private func formatted(_ value: Double) -> String {
        switch format {
        case .integer:
            return Int(value.rounded()).formatted(.number)
        case .decimal(let places):
            return String(format: "%.\(places)f", value)
        case .currency(let code):
            return String(format: "%@ %.2f", code, value)
        }
    }
}
