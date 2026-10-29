import SwiftUI
import CoreLocation

// MARK: - Badge de ligne aux couleurs officielles

struct LineBadge: View {
    let line: Line?
    let fallbackId: String
    var size: CGFloat = 26

    init(line: Line?, fallbackId: String = "?", size: CGFloat = 26) {
        self.line = line
        self.fallbackId = fallbackId
        self.size = size
    }

    private var label: String { line?.shortName ?? fallbackId }
    private var background: Color { Color(hex: line?.background) ?? .gray }
    private var foreground: Color { Color(hex: line?.foreground) ?? .white }
    private var isRound: Bool { line?.kind == .metro || line?.kind == .rer }

    var body: some View {
        Text(label)
            .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(foreground)
            .padding(.horizontal, isRound ? 0 : size * 0.22)
            .frame(minWidth: size, minHeight: size)
            .frame(width: isRound ? size : nil, height: size)
            .background {
                if isRound {
                    Circle().fill(background)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(background)
                }
            }
            .accessibilityLabel(Text("Ligne \(label)"))
    }
}

/// Rangée de badges (avec repli « +N »).
struct LineBadgeRow: View {
    let lines: [Line]
    var max: Int = 8
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 4) {
            ForEach(lines.prefix(max)) { line in
                LineBadge(line: line, size: size)
            }
            if lines.count > max {
                Text("+\(lines.count - max)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Arrêt

struct StopRow: View {
    @Environment(StopStore.self) private var store
    let stop: Stop
    var distance: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(stop.name)
                    .font(.headline)
                Spacer()
                if let distance {
                    Text(Format.distance(distance))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(stop.city)
                .font(.caption)
                .foregroundStyle(.secondary)
            LineBadgeRow(lines: store.lines(for: stop))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Passages

struct DepartureGroupRow: View {
    @Environment(StopStore.self) private var store
    let group: DepartureGroup

    var body: some View {
        HStack(spacing: 12) {
            LineBadge(line: store.lineById[group.lineId], fallbackId: group.lineId, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.destination)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                if let platform = group.departures.first?.platform, !platform.isEmpty {
                    Text("Quai \(platform)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 10)) { context in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    ForEach(Array(group.departures.enumerated()), id: \.element.id) { index, departure in
                        WaitTime(departure: departure, now: context.date, primary: index == 0)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct WaitTime: View {
    let departure: Departure
    let now: Date
    let primary: Bool

    private var minutes: Int { Int(departure.date.timeIntervalSince(now) / 60) }

    var body: some View {
        Group {
            if departure.atStop || minutes <= 0 {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .symbolEffect(.pulse)
                    .foregroundStyle(.green)
                    .accessibilityLabel("À l'approche")
            } else if minutes >= 60 {
                Text(departure.date, format: .dateTime.hour().minute())
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(minutes)")
                    Text("min").font(.caption2)
                }
            }
        }
        .font(primary ? Font.title3.weight(.bold).monospacedDigit() : Font.subheadline.monospacedDigit())
        .foregroundStyle(primary ? Color.primary : Color.secondary)
    }
}

/// Section de liste avec les passages en direct d'un arrêt.
struct LiveDeparturesSection<Header: View>: View {
    @Environment(StopStore.self) private var store
    @AppStorage("primApiKey") private var apiKey = ""
    let stop: Stop
    var limit: Int? = nil
    @ViewBuilder var header: () -> Header

    @State private var loader = DeparturesLoader()

    var body: some View {
        Section {
            content
        } header: {
            header()
        } footer: {
            if let last = loader.lastUpdate {
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    Text("Temps réel · mis à jour \(last, format: .relative(presentation: .named))")
                }
            }
        }
        .task(id: stop.ref + apiKey) {
            await loader.run(stop: stop, apiKey: apiKey)
        }
    }

    @ViewBuilder
    private var content: some View {
        let groups = limit.map { Array(loader.groups.prefix($0)) } ?? loader.groups
        if let error = loader.errorMessage, loader.groups.isEmpty {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
        } else if groups.isEmpty {
            if loader.isLoading || loader.lastUpdate == nil {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                Text("Aucun passage prévu pour le moment")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(groups) { group in
                DepartureGroupRow(group: group)
            }
        }
    }
}
