import SwiftUI
import MapKit

struct StopDetailView: View {
    @Environment(StopStore.self) private var store
    @Environment(LocationManager.self) private var location
    let stop: Stop

    var body: some View {
        List {
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: stop.coordinate,
                    latitudinalMeters: 350,
                    longitudinalMeters: 350
                ))) {
                    UserAnnotation()
                    Marker(stop.name, systemImage: "mappin", coordinate: stop.coordinate)
                        .tint(.blue)
                }
                .allowsHitTesting(false)
                .frame(height: 170)
                .listRowInsets(EdgeInsets())

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(stop.city)
                        if let here = location.location {
                            let d = here.distance(from: stop.location)
                            Text("·")
                            Label("\(Format.distance(d)) · \(Format.walk(d))", systemImage: "figure.walk")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    LineBadgeRow(lines: store.lines(for: stop), max: 14, size: 24)
                }
                .padding(.vertical, 4)
            }

            LiveDeparturesSection(stop: stop) {
                Text("Prochains passages")
            }

            Section {
                Button {
                    openInMaps()
                } label: {
                    Label("Itinéraire à pied dans Plans", systemImage: "figure.walk.circle.fill")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(stop.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { store.toggleFavorite(stop) }
                } label: {
                    Image(systemName: store.isFavorite(stop) ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                }
                .sensoryFeedback(.success, trigger: store.isFavorite(stop))
                .accessibilityLabel(store.isFavorite(stop) ? "Retirer des favoris" : "Ajouter aux favoris")
            }
        }
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
        item.name = stop.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
