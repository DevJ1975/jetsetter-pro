// File: Core/Utilities/AirportCoordinates.swift
//
// Lookup table mapping IATA airport codes to lat/lon for the world's busiest
// hubs. Used by FlightMapView to plot real great-circle routes.

import Foundation
import CoreLocation

enum AirportCoordinates {

    static func coordinate(for iata: String) -> CLLocationCoordinate2D? {
        table[iata.uppercased()]
    }

    static func isKnown(_ iata: String) -> Bool {
        table[iata.uppercased()] != nil
    }

    // MARK: - Data

    private static let table: [String: CLLocationCoordinate2D] = [
        // ── North America ──────────────────────────────────────────────────
        "ATL": CLLocationCoordinate2D(latitude: 33.6407,  longitude: -84.4277),
        "BOS": CLLocationCoordinate2D(latitude: 42.3656,  longitude: -71.0096),
        "BWI": CLLocationCoordinate2D(latitude: 39.1754,  longitude: -76.6683),
        "CLT": CLLocationCoordinate2D(latitude: 35.2144,  longitude: -80.9473),
        "DCA": CLLocationCoordinate2D(latitude: 38.8512,  longitude: -77.0402),
        "DEN": CLLocationCoordinate2D(latitude: 39.8561,  longitude: -104.6737),
        "DFW": CLLocationCoordinate2D(latitude: 32.8998,  longitude: -97.0403),
        "DTW": CLLocationCoordinate2D(latitude: 42.2124,  longitude: -83.3534),
        "EWR": CLLocationCoordinate2D(latitude: 40.6925,  longitude: -74.1687),
        "FLL": CLLocationCoordinate2D(latitude: 26.0742,  longitude: -80.1506),
        "HNL": CLLocationCoordinate2D(latitude: 21.3187,  longitude: -157.9225),
        "IAD": CLLocationCoordinate2D(latitude: 38.9531,  longitude: -77.4565),
        "IAH": CLLocationCoordinate2D(latitude: 29.9844,  longitude: -95.3414),
        "JFK": CLLocationCoordinate2D(latitude: 40.6413,  longitude: -73.7781),
        "LAS": CLLocationCoordinate2D(latitude: 36.0840,  longitude: -115.1537),
        "LAX": CLLocationCoordinate2D(latitude: 33.9416,  longitude: -118.4085),
        "LGA": CLLocationCoordinate2D(latitude: 40.7769,  longitude: -73.8740),
        "MCO": CLLocationCoordinate2D(latitude: 28.4312,  longitude: -81.3081),
        "MIA": CLLocationCoordinate2D(latitude: 25.7959,  longitude: -80.2870),
        "MSP": CLLocationCoordinate2D(latitude: 44.8848,  longitude: -93.2223),
        "ORD": CLLocationCoordinate2D(latitude: 41.9742,  longitude: -87.9073),
        "PHL": CLLocationCoordinate2D(latitude: 39.8744,  longitude: -75.2424),
        "PHX": CLLocationCoordinate2D(latitude: 33.4373,  longitude: -112.0078),
        "SAN": CLLocationCoordinate2D(latitude: 32.7338,  longitude: -117.1933),
        "SEA": CLLocationCoordinate2D(latitude: 47.4502,  longitude: -122.3088),
        "SFO": CLLocationCoordinate2D(latitude: 37.6213,  longitude: -122.3790),
        "SLC": CLLocationCoordinate2D(latitude: 40.7899,  longitude: -111.9791),
        "MEX": CLLocationCoordinate2D(latitude: 19.4361,  longitude: -99.0719),
        "YUL": CLLocationCoordinate2D(latitude: 45.4706,  longitude: -73.7408),
        "YVR": CLLocationCoordinate2D(latitude: 49.1967,  longitude: -123.1815),
        "YYC": CLLocationCoordinate2D(latitude: 51.1215,  longitude: -114.0067),
        "YYZ": CLLocationCoordinate2D(latitude: 43.6772,  longitude: -79.6306),

        // ── South America ──────────────────────────────────────────────────
        "BOG": CLLocationCoordinate2D(latitude: 4.7016,   longitude: -74.1469),
        "EZE": CLLocationCoordinate2D(latitude: -34.8222, longitude: -58.5358),
        "GRU": CLLocationCoordinate2D(latitude: -23.4356, longitude: -46.4731),
        "LIM": CLLocationCoordinate2D(latitude: -12.0219, longitude: -77.1143),
        "SCL": CLLocationCoordinate2D(latitude: -33.3930, longitude: -70.7858),

        // ── Europe ─────────────────────────────────────────────────────────
        "AMS": CLLocationCoordinate2D(latitude: 52.3105,  longitude: 4.7683),
        "ARN": CLLocationCoordinate2D(latitude: 59.6498,  longitude: 17.9237),
        "ATH": CLLocationCoordinate2D(latitude: 37.9364,  longitude: 23.9445),
        "BCN": CLLocationCoordinate2D(latitude: 41.2974,  longitude: 2.0833),
        "BER": CLLocationCoordinate2D(latitude: 52.3667,  longitude: 13.5033),
        "CDG": CLLocationCoordinate2D(latitude: 49.0097,  longitude: 2.5479),
        "CPH": CLLocationCoordinate2D(latitude: 55.6181,  longitude: 12.6561),
        "DUB": CLLocationCoordinate2D(latitude: 53.4264,  longitude: -6.2499),
        "FCO": CLLocationCoordinate2D(latitude: 41.7999,  longitude: 12.2462),
        "FRA": CLLocationCoordinate2D(latitude: 50.0379,  longitude: 8.5622),
        "HEL": CLLocationCoordinate2D(latitude: 60.3172,  longitude: 24.9633),
        "IST": CLLocationCoordinate2D(latitude: 41.2753,  longitude: 28.7519),
        "LGW": CLLocationCoordinate2D(latitude: 51.1537,  longitude: -0.1821),
        "LHR": CLLocationCoordinate2D(latitude: 51.4700,  longitude: -0.4543),
        "LIS": CLLocationCoordinate2D(latitude: 38.7742,  longitude: -9.1342),
        "MAD": CLLocationCoordinate2D(latitude: 40.4936,  longitude: -3.5668),
        "MUC": CLLocationCoordinate2D(latitude: 48.3538,  longitude: 11.7861),
        "MXP": CLLocationCoordinate2D(latitude: 45.6306,  longitude: 8.7281),
        "ORY": CLLocationCoordinate2D(latitude: 48.7233,  longitude: 2.3794),
        "OSL": CLLocationCoordinate2D(latitude: 60.1976,  longitude: 11.1004),
        "VIE": CLLocationCoordinate2D(latitude: 48.1103,  longitude: 16.5697),
        "ZRH": CLLocationCoordinate2D(latitude: 47.4647,  longitude: 8.5492),

        // ── Middle East & Africa ──────────────────────────────────────────
        "AUH": CLLocationCoordinate2D(latitude: 24.4441,  longitude: 54.6510),
        "CAI": CLLocationCoordinate2D(latitude: 30.1219,  longitude: 31.4056),
        "CPT": CLLocationCoordinate2D(latitude: -33.9648, longitude: 18.6017),
        "DOH": CLLocationCoordinate2D(latitude: 25.2731,  longitude: 51.6080),
        "DXB": CLLocationCoordinate2D(latitude: 25.2528,  longitude: 55.3644),
        "JNB": CLLocationCoordinate2D(latitude: -26.1392, longitude: 28.2460),

        // ── Asia & Pacific ────────────────────────────────────────────────
        "BKK": CLLocationCoordinate2D(latitude: 13.6900,  longitude: 100.7501),
        "CAN": CLLocationCoordinate2D(latitude: 23.3924,  longitude: 113.2988),
        "DEL": CLLocationCoordinate2D(latitude: 28.5562,  longitude: 77.1000),
        "HAN": CLLocationCoordinate2D(latitude: 21.2187,  longitude: 105.8042),
        "HKG": CLLocationCoordinate2D(latitude: 22.3080,  longitude: 113.9185),
        "HND": CLLocationCoordinate2D(latitude: 35.5494,  longitude: 139.7798),
        "ICN": CLLocationCoordinate2D(latitude: 37.4602,  longitude: 126.4407),
        "KIX": CLLocationCoordinate2D(latitude: 34.4347,  longitude: 135.2440),
        "KUL": CLLocationCoordinate2D(latitude: 2.7456,   longitude: 101.7099),
        "MNL": CLLocationCoordinate2D(latitude: 14.5086,  longitude: 121.0194),
        "NRT": CLLocationCoordinate2D(latitude: 35.7720,  longitude: 140.3929),
        "PEK": CLLocationCoordinate2D(latitude: 40.0801,  longitude: 116.5846),
        "PVG": CLLocationCoordinate2D(latitude: 31.1443,  longitude: 121.8083),
        "SGN": CLLocationCoordinate2D(latitude: 10.8188,  longitude: 106.6520),
        "SIN": CLLocationCoordinate2D(latitude: 1.3644,   longitude: 103.9915),
        "TPE": CLLocationCoordinate2D(latitude: 25.0797,  longitude: 121.2342),
        "BOM": CLLocationCoordinate2D(latitude: 19.0896,  longitude: 72.8656),

        // ── Oceania ───────────────────────────────────────────────────────
        "AKL": CLLocationCoordinate2D(latitude: -37.0082, longitude: 174.7850),
        "BNE": CLLocationCoordinate2D(latitude: -27.3838, longitude: 153.1180),
        "MEL": CLLocationCoordinate2D(latitude: -37.6733, longitude: 144.8430),
        "PER": CLLocationCoordinate2D(latitude: -31.9402, longitude: 115.9667),
        "SYD": CLLocationCoordinate2D(latitude: -33.9399, longitude: 151.1753)
    ]
}
