// File: Shared/JetSetterDeepLink.swift
//
// The app's URL scheme, `jetsetterpro://`, parsed and built in one place. The
// Next Trip widget and the Live Activity build their tap targets with it
// (`widgetURL`), the app parses incoming URLs with it in `onOpenURL`, and the
// backend's push `deepLink` key uses the same spellings. Keeping both halves
// in one type means a widget can never link to a path the app doesn't know.
//
//   jetsetterpro://trip/next            the next trip (Home)
//   jetsetterpro://trip/new             the Add Trip form
//   jetsetterpro://trip/<uuid>          one trip (Trip Day widget set to a trip)
//   jetsetterpro://flight/DL1423        that flight's card on Home
//   jetsetterpro://wallet               the Wallet tab
//   jetsetterpro://wallet/pass/<uuid>   one pass in the wallet
//
// Lives in Shared/ because the app and the widget extension both compile it,
// so it is plain Foundation. `nonisolated` keeps the app target's MainActor
// default from applying here, so the widget, the notification delegate and
// tests can all use it from any context.
//
// The flight segment is only checked for URL hygiene (letters and digits).
// Whether it is a real flight number is decided in the app by the one flight
// number parser, `TravelStore.extractFlightNumber`, which the widget can't see.

import Foundation

nonisolated enum JetSetterDeepLink: Hashable, Sendable {
    case nextTrip
    case newTrip
    /// A specific trip, by its id.
    case trip(UUID)
    /// Compact, upper-cased flight text from the URL ("DL1423").
    case flight(String)
    case wallet
    case walletPass(UUID)

    static let scheme = "jetsetterpro"

    // MARK: - Parsing

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        // "jetsetterpro://trip/next" puts "trip" in the host. The host-less
        // "jetsetterpro:///trip/next" spelling is accepted too, because a
        // hand-typed backend template can easily produce it.
        let segments = ([components.host ?? ""] + components.path.split(separator: "/").map(String.init))
            .filter { !$0.isEmpty }
        guard let head = segments.first?.lowercased() else { return nil }

        switch head {
        case "trip":
            guard segments.count == 2 else { return nil }
            switch segments[1].lowercased() {
            case "next": self = .nextTrip
            case "new":  self = .newTrip
            default:
                guard let id = UUID(uuidString: segments[1]) else { return nil }
                self = .trip(id)
            }

        case "flight":
            guard segments.count == 2 else { return nil }
            let compact = segments[1].uppercased().filter { !$0.isWhitespace }
            guard (2...10).contains(compact.count),
                  compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
            self = .flight(compact)

        case "wallet":
            if segments.count == 1 {
                self = .wallet
            } else if segments.count == 3, segments[1].lowercased() == "pass",
                      let id = UUID(uuidString: segments[2]) {
                self = .walletPass(id)
            } else {
                return nil
            }

        default:
            return nil
        }
    }

    // MARK: - Building

    /// The link as a URL. Optional only because `URLComponents` says so; every
    /// case builds a valid URL.
    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .nextTrip:
            components.host = "trip"
            components.path = "/next"
        case .newTrip:
            components.host = "trip"
            components.path = "/new"
        case .trip(let id):
            components.host = "trip"
            components.path = "/" + id.uuidString
        case .flight(let number):
            components.host = "flight"
            components.path = "/" + number.uppercased().filter { !$0.isWhitespace }
        case .wallet:
            components.host = "wallet"
        case .walletPass(let id):
            components.host = "wallet"
            components.path = "/pass/" + id.uuidString
        }
        return components.url
    }
}
