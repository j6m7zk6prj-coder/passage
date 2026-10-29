import SwiftUI

@main
struct PassagesApp: App {
    @State private var store = StopStore()
    @State private var location = LocationManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(location)
                .onAppear { location.start() }
        }
    }
}

struct RootView: View {
    @AppStorage("primApiKey") private var apiKey = ""
    @State private var showOnboarding = false

    var body: some View {
        TabView {
            NearbyView()
                .tabItem { Label("À proximité", systemImage: "location.fill") }
            FavoritesView()
                .tabItem { Label("Favoris", systemImage: "star.fill") }
            StopsMapView()
                .tabItem { Label("Carte", systemImage: "map.fill") }
            SearchStopsView()
                .tabItem { Label("Rechercher", systemImage: "magnifyingglass") }
        }
        .onAppear {
            if apiKey.trimmingCharacters(in: .whitespaces).isEmpty { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding) {
            NavigationStack { SettingsView(isOnboarding: true) }
                .interactiveDismissDisabled(apiKey.isEmpty)
        }
    }
}
