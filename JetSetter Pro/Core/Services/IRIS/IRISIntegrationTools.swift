// File: Core/Services/IRIS/IRISIntegrationTools.swift
//
// Bridge tools that connect IRIS to app services she previously couldn't
// reach. Each wraps a real, already-shipping service so IRIS can *invoke* the
// full API surface, not just describe it:
//
//   • ConvertCurrencyTool  — live FX conversion   (ExchangeRateService)
//   • GetFlightStatusTool   — live flight status   (FlightAware, via DisruptionMonitorService)
//   • SearchRentalCarsTool  — rental car search    (RentalCarService: Enterprise/Hertz/National)
//   • DisruptionTool        — rebooking options    (DisruptionResponseEngine: Amadeus + Duffel)
//   • TraceBaggageTool      — bag trace by tag      (SITAWorldTracerService)
//   • AddToCalendarTool     — [staged] add events   (CalendarService / EventKit)
//
// Read/lookup tools run immediately. AddToCalendarTool writes to the device
// Calendar, so it follows the same confirm-before-commit pattern as the other
// action tools (stages an IRISPendingAction; the user's tap runs the commit).

import Foundation
import FoundationModels

// MARK: - Convert Currency (immediate — read-only)

@available(iOS 26.0, *)
struct ConvertCurrencyTool: Tool {
    let name = "convertCurrency"
    let description = "Converts a money amount from one currency to another at live exchange rates. Use for questions like 'how much is 200 euros in dollars?'."

    @Generable
    struct Arguments {
        @Guide(description: "The amount of money to convert, e.g. 200.")
        var amount: Double
        @Guide(description: "Source 3-letter currency code, e.g. EUR.")
        var fromCurrency: String
        @Guide(description: "Target 3-letter currency code, e.g. USD.")
        var toCurrency: String
    }

    func call(arguments: Arguments) async throws -> String {
        let from = arguments.fromCurrency.uppercased().trimmingCharacters(in: .whitespaces)
        let to   = arguments.toCurrency.uppercased().trimmingCharacters(in: .whitespaces)
        guard from.count == 3, to.count == 3 else {
            return "Give me 3-letter currency codes, like EUR and USD."
        }
        if from == to {
            return String(format: "%.2f %@ is already in %@ — no conversion needed.", arguments.amount, from, to)
        }
        guard let rates = await ExchangeRateService.shared.rates(for: from),
              let converted = rates.convert(amount: arguments.amount, to: to) else {
            return "I couldn't get a live \(from)→\(to) rate right now. Try again in a moment."
        }
        let unitRate = rates.rates[to] ?? (converted / max(arguments.amount, 0.0001))
        return String(format: "%.2f %@ ≈ %.2f %@ (1 %@ = %.4f %@).",
                      arguments.amount, from, converted, to, from, unitRate, to)
    }
}

// MARK: - Flight Status (immediate — read-only)

@available(iOS 26.0, *)
struct GetFlightStatusTool: Tool {
    let name = "getFlightStatus"
    let description = "Returns live status for a flight number (gate, terminal, delay, cancellation) without leaving the conversation. Use trackFlight instead when the user wants to OPEN the flight tracker."

    @Generable
    struct Arguments {
        @Guide(description: "Flight number, e.g. 'AA100' or 'UA55'.")
        var flightNumber: String
    }

    func call(arguments: Arguments) async throws -> String {
        let number = arguments.flightNumber.trimmingCharacters(in: .whitespaces).uppercased()
        guard !number.isEmpty else { return "Which flight number should I check?" }

        let flight: Flight
        do {
            flight = try await DisruptionMonitorService.shared.fetchFlightStatus(flightNumber: number)
        } catch {
            return "I couldn't reach the flight-status service for \(number) right now. I can open the Flight Tracker for you instead."
        }

        return await MainActor.run {
            var status = flight.status
            if flight.cancelled { status = "Cancelled" }
            else if flight.diverted { status = "Diverted" }

            var lines = ["\(number) — \(status)",
                         "\(flight.origin.displayName) → \(flight.destination.displayName)"]

            var gateBits: [String] = []
            if let g = flight.gateOrigin, !g.isEmpty { gateBits.append("Gate \(g)") }
            if let t = flight.terminalOrigin, !t.isEmpty { gateBits.append("Terminal \(t)") }
            if !gateBits.isEmpty { lines.append(gateBits.joined(separator: ", ")) }

            if let dep = flight.bestDepartureTime {
                let f = DateFormatter(); f.timeStyle = .short; f.timeZone = flight.origin.timeZone
                lines.append("Departs \(f.string(from: dep))")
            }
            if let delay = flight.departureDelayMinutes, delay > 0 {
                lines.append("Departure delayed \(delay) min")
            }
            if let claim = flight.baggageClaim, !claim.isEmpty {
                lines.append("Baggage claim \(claim)")
            }
            return lines.joined(separator: "\n")
        }
    }
}

// MARK: - Search Rental Cars (immediate — read-only)

@available(iOS 26.0, *)
struct SearchRentalCarsTool: Tool {
    let name = "searchRentalCars"
    let description = "Searches rental cars across Enterprise, Hertz and National for a pickup location and date range, returning the best few options by price."

    @Generable
    struct Arguments {
        @Guide(description: "Pickup location — an airport IATA code or city, e.g. 'NRT' or 'Tokyo'.")
        var location: String
        @Guide(description: "Pickup date as yyyy-MM-dd, e.g. 2026-08-15.")
        var pickupDate: String
        @Guide(description: "Drop-off date as yyyy-MM-dd, e.g. 2026-08-19.")
        var dropoffDate: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let pickup = AddTripTool.parseDate(arguments.pickupDate),
              let dropoff = AddTripTool.parseDate(arguments.dropoffDate) else {
            return "I couldn't read those dates. Give me pickup and drop-off like 2026-08-15."
        }
        guard dropoff > pickup else {
            return "The drop-off date needs to be after the pickup date."
        }
        let location = arguments.location.trimmingCharacters(in: .whitespaces)
        guard !location.isEmpty else { return "Where should I pick the car up?" }

        var params = RentalCarSearchParams()
        params.pickupLocation = location
        params.pickupDate = pickup
        params.dropoffDate = dropoff

        do {
            let vehicles = try await RentalCarService.shared.searchVehicles(params: params)
            let top = vehicles.prefix(3)
            guard !top.isEmpty else {
                return "No rental cars came back for \(location) on those dates."
            }
            let lines = top.map { v in
                "• \(v.displayName) (\(v.provider.displayName)) — \(v.formattedDailyRate)/day, \(v.formattedTotalWithTaxes) total"
            }
            return "Rental options at \(location):\n" + lines.joined(separator: "\n")
        } catch {
            return "I couldn't complete the rental search: \(error.localizedDescription)"
        }
    }
}

// MARK: - Disruption / Rebooking (immediate — read-only)

@available(iOS 26.0, *)
struct DisruptionTool: Tool {
    let name = "checkDisruption"
    let description = "When a flight is delayed or cancelled, finds up to 3 alternative flights on the same route and reports whether the booking can be changed. Provide origin and destination airport codes and the travel date."

    @Generable
    struct Arguments {
        @Guide(description: "Origin airport IATA code, e.g. 'JFK'.")
        var origin: String
        @Guide(description: "Destination airport IATA code, e.g. 'LAX'.")
        var destination: String
        @Guide(description: "Travel date as yyyy-MM-dd, e.g. 2026-08-15.")
        var date: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let date = AddTripTool.parseDate(arguments.date) else {
            return "I couldn't read that date. Use yyyy-MM-dd, like 2026-08-15."
        }
        let origin = arguments.origin.trimmingCharacters(in: .whitespaces).uppercased()
        let destination = arguments.destination.trimmingCharacters(in: .whitespaces).uppercased()

        let alternatives = await DisruptionResponseEngine.shared.searchAlternativeFlights(
            origin: origin, destination: destination, date: date
        )

        // Fails open to true, so phrase it as "likely available".
        let tripId = await MainActor.run { TravelStore.activeOrNextTrip()?.id }
        var eligibilityLine = ""
        if let tripId {
            let changeable = await DisruptionResponseEngine.shared.checkRebookingEligibility(tripId: tripId)
            eligibilityLine = changeable
                ? "Your current booking looks eligible to change.\n"
                : "Your current booking may not be changeable — check the fare rules.\n"
        }

        guard !alternatives.isEmpty else {
            return eligibilityLine + "I couldn't find alternative flights on \(origin)→\(destination) for that date right now."
        }

        let t = AppDateFormatters.shortTime
        let lines = alternatives.prefix(3).map { alt -> String in
            "• \(alt.flightNumber) — \(t.string(from: alt.departure)) → \(t.string(from: alt.arrival)), \(alt.durationFormatted), \(alt.cabinClass), \(alt.priceFormatted), ~\(alt.availableSeats) seats"
        }
        return eligibilityLine + "Alternatives on \(origin)→\(destination):\n" + lines.joined(separator: "\n")
    }
}

// MARK: - Trace Baggage (immediate — read-only)

@available(iOS 26.0, *)
struct TraceBaggageTool: Tool {
    let name = "traceBaggage"
    let description = "Traces a checked bag by its 7–10 digit bag tag number via SITA WorldTracer and reports its current status and location."

    @Generable
    struct Arguments {
        @Guide(description: "The bag tag number printed on the check-in receipt (7–10 digits).")
        var tagNumber: String
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let bag = try await SITAWorldTracerService.shared.traceBag(tagNumber: arguments.tagNumber)
            var lines = ["Bag \(bag.tagNumber): \(bag.mappedStatus.displayName)"]
            if let loc = bag.lastLocation, !loc.isEmpty { lines.append("Last seen: \(loc)") }
            if let fn = bag.flightNumber, !fn.isEmpty {
                lines.append("Flight: \(fn)\(bag.airline.map { " (\($0))" } ?? "")")
            }
            if let eta = bag.expectedDelivery, !eta.isEmpty { lines.append("Expected: \(eta)") }
            if let notes = bag.remarks, !notes.isEmpty { lines.append("Note: \(notes)") }
            return lines.joined(separator: "\n")
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - Add to Calendar (confirm before commit)

@available(iOS 26.0, *)
struct AddToCalendarTool: Tool {
    let name = "addToCalendar"
    let description = "Prepare to add a trip's flights and events to the device Calendar. This does NOT add them immediately — the user must confirm, and Calendar permission may be requested."

    @Generable
    struct Arguments {
        @Guide(description: "Optional trip name to target; defaults to the active or next upcoming trip.")
        var tripName: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let wanted = arguments.tripName?.trimmingCharacters(in: .whitespaces).lowercased()
        let trip: Trip? = await MainActor.run {
            if let wanted, !wanted.isEmpty {
                return TravelStore.loadTrips().first {
                    $0.name.lowercased().contains(wanted) || $0.destination.lowercased().contains(wanted)
                }
            }
            return TravelStore.activeOrNextTrip()
        }
        guard let trip else {
            return "Add a trip first and I'll put its events on your Calendar."
        }
        let items = trip.sortedItems
        guard !items.isEmpty else {
            return "\(trip.name) doesn't have any itinerary items to add yet."
        }
        let tripName = trip.name
        let count = items.count
        let summary = "Add \(count) event\(count == 1 ? "" : "s") from \(tripName) to your Calendar"

        await MainActor.run {
            let action = IRISPendingAction(kind: .addToCalendar, summary: summary) {
                var added = 0
                for item in items {
                    if (try? await CalendarService.shared.addEvent(for: item)) != nil { added += 1 }
                }
                if added == 0 {
                    return "I couldn't add those — check Calendar access in Settings › Privacy › Calendars."
                }
                return "Added \(added) event\(added == 1 ? "" : "s") from \(tripName) to your Calendar."
            }
            IRISActionRouter.shared.proposeAction(action)
        }
        return "Prepared: \(summary). Ask the user to confirm — nothing is on the Calendar yet."
    }
}
