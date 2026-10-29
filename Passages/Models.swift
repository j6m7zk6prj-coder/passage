import Foundation
import CoreLocation
import SwiftUI

/// Un arrêt (zone d'arrêt IDFM). `ref` est l'identifiant à envoyer à l'API PRIM
/// (ex. "STIF:StopArea:SP:43135:").
struct Stop: Identifiable, Codable, Hashable {
    let ref: String
    let name: String
    let city: String
    let lat: Double
    let lon: Double
    let lineIds: [String]

    var id: String { ref }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }

    enum CodingKeys: String, CodingKey {
        case ref = "r", name = "n", city = "c", lat = "la", lon = "lo", lineIds = "l"
    }
}

struct NearbyStop: Identifiable, Hashable {
    let stop: Stop
    let distance: Double
    var id: String { stop.ref }
}

struct Line: Identifiable, Codable, Hashable {
    let id: String          // ex. "C01742"
    let shortName: String   // ex. "T3a", "91", "A"
    let name: String
    let mode: String        // bus, tram, metro, rail, funicular, cableway…
    let background: String?
    let foreground: String?

    enum CodingKeys: String, CodingKey {
        case id = "i", shortName = "s", name = "n", mode = "m", background = "bg", foreground = "fg"
    }

    var kind: TransportKind { TransportKind(rawMode: mode) }
}

enum TransportKind: Int, Comparable {
    case metro = 0, rer, tram, train, cable, bus, other

    init(rawMode: String) {
        switch rawMode.lowercased() {
        case "metro": self = .metro
        case "tram": self = .tram
        case "rer": self = .rer
        case "rail": self = .train
        case "funicular", "cableway": self = .cable
        case "bus", "coach": self = .bus
        default: self = .other
        }
    }

    var symbol: String {
        switch self {
        case .metro: return "tram.fill.tunnel"
        case .tram: return "tram.fill"
        case .rer, .train: return "train.side.front.car"
        case .cable: return "cablecar.fill"
        case .bus, .other: return "bus.fill"
        }
    }

    static func < (lhs: TransportKind, rhs: TransportKind) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct Departure: Identifiable, Hashable {
    let id = UUID()
    let lineId: String
    let destination: String
    let date: Date
    let atStop: Bool
    let platform: String?
}

/// Passages regroupés par ligne + destination.
struct DepartureGroup: Identifiable, Hashable {
    let lineId: String
    let destination: String
    var departures: [Departure]

    var id: String { lineId + "|" + destination }
}

extension Color {
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

enum Format {
    static func distance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
        return String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",")
    }

    /// Temps à pied approximatif (5 km/h).
    static func walk(_ meters: Double) -> String {
        let minutes = max(1, Int((meters / 83).rounded()))
        return "\(minutes) min à pied"
    }
}
