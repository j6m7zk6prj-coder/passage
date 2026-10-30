import Foundation
import CoreLocation

/// Calculateur d'itinéraires d'Île-de-France Mobilités (Navitia, via PRIM), avec le temps réel.
struct NavitiaClient {
    static let base = URL(string: "https://prim.iledefrance-mobilites.fr/marketplace/v2/navitia/")!
    let apiKey: String

    enum TimeMode: String { case departure, arrival }

    func journeys(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, at date: Date?, mode: TimeMode,
                  wheelchair: Bool = false, lessWalking: Bool = false) async throws -> [Journey] {
        var c = URLComponents(url: Self.base.appendingPathComponent("journeys"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "from", value: "\(from.longitude);\(from.latitude)"),
            URLQueryItem(name: "to", value: "\(to.longitude);\(to.latitude)"),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "data_freshness", value: "realtime"),
            URLQueryItem(name: "datetime_represents", value: mode.rawValue),
            URLQueryItem(name: "depth", value: "1")
        ]
        if let date { items.append(URLQueryItem(name: "datetime", value: Self.format(date))) }
        if wheelchair { items.append(URLQueryItem(name: "wheelchair", value: "true")) }
        if lessWalking { items.append(URLQueryItem(name: "traveler_type", value: "slow_walker")) }
        c.queryItems = items

        var request = URLRequest(url: c.url!)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw PrimError.invalidKey }
        if status == 429 { throw PrimError.quota }
        let decoded = try JSONDecoder().decode(JourneysResponse.self, from: data)
        if let error = decoded.error, (decoded.journeys ?? []).isEmpty {
            throw NSError(domain: "Navitia", code: 1, userInfo: [NSLocalizedDescriptionKey: Self.explain(error)])
        }
        return decoded.journeys ?? []
    }

    static func explain(_ e: NavitiaError) -> String {
        switch e.id ?? "" {
        case "no_solution": return "Aucun trajet trouvé à cette heure."
        case "no_origin", "no_origin_nor_destination", "no_destination": return "Départ ou arrivée hors d'Île-de-France."
        case "date_out_of_bounds": return "Date trop lointaine pour les horaires disponibles."
        default: return e.message ?? "Le calculateur IDFM n'a pas pu répondre."
        }
    }

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f
    }()

    static func format(_ d: Date) -> String { formatter.string(from: d) }
    static func parse(_ s: String?) -> Date? { s.flatMap { formatter.date(from: $0) } }
}

// MARK: - Modèles Navitia (champs utiles seulement)

struct JourneysResponse: Decodable {
    let journeys: [Journey]?
    let error: NavitiaError?
}

struct NavitiaError: Decodable {
    let id: String?
    let message: String?
}

struct Journey: Decodable, Identifiable, Hashable {
    let duration: Int
    let nb_transfers: Int?
    let departure_date_time: String
    let arrival_date_time: String
    let sections: [JourneySection]
    let durations: Durations?
    let type: String?
    let status: String?

    var id: String { departure_date_time + arrival_date_time + sections.map { $0.id ?? $0.type }.joined() }
    var departure: Date { NavitiaClient.parse(departure_date_time) ?? .now }
    var arrival: Date { NavitiaClient.parse(arrival_date_time) ?? .now }
    var walkingSeconds: Int { durations?.walking ?? sections.filter { $0.isWalk }.reduce(0) { $0 + ($1.duration ?? 0) } }
    var transitSections: [JourneySection] { sections.filter { $0.type == "public_transport" } }
    /// Sections affichées dans le résumé (on cache les attentes et micro-marches).
    var summarySections: [JourneySection] {
        sections.filter { $0.type == "public_transport" || ($0.isWalk && ($0.duration ?? 0) >= 60) }
    }
    var isDisrupted: Bool { (status ?? "").contains("SIGNIFICANT") || (status ?? "").contains("NO_SERVICE") || (status ?? "").contains("REDUCED") }

    struct Durations: Decodable, Hashable {
        let walking: Int?
        let total: Int?
    }

    static func == (a: Journey, b: Journey) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct JourneySection: Decodable, Hashable {
    let id: String?
    let type: String                // public_transport, street_network, transfer, waiting, crow_fly
    let mode: String?               // walking, bike, car…
    let duration: Int?
    let departure_date_time: String?
    let arrival_date_time: String?
    let base_departure_date_time: String?
    let from: NavPlace?
    let to: NavPlace?
    let display_informations: DisplayInformations?
    let links: [Link]?
    let geojson: GeoJSON?
    let stop_date_times: [StopDateTime]?
    let path: [PathStep]?

    var isWalk: Bool { type == "street_network" && (mode ?? "walking") == "walking" || type == "crow_fly" || type == "transfer" }
    var departure: Date? { NavitiaClient.parse(departure_date_time) }
    var arrival: Date? { NavitiaClient.parse(arrival_date_time) }
    var delayMinutes: Int {
        guard let d = departure, let b = NavitiaClient.parse(base_departure_date_time) else { return 0 }
        return Int(d.timeIntervalSince(b) / 60)
    }
    var lineId: String? {
        links?.first { $0.type == "line" }?.id.map { $0.split(separator: ":").last.map(String.init) ?? $0 }
    }
    var coordinates: [CLLocationCoordinate2D] {
        (geojson?.coordinates ?? []).compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) : nil }
    }
    /// Quai de montée, utilisable avec l'API Prochains passages (STIF:StopPoint:Q:xxx:).
    var boardingMonitoringRef: String? {
        guard let id = from?.stop_point?.id, let last = id.split(separator: ":").last else { return nil }
        return "STIF:StopPoint:Q:\(last):"
    }
    var intermediateStops: Int { max(0, (stop_date_times?.count ?? 0) - 1) }

    struct Link: Decodable, Hashable {
        let type: String?
        let id: String?
    }
    struct GeoJSON: Decodable, Hashable {
        let coordinates: [[Double]]?
    }
    struct StopDateTime: Decodable, Hashable {
        let stop_point: NavStopPoint?
        let departure_date_time: String?
    }
    struct PathStep: Decodable, Hashable {
        let name: String?
        let length: Int?
        let duration: Int?
        let instruction: String?
    }
}

struct NavPlace: Decodable, Hashable {
    let name: String?
    let embedded_type: String?
    let stop_point: NavStopPoint?
    let stop_area: NavStopPoint?
}

struct NavStopPoint: Decodable, Hashable {
    let id: String?
    let name: String?
    let coord: Coord?
}

struct Coord: Decodable, Hashable {
    let lat: String?
    let lon: String?
}

struct DisplayInformations: Decodable, Hashable {
    let code: String?
    let color: String?
    let text_color: String?
    let commercial_mode: String?
    let physical_mode: String?
    let direction: String?
    let headsign: String?
    let label: String?
    let name: String?
    let network: String?
}

extension JourneySection {
    /// Mode lisible : « Métro », « RER », « Tramway », « Bus »…
    var modeLabel: String {
        let m = (display_informations?.commercial_mode ?? display_informations?.physical_mode ?? "").lowercased()
        if m.contains("métro") || m.contains("metro") { return "Métro" }
        if m.contains("rer") { return "RER" }
        if m.contains("tram") { return "Tramway" }
        if m.contains("train") || m.contains("transilien") || m.contains("ter") { return "Train" }
        if m.contains("câble") || m.contains("cable") || m.contains("funi") { return "Câble" }
        return "Bus"
    }

    var modeKind: TransportKind {
        switch modeLabel {
        case "Métro": return .metro
        case "RER": return .rer
        case "Tramway": return .tram
        case "Train": return .train
        case "Câble": return .cable
        default: return .bus
        }
    }
}
