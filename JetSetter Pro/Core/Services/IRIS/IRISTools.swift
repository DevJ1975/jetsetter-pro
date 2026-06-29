// File: Core/Services/IRIS/IRISTools.swift
//
// The five tools IRIS can call. Apple recommends 3-5 tools max for context
// efficiency, so we picked the highest-leverage ones:
//   1. GetTripsTool              — read the user's itinerary
//   2. GetWeatherTool            — live weather at a destination
//   3. GetVisaAndEssentialsTool  — entry rules + emergency/tipping/plug data
//   4. RememberPreferenceTool    — persist a new user preference
//   5. GetDepartureRecommendationTool — the headline "leave-by" answer
//
// Recall of preferences is NOT a tool — IRIS gets all stored preferences
// injected into her Instructions at session creation by IRISPersonality.

import Foundation
import FoundationModels
import CoreLocation

// MARK: - 1. GetTripsTool

@available(iOS 26.0, *)
struct GetTripsTool: Tool {
    let name = "getUserTrips"
    let description = "Returns the user's saved trips (name, destination, dates, flights, hotels) so you can ground answers in their real plans."

    @Generable
    struct Arguments {
        @Guide(description: "Filter to 'upcoming', 'past', or 'all'. Defaults to 'upcoming'.")
        var filter: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let filter = (arguments.filter ?? "upcoming").lowercased()
        let trips = await loadTrips()
        let now = Date()
        let filtered: [Trip]
        switch filter {
        case "past": filtered = trips.filter { $0.endDate < now }
        case "all":  filtered = trips
        default:     filtered = trips.filter { $0.endDate >= now }
        }
        if filtered.isEmpty { return "User has no \(filter) trips on file." }

        let f = DateFormatter(); f.dateStyle = .medium
        let lines = filtered.sorted { $0.startDate < $1.startDate }.map { trip -> String in
            let items = trip.items.prefix(6).map { "    • \($0.title) (\(f.string(from: $0.startDate)))" }.joined(separator: "\n")
            return """
            - \(trip.name) — \(trip.destination)
              \(f.string(from: trip.startDate)) → \(f.string(from: trip.endDate))
            \(items)
            """
        }
        return lines.joined(separator: "\n\n")
    }

    @MainActor
    private func loadTrips() -> [Trip] {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips") else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (try? d.decode([Trip].self, from: data)) ?? []
    }
}

// MARK: - 2. GetWeatherTool

@available(iOS 26.0, *)
struct GetWeatherTool: Tool {
    let name = "getWeather"
    let description = "Returns current weather (temperature, conditions) at a destination city or airport IATA code."

    @Generable
    struct Arguments {
        @Guide(description: "City name or 3-letter IATA airport code, e.g. 'Tokyo' or 'NRT'.")
        var location: String
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.location.uppercased().trimmingCharacters(in: .whitespaces)
        let coord = AirportCoordinates.coordinate(for: query)
        guard let coord else {
            return "I don't have coordinates for \(arguments.location). Ask me by airport code (e.g. NRT, CDG)."
        }
        guard let weather = try? await WeatherService.shared.fetch(
            latitude: coord.latitude, longitude: coord.longitude
        ) else {
            return "Couldn't reach the weather service for \(arguments.location). Try again in a moment."
        }
        return "\(Int(weather.temperatureFahrenheit))°F, \(weather.conditionDescription). Wind \(Int(weather.windspeedKmh)) km/h."
    }
}

// MARK: - 3. GetVisaAndEssentialsTool

@available(iOS 26.0, *)
struct GetVisaAndEssentialsTool: Tool {
    let name = "getVisaAndCountryEssentials"
    let description = "Returns US-passport visa requirements PLUS country essentials (emergency numbers, tipping etiquette, plug types, water safety) for a destination country."

    @Generable
    struct Arguments {
        @Guide(description: "Country name like 'Japan' or 'France'. NOT a city.")
        var country: String
    }

    func call(arguments: Arguments) async throws -> String {
        var parts: [String] = []

        if let visa = VisaRequirements.find(query: arguments.country) {
            var line = "VISA (US passport): \(visa.requirementKind.rawValue)"
            if let days = visa.maxStayDays { line += ", up to \(days) days" }
            if let fee = visa.entryFee { line += ", fee \(fee)" }
            line += ". Passport: \(visa.passportValidityMonths == 0 ? "valid through stay" : "valid \(visa.passportValidityMonths)mo past entry")."
            if visa.onwardTicketRequired { line += " Onward ticket required." }
            parts.append(line)
            if !visa.additionalNotes.isEmpty {
                parts.append("NOTES: " + visa.additionalNotes.joined(separator: " "))
            }
        }

        if let country = TravelEssentialsData.find(query: arguments.country) {
            parts.append("EMERGENCY: \(country.emergency.general ?? country.emergency.police) (police: \(country.emergency.police))")
            parts.append("TIPPING (restaurants): \(country.tipping.restaurantPercent)")
            parts.append("PLUGS: Type \(country.electrical.plugTypes.joined(separator: "/")), \(country.electrical.voltage)\(country.electrical.needsAdapterForUS ? " — US travelers need an adapter" : "")")
            parts.append("WATER: \(country.waterSafe ? "Tap water safe" : "Drink bottled only")\(country.waterNote.map { " — \($0)" } ?? "")")
        }

        return parts.isEmpty
            ? "I don't have detailed data for \(arguments.country). Verify with travel.state.gov before flying."
            : parts.joined(separator: "\n")
    }
}

// MARK: - 4. RememberPreferenceTool

@available(iOS 26.0, *)
struct RememberPreferenceTool: Tool {
    let name = "rememberUserPreference"
    let description = "Saves a single travel preference (e.g., vegetarian, aisle seat near front) so you can recall it across conversations."

    @Generable
    struct Arguments {
        @Guide(description: "Category: dietary, seating, hotelStyle, airlinePreference, transportation, destinations, activities, or general.")
        var category: String
        @Guide(description: "The preference itself, as a short noun phrase. E.g. 'vegetarian' or 'aisle seat near front'.")
        var value: String
    }

    func call(arguments: Arguments) async throws -> String {
        let category = IRISPreference.Category.allCases.first {
            $0.rawValue.lowercased() == arguments.category.lowercased()
        } ?? .general
        let saved = await Task { @MainActor in
            IRISMemory.shared.remember(category: category, value: arguments.value)
        }.value
        return "Saved: \(saved.category.displayName) → \(saved.value)."
    }
}

// MARK: - 6. GetTravelProfileTool

@available(iOS 26.0, *)
struct GetTravelProfileTool: Tool {
    let name = "getLearnedTravelProfile"
    let description = "Returns what the app has LEARNED about this traveler from their past behavior — typical seat, preferred airlines/cabin, hotel brands, frequent places, and typical spending. Use it to personalize and anticipate. Returns a note if nothing has been learned yet."

    @Generable
    struct Arguments {
        @Guide(description: "Optional focus: 'seat', 'airlines', 'hotels', 'spend', 'places', or 'all'. Defaults to 'all'.")
        var aspect: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let summary = await Task { @MainActor in
            TravelProfileStore.shared.profile.summaryForPrompt()
        }.value
        return summary.isEmpty
            ? "I haven't learned enough about this traveler's habits yet — nothing on file."
            : summary
    }
}

// MARK: - SubmitExpensesTool

@available(iOS 26.0, *)
struct SubmitExpensesTool: Tool {
    let name = "submitExpenses"
    let description = "Submits the user's logged expenses to a connected provider (email, expensify, ramp, brex, divvy). Optionally filters to a trip by name."

    @Generable
    struct Arguments {
        @Guide(description: "Provider ID: 'email', 'expensify', 'ramp', 'brex', or 'divvy'. Use 'email' for the universal PDF fallback.")
        var provider: String
        @Guide(description: "Optional trip name substring to filter expenses (e.g. 'Tokyo'). If omitted, submits ALL expenses.")
        var tripName: String?
    }

    func call(arguments: Arguments) async throws -> String {
        return await Task { @MainActor () -> String in
            let id: String = {
                switch arguments.provider.lowercased() {
                case "email", "email_pdf", "pdf": return "email_pdf"
                default: return arguments.provider.lowercased()
                }
            }()
            guard let provider = ExpenseExportRegistry.find(id: id) else {
                return "Unknown provider '\(arguments.provider)'. Try: email, expensify, ramp, brex, divvy."
            }
            guard await provider.isConnected() else {
                return "\(provider.displayName) isn't connected. Open Settings → Expense Connections to set it up."
            }

            // Load expenses
            guard let data = UserDefaults.standard.data(forKey: "jetsetter_expenses") else {
                return "I don't see any logged expenses yet."
            }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let allExpenses = (try? decoder.decode([Expense].self, from: data)) ?? []
            guard !allExpenses.isEmpty else { return "No expenses to submit." }

            // Find trip
            var trip: Trip?
            if let tripName = arguments.tripName?.trimmingCharacters(in: .whitespaces), !tripName.isEmpty,
               let tripData = UserDefaults.standard.data(forKey: "jetsetter_trips"),
               let trips = try? decoder.decode([Trip].self, from: tripData) {
                trip = trips.first {
                    $0.name.lowercased().contains(tripName.lowercased())
                    || $0.destination.lowercased().contains(tripName.lowercased())
                }
            }

            let scoped: [Expense]
            if let trip = trip {
                let end = trip.endDate.addingTimeInterval(86400)
                scoped = allExpenses.filter { $0.date >= trip.startDate && $0.date < end }
                if scoped.isEmpty {
                    return "No expenses found within \(trip.name)'s date range."
                }
            } else {
                scoped = allExpenses
            }

            // Submitting is an outbound write — stage it for confirmation rather
            // than sending immediately. The actual submit runs from the card.
            let providerName = provider.displayName
            let count = scoped.count
            let scopeLabel = trip.map { " for \($0.name)" } ?? ""
            let summary = "Submit \(count) expense\(count == 1 ? "" : "s")\(scopeLabel) via \(providerName)"
            let tripForCommit = trip

            let action = IRISPendingAction(kind: .submitExpenses, summary: summary) {
                do {
                    let result = try await provider.submit(trip: tripForCommit, expenses: scoped)
                    return "Submitted \(result.successCount) of \(count) expense\(count == 1 ? "" : "s") via \(result.providerName)."
                } catch {
                    return "Submit failed: \(error.localizedDescription)"
                }
            }
            IRISActionRouter.shared.proposeAction(action)
            return "Prepared to submit \(count) expense\(count == 1 ? "" : "s")\(scopeLabel) via \(providerName). Ask the user to confirm — nothing has been sent yet."
        }.value
    }
}

// MARK: - 5. GetDepartureRecommendationTool

@available(iOS 26.0, *)
struct GetDepartureRecommendationTool: Tool {
    let name = "getDepartureRecommendation"
    let description = "Computes when the user should leave for the airport based on live traffic, TSA wait estimate, and their security lane."

    @Generable
    struct Arguments {
        @Guide(description: "Origin airport IATA code (e.g. SFO, JFK, LHR).")
        var originAirportIATA: String
        @Guide(description: "ISO 8601 scheduled departure timestamp, e.g. 2026-08-15T18:25:00Z.")
        var scheduledDepartureISO: String
        @Guide(description: "Security lane: 'standard', 'preCheck', 'clear', or 'clearPlusPreCheck'. Defaults to standard.")
        var lane: String?
        @Guide(description: "Current user latitude. Required.")
        var currentLatitude: Double
        @Guide(description: "Current user longitude. Required.")
        var currentLongitude: Double
    }

    func call(arguments: Arguments) async throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let departure = formatter.date(from: arguments.scheduledDepartureISO)
            ?? ISO8601DateFormatter().date(from: arguments.scheduledDepartureISO)
        guard let departure else {
            return "I couldn't parse the departure time '\(arguments.scheduledDepartureISO)'. Use ISO 8601."
        }

        let lane: SecurityLane = {
            switch (arguments.lane ?? "standard").lowercased() {
            case "precheck":          return .preCheck
            case "clear":             return .clear
            case "clearpluspreCheck",
                 "clearplusprecheck": return .clearPlusPreCheck
            default:                  return .standard
            }
        }()

        let coord = CLLocationCoordinate2D(
            latitude: arguments.currentLatitude,
            longitude: arguments.currentLongitude
        )
        let rec = await Task { @MainActor in
            await DepartureOptimizerService.shared.recommend(
                currentLocation: coord,
                airportIATA: arguments.originAirportIATA,
                scheduledDeparture: departure,
                lane: lane
            )
        }.value
        guard let rec else {
            return "I don't have coordinates for \(arguments.originAirportIATA). Try a different airport."
        }

        let t = DateFormatter(); t.timeStyle = .short
        return """
        Leave at \(t.string(from: rec.leaveAt)) (in \(rec.minutesUntilLeave) min).
        Drive: \(rec.driveMinutes) min. TSA: \(rec.tsaWait.display). Buffer: \(rec.boardingBufferMinutes) min at gate.
        Status: \(rec.urgency.label).
        """
    }
}
