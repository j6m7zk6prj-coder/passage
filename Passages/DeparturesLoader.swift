import Foundation
import Observation

/// Charge et rafraîchit en continu les prochains passages d'un arrêt.
@Observable
final class DeparturesLoader {
    private(set) var groups: [DepartureGroup] = []
    private(set) var lastUpdate: Date?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    @ObservationIgnored private var currentRef: String?

    @MainActor
    func refresh(stop: Stop, apiKey: String) async {
        if currentRef != stop.ref {
            currentRef = stop.ref
            groups = []
            lastUpdate = nil
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let departures = try await PrimClient(apiKey: apiKey).departures(monitoringRef: stop.ref)
            guard currentRef == stop.ref else { return }
            groups = PrimClient.group(departures)
            lastUpdate = Date()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Boucle de rafraîchissement (à lancer dans un `.task`).
    @MainActor
    func run(stop: Stop, apiKey: String, every seconds: Double = 30) async {
        while !Task.isCancelled {
            await refresh(stop: stop, apiKey: apiKey)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }
}
