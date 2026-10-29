import SwiftUI
import MapKit

struct StopsMapView: View {
    @Environment(StopStore.self) private var store
    @Environment(LocationManager.self) private var location

    @State private var position: MapCameraPosition = .userLocation(fallback: .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
            latitudinalMeters: 2500,
            longitudinalMeters: 2500
        )
    ))
    @State private var visibleStops: [Stop] = []
    @State private var tooFar = false
    @State private var selected: Stop?

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(visibleStops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate, anchor: .center) {
                    StopPin(kind: store.lines(for: stop).first?.kind ?? .bus)
                        .onTapGesture { selected = stop }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            let span = context.region.span
            if span.latitudeDelta > 0.04 {
                tooFar = true
                visibleStops = []
            } else {
                tooFar = false
                visibleStops = store.stops(
                    in: context.region.center,
                    latSpan: span.latitudeDelta,
                    lonSpan: span.longitudeDelta,
                    limit: 200
                )
            }
        }
        .overlay(alignment: .top) {
            if tooFar {
                Text("Zoome pour voir les arrêts")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .onAppear {
            if visibleStops.isEmpty, let here = location.location {
                visibleStops = store.stops(in: here.coordinate, latSpan: 0.015, lonSpan: 0.015, limit: 200)
            }
        }
        .sheet(item: $selected) { stop in
            NavigationStack {
                StopDetailView(stop: stop)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Fermer") { selected = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct StopPin: View {
    let kind: TransportKind

    private var color: Color {
        switch kind {
        case .metro: return .blue
        case .rer, .train: return .purple
        case .tram: return .green
        case .cable: return .orange
        case .bus, .other: return .red
        }
    }

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color.gradient, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2, y: 1)
            .contentShape(Circle())
    }
}
