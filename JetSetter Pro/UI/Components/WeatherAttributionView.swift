// File: UI/Components/WeatherAttributionView.swift
//
// Apple requires the Apple Weather mark and a link to its legal attribution
// page wherever WeatherKit data is displayed. Shows nothing for data that came
// from the Open-Meteo fallback.

import SwiftUI
import WeatherKit

struct WeatherAttributionView: View {
    let source: WeatherSource
    var onDark: Bool = true

    @State private var attribution: WeatherAttribution?
    @State private var legalURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if source == .weatherKit, let attribution {
                HStack(spacing: 4) {
                    AsyncImage(url: (onDark || colorScheme == .dark) ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Text("Apple Weather").font(.system(size: 9, weight: .semibold))
                    }
                    .frame(height: 12)
                    Button("Legal") { legalURL = attribution.legalPageURL }
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(onDark ? Color.white.opacity(0.6) : .secondary)
                }
                .accessibilityLabel("Weather data by Apple Weather")
            }
        }
        .task {
            guard source == .weatherKit, attribution == nil else { return }
            attribution = await WeatherService.shared.attribution()
        }
        .inAppWeb(url: $legalURL, title: "Apple Weather")
    }
}
