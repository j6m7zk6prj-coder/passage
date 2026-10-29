import Foundation
import CoreLocation
import Observation
import SwiftUI

@Observable
final class StopStore {
    private(set) var stops: [Stop] = []
    private(set) var lineById: [String: Line] = [:]
    private(set) var loadError: String?
    private(set) var favoriteRefs: [String] = []

    @ObservationIgnored private let favoritesKey = "favoriteStops"
    @ObservationIgnored private var searchIndex: [(key: String, stop: Stop)] = []

    init() {
        favoriteRefs = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        load()
    }

    private func load() {
        let decoder = JSONDecoder()
        do {
            guard let stopsURL = Bundle.main.url(forResource: "stops", withExtension: "json"),
                  let linesURL = Bundle.main.url(forResource: "lines", withExtension: "json") else {
                loadError = "Les données des arrêts sont absentes de l'appli (stops.json / lines.json)."
                return
            }
            stops = try decoder.decode([Stop].self, from: Data(contentsOf: stopsURL))
            let lineList = try decoder.decode([Line].self, from: Data(contentsOf: linesURL))
            lineById = Dictionary(lineList.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            searchIndex = stops.map { (Self.normalize($0.name + " " + $0.city), $0) }
        } catch {
            loadError = "Impossible de lire les arrêts : \(error.localizedDescription)"
        }
    }

    // MARK: - Recherche

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'", with: " ")
    }

    func search(_ query: String, near location: CLLocation?) -> [Stop] {
        let words = Self.normalize(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var result: [Stop] = Array(
            searchIndex.lazy
                .filter { entry in words.allSatisfy { entry.key.contains($0) } }
                .map { $0.stop }
                .prefix(200)
        )
        if let location {
            result.sort { $0.location.distance(from: location) < $1.location.distance(from: location) }
        }
        return Array(result.prefix(60))
    }

    // MARK: - Proximité

    /// Arrêts les plus proches, avec leur distance en mètres.
    func nearest(to location: CLLocation, limit: Int = 20, within radius: Double = 2000) -> [NearbyStop] {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let cosLat = cos(lat * .pi / 180)
        let latDelta = radius / 111_000
        let lonDelta = radius / (111_000 * max(cosLat, 0.1))

        var candidates: [(Stop, Double)] = []
        for stop in stops where abs(stop.lat - lat) < latDelta && abs(stop.lon - lon) < lonDelta {
            let dx = (stop.lon - lon) * 111_000 * cosLat
            let dy = (stop.lat - lat) * 111_000
            let d = (dx * dx + dy * dy).squareRoot()
            if d <= radius { candidates.append((stop, d)) }
        }
        candidates.sort { $0.1 < $1.1 }
        return candidates.prefix(limit).map { NearbyStop(stop: $0.0, distance: $0.1) }
    }

    func stops(in center: CLLocationCoordinate2D, latSpan: Double, lonSpan: Double, limit: Int = 150) -> [Stop] {
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let radius = max(latSpan, lonSpan) * 111_000 / 1.5
        return nearest(to: here, limit: limit, within: max(radius, 300)).map { $0.stop }
    }

    // MARK: - Lignes

    func lines(for stop: Stop) -> [Line] {
        stop.lineIds.compactMap { lineById[$0] }.sorted(by: Self.lineOrder)
    }

    static func lineOrder(_ a: Line, _ b: Line) -> Bool {
        if a.kind != b.kind { return a.kind < b.kind }
        return a.shortName.localizedStandardCompare(b.shortName) == .orderedAscending
    }

    // MARK: - Favoris

    var favorites: [Stop] {
        let byRef = Dictionary(stops.map { ($0.ref, $0) }, uniquingKeysWith: { a, _ in a })
        return favoriteRefs.compactMap { byRef[$0] }
    }

    func isFavorite(_ stop: Stop) -> Bool { favoriteRefs.contains(stop.ref) }

    func toggleFavorite(_ stop: Stop) {
        if let i = favoriteRefs.firstIndex(of: stop.ref) {
            favoriteRefs.remove(at: i)
        } else {
            favoriteRefs.append(stop.ref)
        }
        UserDefaults.standard.set(favoriteRefs, forKey: favoritesKey)
    }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        favoriteRefs.move(fromOffsets: source, toOffset: destination)
        UserDefaults.standard.set(favoriteRefs, forKey: favoritesKey)
    }

    func removeFavorites(at offsets: IndexSet) {
        favoriteRefs.remove(atOffsets: offsets)
        UserDefaults.standard.set(favoriteRefs, forKey: favoritesKey)
    }
}
