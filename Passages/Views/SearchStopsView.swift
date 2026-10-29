import SwiftUI

struct SearchStopsView: View {
    @Environment(StopStore.self) private var store
    @Environment(LocationManager.self) private var location
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let results = store.search(query, near: location.location)
                ForEach(results) { stop in
                    NavigationLink(value: stop) {
                        StopRow(stop: stop, distance: location.location?.distance(from: stop.location))
                    }
                }
            }
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Rechercher un arrêt", systemImage: "magnifyingglass", description: Text("Nom d'arrêt, de gare ou de commune."))
                } else if store.search(query, near: nil).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Rechercher")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Châtelet, Gare de Lyon, Nation…")
            .autocorrectionDisabled()
            .navigationDestination(for: Stop.self) { stop in
                StopDetailView(stop: stop)
            }
        }
    }
}
