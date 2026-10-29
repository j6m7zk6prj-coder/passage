import SwiftUI
import CoreLocation

struct NearbyView: View {
    @Environment(StopStore.self) private var store
    @Environment(LocationManager.self) private var location
    @State private var showSettings = false
    @State private var path = NavigationPath()
    /// Position « figée » utilisée pour la liste : on ne recalcule que si on a bougé de plus de 40 m,
    /// pour éviter que la liste saute en permanence.
    @State private var anchor: CLLocation?

    private var nearby: [NearbyStop] {
        guard let anchor else { return [] }
        return store.nearest(to: anchor, limit: 20, within: 1500)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let error = store.loadError {
                    ContentUnavailableView("Données manquantes", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if location.isDenied {
                    ContentUnavailableView {
                        Label("Localisation désactivée", systemImage: "location.slash")
                    } description: {
                        Text("Autorise l'accès à ta position pour voir les arrêts autour de toi.")
                    } actions: {
                        Button("Ouvrir les Réglages") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if anchor == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Recherche de ta position…").foregroundStyle(.secondary)
                    }
                } else if nearby.isEmpty {
                    ContentUnavailableView("Aucun arrêt à proximité", systemImage: "mappin.slash", description: Text("Aucun arrêt IDFM à moins de 1,5 km."))
                } else {
                    list
                }
            }
            .navigationTitle("À proximité")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .navigationDestination(for: Stop.self) { stop in
                StopDetailView(stop: stop)
            }
        }
        .onAppear { location.start(); updateAnchor(location.location) }
        .onChange(of: location.location) { _, newValue in updateAnchor(newValue) }
    }

    private var list: some View {
        let items = nearby
        let live = Array(items.prefix(3))
        let others = Array(items.dropFirst(3))
        return List {
            ForEach(live) { item in
                LiveDeparturesSection(stop: item.stop, limit: 6) {
                    Button {
                        path.append(item.stop)
                    } label: {
                        NearbyHeader(stop: item.stop, distance: item.distance)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !others.isEmpty {
                Section("Autres arrêts proches") {
                    ForEach(others) { item in
                        NavigationLink(value: item.stop) {
                            StopRow(stop: item.stop, distance: item.distance)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            updateAnchor(location.location, force: true)
        }
    }

    private func updateAnchor(_ newLocation: CLLocation?, force: Bool = false) {
        guard let newLocation else { return }
        if force || anchor == nil || newLocation.distance(from: anchor!) > 40 {
            anchor = newLocation
        }
    }
}

private struct NearbyHeader: View {
    @Environment(StopStore.self) private var store
    let stop: Stop
    let distance: Double

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                    Text("\(Format.distance(distance)) · \(Format.walk(distance))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 2)
        .contentShape(Rectangle())
    }
}
