import SwiftUI

struct FavoritesView: View {
    @Environment(StopStore.self) private var store
    @State private var path = NavigationPath()
    @State private var isEditing = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.favorites.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun favori", systemImage: "star")
                    } description: {
                        Text("Ouvre un arrêt et touche l'étoile pour le retrouver ici avec ses passages en direct.")
                    }
                } else if isEditing {
                    List {
                        ForEach(store.favorites) { stop in
                            StopRow(stop: stop)
                        }
                        .onMove { store.moveFavorites(from: $0, to: $1) }
                        .onDelete { store.removeFavorites(at: $0) }
                    }
                    .environment(\.editMode, .constant(.active))
                } else {
                    List {
                        ForEach(store.favorites) { stop in
                            LiveDeparturesSection(stop: stop, limit: 5) {
                                Button {
                                    path.append(stop)
                                } label: {
                                    HStack {
                                        Text(stop.name)
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(.primary)
                                            .textCase(nil)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Favoris")
            .toolbar {
                if !store.favorites.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isEditing ? "OK" : "Modifier") {
                            withAnimation { isEditing.toggle() }
                        }
                    }
                }
            }
            .navigationDestination(for: Stop.self) { stop in
                StopDetailView(stop: stop)
            }
        }
    }
}
