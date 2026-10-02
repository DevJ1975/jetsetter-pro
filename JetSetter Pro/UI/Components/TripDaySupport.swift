// File: UI/Components/TripDaySupport.swift
//
// Small helpers shared by the trip-day screens (boarding pass, check-in,
// Flight Tracker, Disruption, Itinerary, Packing, Departures board):
//
//   • `TripSpeech` turns airport codes into words VoiceOver can say. Without
//     it "LAS → ATL" is read as "L A S right arrow A T L", which no traveler
//     wants to hear at a gate.
//   • `TripDayLayout` holds the readable-width cap, so a boarding pass or the
//     check-in flow doesn't stretch edge to edge on the iPhone Ultra's inner
//     screen. It caps by the space offered, never by device model.
//   • `ChecklistToggleStyle` keeps the packing rows' circle-and-check look
//     while giving them real toggle semantics. They used to be plain views
//     with `.onTapGesture`, which VoiceOver announced as static text with no
//     way to tell whether an item was packed.
//
// Consolidate later: a parallel change adds `AirportNames` in Core/Utilities.
// When it lands, `TripSpeech.spokenAirport(_:)` should call it and the city
// table in `BoardingPassCard.cityName(for:)` should move there. They stay here
// for now, scoped under `TripSpeech` so nothing collides with that file.

import SwiftUI

// MARK: - TripSpeech

enum TripSpeech {

    /// "LAS" → "Las Vegas". An unknown code is spelled out ("X Y Z"), so
    /// VoiceOver reads the letters instead of guessing at a word, and an
    /// empty or "—" code reads as "unknown airport". Nothing is invented.
    static func spokenAirport(_ code: String?) -> String {
        let trimmed = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty, trimmed != "—" else { return "unknown airport" }
        if let city = BoardingPassCard.cityName(for: trimmed), city != trimmed {
            return city
        }
        return trimmed.map { String($0) }.joined(separator: " ")
    }

    /// ["LAS", "ATL"] → "Las Vegas to Atlanta". Takes every leg, so a
    /// connection reads "Las Vegas to Denver to Atlanta".
    static func spokenRoute(_ codes: [String?]) -> String {
        codes.map(spokenAirport).joined(separator: " to ")
    }

    /// Splits a display route such as "LAS → ATL" (the shape `CheckInFlowView`
    /// and the disruption cards receive) into codes for `spokenRoute(_:)`.
    static func codes(fromDisplayRoute route: String) -> [String?] {
        route.components(separatedBy: "→").map {
            let code = $0.trimmingCharacters(in: .whitespaces)
            return code.isEmpty ? nil : code
        }
    }

    /// Spoken form of a value that may be missing. An unknown gate or seat is
    /// shown as "—" on screen, and VoiceOver says "not assigned yet" instead of
    /// "dash".
    static func spokenValue(_ value: String?, missing: String = "not assigned yet") -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty || trimmed == "—") ? missing : trimmed
    }
}

// MARK: - TripDayLayout

enum TripDayLayout {
    /// Widest a trip-day column grows. Wider than any iPhone in portrait, so
    /// phones are unchanged; on the iPhone Ultra's inner screen or an iPad the
    /// content stays a comfortable reading width and is centred.
    static let readableWidth: CGFloat = 600
}

extension View {
    /// Caps the view at the readable width and centres it in whatever space
    /// it's given. Use this instead of fixed widths or `UIScreen` sizes.
    func tripDayReadableWidth(_ maxWidth: CGFloat = TripDayLayout.readableWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - ChecklistToggleStyle

/// A checklist row: an empty circle that fills with a checkmark when on. The
/// whole row is the tap target, and VoiceOver hears a toggle whose value is
/// "Packed" or "Not packed" rather than "on" or "off".
struct ChecklistToggleStyle: ToggleStyle {
    var onColor: Color
    var offColor: Color
    var onValue: String = "Packed"
    var offValue: String = "Not packed"

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                // `.title3` so the circle grows with Dynamic Type alongside the
                // item name instead of staying a fixed-size dot.
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? onColor : offColor)
                    .accessibilityHidden(true)
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? onValue : offValue)
    }
}
