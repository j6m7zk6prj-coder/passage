import Foundation
import MapKit
import Observation

/// Un point de départ ou d'arrivée.
struct RoutePoint: Identifiable, Hashable {
    var id: String
    var name: String
    var subtitle: String?
    var latitude: Double
    var longitude: Double
    var isCurrentLocation = false

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    static func current(_ loc: CLLocation) -> RoutePoint {
        RoutePoint(id: "me", name: "Ma position", latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, isCurrentLocation: true)
    }

    static func stop(_ s: Stop) -> RoutePoint {
        RoutePoint(id: "stop-" + s.ref, name: s.name, subtitle: s.city, latitude: s.lat, longitude: s.lon)
    }

    var mapItem: MKMapItem {
        if isCurrentLocation { return MKMapItem.forCurrentLocation() }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        return item
    }
}

/// Saisie semi-automatique d'adresses et de lieux (comme dans Plans), centrée sur l'Île-de-France.
@MainActor
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    private(set) var query = ""

    func update(_ text: String) {
        query = text
        if text.trimmingCharacters(in: .whitespaces).isEmpty { results = [] } else { completer.queryFragment = text }
    }

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
            latitudinalMeters: 90_000, longitudinalMeters: 90_000
        )
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results
        Task { @MainActor in self.results = Array(found.prefix(12)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    /// Coordonnées d'une suggestion.
    func resolve(_ completion: MKLocalSearchCompletion) async -> RoutePoint? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let c = item.placemark.coordinate
        return RoutePoint(id: "place-\(c.latitude),\(c.longitude)", name: completion.title,
                          subtitle: completion.subtitle.isEmpty ? nil : completion.subtitle,
                          latitude: c.latitude, longitude: c.longitude)
    }
}

/// Lieux récents, pour ne pas les retaper.
enum RecentPlaces {
    private static let key = "recentPlaces"

    struct Saved: Codable { let name: String; let subtitle: String?; let lat: Double; let lon: Double }

    static func load() -> [RoutePoint] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Saved].self, from: data) else { return [] }
        return list.map { RoutePoint(id: "recent-\($0.lat),\($0.lon)", name: $0.name, subtitle: $0.subtitle, latitude: $0.lat, longitude: $0.lon) }
    }

    static func add(_ p: RoutePoint) {
        guard !p.isCurrentLocation else { return }
        var list = load().filter { $0.name != p.name }
        list.insert(p, at: 0)
        let saved = list.prefix(8).map { Saved(name: $0.name, subtitle: $0.subtitle, lat: $0.latitude, lon: $0.longitude) }
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(saved)), forKey: key)
    }
}
