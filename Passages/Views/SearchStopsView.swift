import SwiftUI
import MapKit

struct SearchStopsView: View {
    @Environment(StopStore.self) private var store
    @Environment(LocationManager.self) private var location
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let lines = store.searchLines(query)
                let stops = store.search(query, near: location.location)
                if !lines.isEmpty {
                    Section("Lignes") {
                        ForEach(lines) { line in
                            NavigationLink(value: line) { LineRow(line: line) }
                        }
                    }
                }
                if !stops.isEmpty {
                    Section("Arrêts") {
                        ForEach(stops) { stop in
                            NavigationLink(value: stop) {
                                StopRow(stop: stop, distance: location.location?.distance(from: stop.location))
                            }
                        }
                    }
                }
            }
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Rechercher", systemImage: "magnifyingglass",
                                           description: Text("Une ligne (T8, 91, RER A, métro 14) ou un arrêt, une gare, une commune."))
                } else if store.search(query, near: nil).isEmpty && store.searchLines(query).isEmpty {
                    ContentUnavailableView("Aucun résultat pour « \(query) »", systemImage: "magnifyingglass",
                                           description: Text("Vérifie l'orthographe ou essaie un autre nom."))
                }
            }
            .navigationTitle("Rechercher")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ligne, arrêt, gare…")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationDestination(for: Stop.self) { stop in
                StopDetailView(stop: stop)
            }
            .navigationDestination(for: Line.self) { line in
                LineDetailView(line: line)
            }
        }
    }
}

struct LineRow: View {
    let line: Line

    private var modeLabel: String {
        switch line.kind {
        case .metro: return "Métro"
        case .rer: return "RER"
        case .tram: return "Tramway"
        case .train: return "Train"
        case .cable: return "Téléphérique / funiculaire"
        case .bus: return "Bus"
        case .other: return "Ligne"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            LineBadge(line: line, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name == line.shortName ? "\(modeLabel) \(line.shortName)" : line.name)
                    .font(.headline)
                    .lineLimit(2)
                Label(modeLabel, systemImage: line.kind.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Tous les arrêts d'une ligne, avec la carte.
struct LineDetailView: View {
    @Environment(StopStore.self) private var store
    @Environment(LocationManager.self) private var location
    let line: Line
    @State private var filter = ""

    var body: some View {
        let all = store.stops(forLine: line.id, near: location.location)
        let shown = filter.isEmpty ? all : all.filter { StopStore.normalize($0.name + " " + $0.city).contains(StopStore.normalize(filter)) }
        List {
            Section {
                Map(initialPosition: .automatic) {
                    UserAnnotation()
                    ForEach(all) { stop in
                        Annotation(stop.name, coordinate: stop.coordinate) {
                            Circle()
                                .fill(Color(hex: line.background) ?? .blue)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .frame(height: 220)
                .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(shown) { stop in
                    NavigationLink(value: stop) {
                        StopRow(stop: stop, distance: location.location?.distance(from: stop.location))
                    }
                }
            } header: {
                Text(location.location == nil ? "\(all.count) arrêts" : "\(all.count) arrêts · du plus proche au plus loin")
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $filter, prompt: "Filtrer les arrêts")
        .navigationTitle(line.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    LineBadge(line: line, size: 26)
                    Text(line.name == line.shortName ? "" : line.name)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
        }
    }
}
