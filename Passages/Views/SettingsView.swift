import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("primApiKey") private var apiKey = ""
    var isOnboarding = false

    @State private var draft = ""
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle, testing, ok(Int), failed(String)
    }

    /// Zone d'arrêt de l'exemple de la doc IDFM : sert à tester la clé.
    private let testRef = "STIF:StopArea:SP:42587:"

    var body: some View {
        Form {
            if isOnboarding {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "tram.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.tint)
                        Text("Bienvenue")
                            .font(.largeTitle.bold())
                        Text("Pour afficher les passages en temps réel, l'appli utilise l'API officielle d'Île-de-France Mobilités. Elle est gratuite : il suffit de créer un compte et de copier ta clé ici.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }

            Section {
                TextField("Colle ta clé API ici", text: $draft, axis: .vertical)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text("Enregistrer et tester")
                        Spacer()
                        switch testState {
                        case .idle: EmptyView()
                        case .testing: ProgressView()
                        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        }
                    }
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testState == .testing)
            } header: {
                Text("Clé API PRIM")
            } footer: {
                switch testState {
                case .ok: Text("Clé valide ✓ Les passages temps réel sont activés.")
                case .failed(let message): Text(message).foregroundStyle(.red)
                default: Text("La clé reste uniquement sur ton iPhone.")
                }
            }

            Section("Obtenir une clé (2 min)") {
                Link(destination: URL(string: "https://prim.iledefrance-mobilites.fr/fr")!) {
                    Label("1. Créer un compte sur PRIM", systemImage: "person.crop.circle.badge.plus")
                }
                Label("2. Mon compte → Mes jetons d'authentification → Générer", systemImage: "key.fill")
                Label("3. Copier la clé et la coller ci-dessus", systemImage: "doc.on.clipboard")
            }

            Section("Données") {
                Text("Horaires temps réel et référentiel des arrêts : Île-de-France Mobilités (PRIM / open data, licence ODbL).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(isOnboarding ? "" : "Réglages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") { dismiss() }
                    .disabled(apiKey.isEmpty)
            }
        }
        .onAppear { draft = apiKey }
    }

    @MainActor
    private func save() async {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        testState = .testing
        do {
            let departures = try await PrimClient(apiKey: key).departures(monitoringRef: testRef)
            apiKey = key
            testState = .ok(departures.count)
            if isOnboarding {
                try? await Task.sleep(nanoseconds: 800_000_000)
                dismiss()
            }
        } catch PrimError.invalidKey {
            testState = .failed("Clé refusée par IDFM. Vérifie qu'elle est bien copiée en entier (une nouvelle clé peut mettre quelques minutes à s'activer).")
        } catch {
            // Erreur réseau ou autre : on enregistre quand même la clé.
            apiKey = key
            testState = .failed("Clé enregistrée, mais le test a échoué : \(error.localizedDescription)")
        }
    }
}
