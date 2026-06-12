// File: Core/Utilities/DigitalIDStates.swift
//
// US states and territories that support adding a state-issued driver's
// license or ID card to Apple Wallet. Updated against the public list at
// https://support.apple.com/118313 — verify periodically as Apple adds more.

import Foundation

struct DigitalIDState: Identifiable, Equatable {
    let id: String       // 2-letter postal code, e.g. "AZ"
    let name: String     // e.g. "Arizona"
    let issuerName: String   // e.g. "Arizona DOT"
    /// Official state information page or DMV mDL landing page.
    let infoURL: URL
    /// True when the state has fully launched in Apple Wallet (vs. announced).
    let isLive: Bool

    /// Combined regular DL + ID program identifier for display.
    var displayProgram: String { "\(name) Driver's License & State ID" }
}

enum DigitalIDStates {

    /// Live (or imminently live) Apple Wallet ID jurisdictions.
    static let all: [DigitalIDState] = [
        DigitalIDState(
            id: "AZ", name: "Arizona", issuerName: "Arizona Department of Transportation",
            infoURL: URL(string: "https://azdot.gov/mvd/services/driver-services/mobile-id")!,
            isLive: true
        ),
        DigitalIDState(
            id: "CA", name: "California", issuerName: "California DMV",
            infoURL: URL(string: "https://www.dmv.ca.gov/portal/ca-mobile-driver-license/")!,
            isLive: true
        ),
        DigitalIDState(
            id: "CO", name: "Colorado", issuerName: "Colorado DMV",
            infoURL: URL(string: "https://dmv.colorado.gov/myColorado-mobile-id")!,
            isLive: true
        ),
        DigitalIDState(
            id: "GA", name: "Georgia", issuerName: "Georgia Department of Driver Services",
            infoURL: URL(string: "https://dds.georgia.gov/digital-license-id")!,
            isLive: true
        ),
        DigitalIDState(
            id: "HI", name: "Hawaii", issuerName: "Hawaii Department of Transportation",
            infoURL: URL(string: "https://hidot.hawaii.gov/")!,
            isLive: true
        ),
        DigitalIDState(
            id: "IA", name: "Iowa", issuerName: "Iowa DOT",
            infoURL: URL(string: "https://iowadot.gov/mvd/mobile-id")!,
            isLive: true
        ),
        DigitalIDState(
            id: "KY", name: "Kentucky", issuerName: "Kentucky Transportation Cabinet",
            infoURL: URL(string: "https://drive.ky.gov/")!,
            isLive: true
        ),
        DigitalIDState(
            id: "MD", name: "Maryland", issuerName: "Maryland MVA",
            infoURL: URL(string: "https://mva.maryland.gov/Pages/MobileID.aspx")!,
            isLive: true
        ),
        DigitalIDState(
            id: "NM", name: "New Mexico", issuerName: "New Mexico MVD",
            infoURL: URL(string: "https://www.mvd.newmexico.gov/")!,
            isLive: true
        ),
        DigitalIDState(
            id: "OH", name: "Ohio", issuerName: "Ohio BMV",
            infoURL: URL(string: "https://bmv.ohio.gov/")!,
            isLive: true
        ),
        DigitalIDState(
            id: "PR", name: "Puerto Rico", issuerName: "Puerto Rico DTOP",
            infoURL: URL(string: "https://dtop.pr.gov/")!,
            isLive: true
        ),
        DigitalIDState(
            id: "WV", name: "West Virginia", issuerName: "West Virginia DMV",
            infoURL: URL(string: "https://transportation.wv.gov/DMV/")!,
            isLive: true
        )
    ]

    /// Returns the entry for a state postal code, or nil if not yet supported.
    static func find(stateCode: String) -> DigitalIDState? {
        all.first { $0.id == stateCode.uppercased() }
    }
}
