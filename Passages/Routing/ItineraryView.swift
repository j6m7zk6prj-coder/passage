import SwiftUI
import MapKit

enum TravelMode: Int, CaseIterable, Identifiable {
    case transit, walk, car
    var id: Int { rawValue }
    var label: String { ["Transports", "À pied", "Voiture"][rawValue] }
    var symbol: String { ["tram.fill", "figure.walk", "car.fill"][rawValue] }
}

enum WhenMode: Int { case now, leaveAt, arriveBy }

// MARK: - Écran principal

struct ItineraryView: View {
    @Environment(StopStore.self) private var store
    @Environment(LocationManager.self) private var location
    @AppStorage("primApiKey") private var apiKey = ""

    @State private var from: RoutePoint?
    @State private var to: RoutePoint?
    @State private var mode: TravelMode = .transit
    @State private var when: WhenMode = .now
    @State private var date = Date()
    @State private var editing: Field?
    @State private var showTime = false

    @State private var journeys: [Journey] = []
    @State private var routes: [MKRoute] = []
    @State private var loading = false
    @State private var error: String?

    enum Field: String, Identifiable { case from, to; var id: String { rawValue } }

    private var origin: RoutePoint? { from ?? location.location.map(RoutePoint.current) }

    private var searchKey: String {
        [origin?.id ?? "", "\(origin?.latitude ?? 0)", to?.id ?? "", "\(mode.rawValue)", "\(when.rawValue)", "\(Int(date.timeIntervalSince1970 / 60))"].joined(separator: "|")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    pointRow(icon: "circle.circle.fill", tint: .blue, title: origin?.name ?? "Départ", placeholder: origin == nil) { editing = .from }
                    HStack {
                        pointRow(icon: "mappin.circle.fill", tint: .red, title: to?.name ?? "Où vas-tu ?", placeholder: to == nil) { editing = .to }
                        Button {
                            let o = origin
                            from = (to?.isCurrentLocation ?? false) ? nil : to
                            to = o
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.body.weight(.semibold))
                                .padding(8)
                                .background(Color(.tertiarySystemFill), in: Circle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(to == nil)
                        .accessibilityLabel("Inverser départ et arrivée")
                    }
                }

                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(TravelMode.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    if mode == .transit {
                        Button { showTime = true } label: {
                            HStack {
                                Image(systemName: "clock")
                                Text(whenLabel)
                                Spacer()
                                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if to == nil {
                    Section {
                        ContentUnavailableView("Où vas-tu ?", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                               description: Text("Choisis une destination : adresse, lieu, gare ou arrêt."))
                    }
                    .listRowBackground(Color.clear)
                } else if loading {
                    HStack { Spacer(); ProgressView("Calcul de l'itinéraire…"); Spacer() }
                        .listRowBackground(Color.clear)
                } else if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                } else if mode == .transit {
                    Section("Trajets") {
                        ForEach(journeys) { j in
                            NavigationLink(value: j) { JourneyRow(journey: j) }
                        }
                    }
                } else {
                    Section(mode == .walk ? "À pied" : "En voiture") {
                        ForEach(Array(routes.enumerated()), id: \.offset) { i, r in
                            NavigationLink(value: RouteChoice(index: i)) { RouteRow(route: r, mode: mode, best: i == 0) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Itinéraire")
            .navigationDestination(for: Journey.self) { j in
                JourneyDetailView(journey: j, origin: origin, destination: to)
            }
            .navigationDestination(for: RouteChoice.self) { c in
                if c.index < routes.count, let to {
                    RouteDetailView(route: routes[c.index], mode: mode, from: origin, to: to)
                }
            }
            .sheet(item: $editing) { field in
                PlacePickerSheet(title: field == .from ? "Départ" : "Arrivée", allowCurrent: true) { point in
                    if field == .from { from = point.isCurrentLocation ? nil : point } else { to = point }
                    RecentPlaces.add(point)
                }
            }
            .sheet(isPresented: $showTime) {
                TimePickerSheet(when: $when, date: $date)
            }
            .refreshable { await search() }
            .task(id: searchKey) { await search() }
        }
    }

    private var whenLabel: String {
        switch when {
        case .now: return "Partir maintenant"
        case .leaveAt: return "Partir à " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        case .arriveBy: return "Arriver avant " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
    }

    private func pointRow(icon: String, tint: Color, title: String, placeholder: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(tint).font(.title3)
                Text(title)
                    .foregroundStyle(placeholder ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func search() async {
        guard let origin, let to else { journeys = []; routes = []; return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            switch mode {
            case .transit:
                guard !apiKey.isEmpty else { throw PrimError.missingKey }
                let at: Date? = when == .now ? nil : date
                journeys = try await NavitiaClient(apiKey: apiKey).journeys(
                    from: origin.coordinate, to: to.coordinate, at: at, mode: when == .arriveBy ? .arrival : .departure)
                if journeys.isEmpty { error = "Aucun trajet trouvé." }
            case .walk, .car:
                let request = MKDirections.Request()
                request.source = origin.mapItem
                request.destination = to.mapItem
                request.transportType = mode == .walk ? .walking : .automobile
                request.requestsAlternateRoutes = true
                if mode == .car, when != .now { request.departureDate = date }
                let response = try await MKDirections(request: request).calculate()
                routes = response.routes.sorted { $0.expectedTravelTime < $1.expectedTravelTime }
            }
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RouteChoice: Hashable { let index: Int }

// MARK: - Résumé d'un trajet en transports

struct JourneyRow: View {
    @Environment(StopStore.self) private var store
    let journey: Journey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(journey.departure.formatted(.dateTime.hour().minute())) → \(journey.arrival.formatted(.dateTime.hour().minute()))")
                    .font(.headline.monospacedDigit())
                Spacer()
                Text(TripText.text(journey.duration))
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            JourneyChain(journey: journey)
            HStack(spacing: 10) {
                Label("\(TripText.text(journey.walkingSeconds)) à pied", systemImage: "figure.walk")
                let t = journey.nb_transfers ?? 0
                Text(t == 0 ? "Direct" : "\(t) correspondance\(t > 1 ? "s" : "")")
                if journey.transitSections.contains(where: { $0.delayMinutes > 0 }) || journey.isDisrupted {
                    Label("Perturbé", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// « 🚶 4 › [T3a] › [91] › 🚶 2 »
struct JourneyChain: View {
    @Environment(StopStore.self) private var store
    let journey: Journey

    var body: some View {
        let parts = journey.summarySections
        HStack(spacing: 5) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, s in
                if i > 0 { Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary) }
                if s.type == "public_transport" {
                    SectionBadge(section: s, size: 24)
                } else {
                    HStack(spacing: 1) {
                        Image(systemName: "figure.walk")
                        Text("\(max(1, (s.duration ?? 0) / 60))").font(.caption2.weight(.semibold))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Badge d'une ligne dans un trajet (couleurs officielles quand on les connaît).
struct SectionBadge: View {
    @Environment(StopStore.self) private var store
    let section: JourneySection
    var size: CGFloat = 26

    var body: some View {
        if let id = section.lineId, let line = store.lineById[id] {
            LineBadge(line: line, size: size)
        } else {
            let info = section.display_informations
            let fake = Line(id: section.lineId ?? "?", shortName: info?.code ?? info?.label ?? "?", name: info?.name ?? "",
                            mode: section.modeKind == .metro ? "metro" : (section.modeKind == .rer ? "rer" : (section.modeKind == .tram ? "tram" : "bus")),
                            background: info?.color, foreground: info?.text_color)
            LineBadge(line: fake, size: size)
        }
    }
}

enum TripText {
    static func text(_ seconds: Int) -> String {
        let m = max(1, Int((Double(seconds) / 60).rounded()))
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(String(format: "%02d", m % 60))"
    }

    static func distance(_ meters: CLLocationDistance) -> String {
        meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Détail d'un trajet en transports

struct JourneyDetailView: View {
    @Environment(StopStore.self) private var store
    let journey: Journey
    let origin: RoutePoint?
    let destination: RoutePoint?

    var body: some View {
        List {
            Section {
                Map(initialPosition: .automatic) {
                    ForEach(Array(journey.sections.enumerated()), id: \.offset) { _, s in
                        let coords = s.coordinates
                        if coords.count > 1 {
                            if s.type == "public_transport" {
                                MapPolyline(coordinates: coords)
                                    .stroke(color(for: s), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                            } else {
                                MapPolyline(coordinates: coords)
                                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 7]))
                            }
                        }
                    }
                    if let origin { Marker(origin.name, systemImage: "circle.fill", coordinate: origin.coordinate).tint(.blue) }
                    if let destination { Marker(destination.name, systemImage: "mappin", coordinate: destination.coordinate).tint(.red) }
                    UserAnnotation()
                }
                .frame(height: 260)
                .listRowInsets(EdgeInsets())

                HStack {
                    VStack(alignment: .leading) {
                        Text(TripText.text(journey.duration)).font(.title2.bold())
                        Text("\(journey.departure.formatted(.dateTime.hour().minute())) → \(journey.arrival.formatted(.dateTime.hour().minute()))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    JourneyChain(journey: journey)
                }
            }

            Section("Étapes") {
                ForEach(Array(journey.sections.enumerated()), id: \.offset) { _, s in
                    if s.type == "public_transport" {
                        TransitStepView(section: s)
                    } else if s.isWalk && (s.duration ?? 0) > 0 {
                        WalkStepView(section: s)
                    } else if s.type == "waiting", let d = s.duration, d >= 60 {
                        Label("Attente · \(TripText.text(d))", systemImage: "hourglass")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Label {
                    Text("Arrivée à \(journey.arrival.formatted(.dateTime.hour().minute())) · \(destination?.name ?? "destination")")
                } icon: {
                    Image(systemName: "flag.checkered").foregroundStyle(.red)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Trajet")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func color(for s: JourneySection) -> Color {
        if let id = s.lineId, let line = store.lineById[id], let c = Color(hex: line.background) { return c }
        return Color(hex: s.display_informations?.color) ?? .blue
    }
}

struct WalkStepView: View {
    let section: JourneySection

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("À pied · \(TripText.text(section.duration ?? 0))")
                    .font(.subheadline.weight(.semibold))
                if let name = section.to?.name {
                    Text("Jusqu'à \(name)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct TransitStepView: View {
    let section: JourneySection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SectionBadge(section: section, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(section.modeLabel) direction \(section.display_informations?.direction ?? section.display_informations?.headsign ?? "—")")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text("\(section.intermediateStops) arrêt\(section.intermediateStops > 1 ? "s" : "") · \(TripText.text(section.duration ?? 0))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                stopLine(symbol: "arrow.up.circle.fill", tint: .green, label: "Monter à", name: section.from?.name, date: section.departure, delay: section.delayMinutes)
                stopLine(symbol: "arrow.down.circle.fill", tint: .red, label: "Descendre à", name: section.to?.name, date: section.arrival, delay: 0)
            }
            .padding(.leading, 44)
            if let ref = section.boardingMonitoringRef {
                LiveLineDepartures(monitoringRef: ref, lineId: section.lineId)
                    .padding(.leading, 44)
            }
        }
        .padding(.vertical, 4)
    }

    private func stopLine(symbol: String, tint: Color, label: String, name: String?, date: Date?, delay: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint).font(.caption)
            Text("\(label) ") + Text(name ?? "—").bold()
            Spacer(minLength: 4)
            if let date {
                Text(date.formatted(.dateTime.hour().minute())).monospacedDigit()
                if delay > 0 { Text("+\(delay)").foregroundStyle(.orange).font(.caption.bold()) }
            }
        }
        .font(.subheadline)
    }
}

/// Prochains passages en temps réel de la ligne, à l'arrêt où l'on monte.
struct LiveLineDepartures: View {
    @AppStorage("primApiKey") private var apiKey = ""
    let monitoringRef: String
    let lineId: String?
    @State private var departures: [Departure] = []
    @State private var loaded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { ctx in
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                    .symbolEffect(.pulse)
                if !loaded {
                    Text("Temps réel…").foregroundStyle(.secondary)
                } else if departures.isEmpty {
                    Text("Pas d'info temps réel à cet arrêt").foregroundStyle(.secondary)
                } else {
                    Text("Prochains :").foregroundStyle(.secondary)
                    ForEach(departures.prefix(3)) { d in
                        let m = Int(d.date.timeIntervalSince(ctx.date) / 60)
                        Text(m <= 0 ? "à l'approche" : "\(m) min")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                }
            }
            .font(.caption)
        }
        .task(id: monitoringRef) {
            while !Task.isCancelled {
                if let all = try? await PrimClient(apiKey: apiKey).departures(monitoringRef: monitoringRef) {
                    departures = lineId.map { id in all.filter { $0.lineId == id } } ?? all
                    if departures.isEmpty { departures = all.count <= 3 ? all : [] }
                }
                loaded = true
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
}

// MARK: - À pied / en voiture (Plans d'Apple)

struct RouteRow: View {
    let route: MKRoute
    let mode: TravelMode
    let best: Bool

    var body: some View {
        HStack {
            Image(systemName: mode.symbol)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(TripText.text(Int(route.expectedTravelTime)))
                    .font(.title3.bold())
                Text("\(TripText.distance(route.distance))\(route.name.isEmpty ? "" : " · via " + route.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Arrivée vers \(Date().addingTimeInterval(route.expectedTravelTime).formatted(.dateTime.hour().minute()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if best {
                Text("Le plus rapide")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RouteDetailView: View {
    let route: MKRoute
    let mode: TravelMode
    let from: RoutePoint?
    let to: RoutePoint

    var body: some View {
        List {
            Section {
                Map(initialPosition: .rect(route.polyline.boundingMapRect.insetBy(dx: -800, dy: -800))) {
                    MapPolyline(route.polyline)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    Marker(to.name, systemImage: "mappin", coordinate: to.coordinate).tint(.red)
                    UserAnnotation()
                }
                .frame(height: 260)
                .listRowInsets(EdgeInsets())
                HStack {
                    VStack(alignment: .leading) {
                        Text(TripText.text(Int(route.expectedTravelTime))).font(.title2.bold())
                        Text(TripText.distance(route.distance)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        MKMapItem.openMaps(with: [from?.mapItem ?? MKMapItem.forCurrentLocation(), to.mapItem], launchOptions: [
                            MKLaunchOptionsDirectionsModeKey: mode == .walk ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDriving
                        ])
                    } label: {
                        Label("Y aller", systemImage: "location.north.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Section("Étapes") {
                ForEach(Array(route.steps.enumerated()), id: \.offset) { _, step in
                    if !step.instructions.isEmpty {
                        HStack(alignment: .top) {
                            Text(step.instructions)
                            Spacer()
                            if step.distance > 0 {
                                Text(TripText.distance(step.distance)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(mode == .walk ? "À pied" : "En voiture")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Choisir un lieu

struct PlacePickerSheet: View {
    @Environment(StopStore.self) private var store
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss
    let title: String
    var allowCurrent = true
    let onPick: (RoutePoint) -> Void

    @State private var search = PlaceSearch()
    @State private var text = ""
    @State private var resolving = false

    var body: some View {
        NavigationStack {
            List {
                if text.isEmpty {
                    if allowCurrent, let loc = location.location {
                        Button { pick(.current(loc)) } label: {
                            Label("Ma position", systemImage: "location.fill")
                        }
                    }
                    let recents = RecentPlaces.load()
                    if !recents.isEmpty {
                        Section("Récents") {
                            ForEach(recents) { p in
                                Button { pick(p) } label: { placeLabel(p.name, p.subtitle, icon: "clock") }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    let favs = store.favorites
                    if !favs.isEmpty {
                        Section("Arrêts favoris") {
                            ForEach(favs) { s in
                                Button { pick(.stop(s)) } label: { placeLabel(s.name, s.city, icon: "star.fill") }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    let stops = Array(store.search(text, near: location.location).prefix(5))
                    if !stops.isEmpty {
                        Section("Arrêts et gares") {
                            ForEach(stops) { s in
                                Button { pick(.stop(s)) } label: {
                                    HStack {
                                        placeLabel(s.name, s.city, icon: "tram.fill")
                                        Spacer()
                                        LineBadgeRow(lines: store.lines(for: s), max: 4, size: 18)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !search.results.isEmpty {
                        Section("Adresses et lieux") {
                            ForEach(search.results, id: \.self) { c in
                                Button {
                                    Task {
                                        resolving = true
                                        if let p = await search.resolve(c) { pick(p) }
                                        resolving = false
                                    }
                                } label: { placeLabel(c.title, c.subtitle, icon: "mappin.circle.fill") }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .overlay { if resolving { ProgressView() } }
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Adresse, lieu, gare, arrêt…")
            .onChange(of: text) { _, t in search.update(t) }
            .autocorrectionDisabled()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
        }
    }

    private func pick(_ p: RoutePoint) {
        onPick(p)
        dismiss()
    }

    private func placeLabel(_ title: String, _ subtitle: String?, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

struct TimePickerSheet: View {
    @Binding var when: WhenMode
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Quand", selection: $when) {
                    Text("Maintenant").tag(WhenMode.now)
                    Text("Partir à").tag(WhenMode.leaveAt)
                    Text("Arriver avant").tag(WhenMode.arriveBy)
                }
                .pickerStyle(.segmented)
                if when != .now {
                    DatePicker("Heure", selection: $date, in: Date().addingTimeInterval(-3600)...)
                        .datePickerStyle(.graphical)
                }
            }
            .navigationTitle("Heure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .environment(\.locale, Locale(identifier: "fr_FR"))
    }
}
