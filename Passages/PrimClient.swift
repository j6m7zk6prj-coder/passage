import Foundation

enum PrimError: LocalizedError {
    case missingKey
    case invalidKey
    case quota
    case http(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Ajoute ta clé API PRIM dans les réglages."
        case .invalidKey: return "Clé API refusée. Vérifie-la dans les réglages."
        case .quota: return "Trop de requêtes, réessaie dans un instant."
        case .http(let code): return "Le serveur IDFM a répondu \(code)."
        case .badResponse: return "Réponse inattendue du serveur IDFM."
        }
    }
}

/// Client de l'API « Prochains passages (requête unitaire) » d'Île-de-France Mobilités (PRIM).
struct PrimClient {
    static let endpoint = URL(string: "https://prim.iledefrance-mobilites.fr/marketplace/stop-monitoring")!

    let apiKey: String

    func departures(monitoringRef: String) async throws -> [Departure] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw PrimError.missingKey }

        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "MonitoringRef", value: monitoringRef)]
        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PrimError.badResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw PrimError.invalidKey
        case 429: throw PrimError.quota
        default:
            // L'API renvoie parfois 400 pour un arrêt sans passage : on traite comme "aucun passage".
            if http.statusCode == 400 || http.statusCode == 404 { return [] }
            throw PrimError.http(http.statusCode)
        }
        return try Self.parse(data)
    }

    // MARK: - Parsing SIRI Lite (JSON)

    static func parse(_ data: Data) throws -> [Departure] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let siri = root["Siri"] as? [String: Any],
              let delivery = siri["ServiceDelivery"] as? [String: Any] else {
            throw PrimError.badResponse
        }
        guard let monitoring = (delivery["StopMonitoringDelivery"] as? [[String: Any]])?.first else { return [] }
        let visits = monitoring["MonitoredStopVisit"] as? [[String: Any]] ?? []
        let cutoff = Date().addingTimeInterval(-60)

        var result: [Departure] = []
        for visit in visits {
            guard let journey = visit["MonitoredVehicleJourney"] as? [String: Any],
                  let call = journey["MonitoredCall"] as? [String: Any] else { continue }

            let timeString = text(call["ExpectedDepartureTime"])
                ?? text(call["ExpectedArrivalTime"])
                ?? text(call["AimedDepartureTime"])
                ?? text(call["AimedArrivalTime"])
            guard let timeString, let date = parseDate(timeString), date > cutoff else { continue }

            let lineRef = text(journey["LineRef"]) ?? ""
            let destination = text(call["DestinationDisplay"])
                ?? text(journey["DestinationName"])
                ?? text(journey["DirectionName"])
                ?? "—"

            result.append(Departure(
                lineId: lineId(fromRef: lineRef),
                destination: destination,
                date: date,
                atStop: (call["VehicleAtStop"] as? Bool) ?? false,
                platform: text(call["ArrivalPlatformName"]) ?? text(call["DeparturePlatformName"])
            ))
        }
        return result.sorted { $0.date < $1.date }
    }

    /// "STIF:Line::C01742:" -> "C01742"
    static func lineId(fromRef ref: String) -> String {
        let parts = ref.split(separator: ":", omittingEmptySubsequences: true)
        return parts.last.map(String.init) ?? ref
    }

    /// SIRI enveloppe souvent les valeurs : {"value": "..."} ou [{"value": "..."}].
    static func text(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let d = any as? [String: Any] { return text(d["value"]) }
        if let a = any as? [Any] { return text(a.first) }
        return nil
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? iso.date(from: s)
    }

    /// Regroupe par ligne + destination, garde les 3 prochains passages.
    static func group(_ departures: [Departure]) -> [DepartureGroup] {
        var order: [String] = []
        var groups: [String: DepartureGroup] = [:]
        for d in departures {
            let key = d.lineId + "|" + d.destination
            if groups[key] == nil {
                groups[key] = DepartureGroup(lineId: d.lineId, destination: d.destination, departures: [])
                order.append(key)
            }
            if groups[key]!.departures.count < 3 { groups[key]!.departures.append(d) }
        }
        return order.compactMap { groups[$0] }
    }
}
