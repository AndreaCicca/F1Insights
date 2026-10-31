import SwiftUI
import Charts

// MARK: - Driver metadata helpers

extension Collection where Element == DriverMeta {
    func colors(forSelected selected: Set<String>) -> [Color] {
        self.filter { selected.contains($0.id) }
            .sorted { $0.name < $1.name }
            .map { TeamColor.color(for: $0.constructorId) }
    }
}

// MARK: - Shared Lap Series Chart

private struct DriverLapSeriesChart: View {
    let laps: [Lap]
    let results: [RaceResult]
    let loading: Bool
    let loadingLabel: String
    let emptyIcon: String
    let emptySubtitle: String?
    let yAxisLabel: String
    let interpolation: InterpolationMethod
    let yScaleReversed: Bool
    let initialTopCount: Int
    let valueExtractor: (Timing) -> Double?
    let load: () async -> Void

    @State private var selected: Set<String> = []
    @State private var metas: [DriverMeta] = []
    @State private var allPoints: [Point] = []
    @State private var isInitialLoad = true

    struct Point: Identifiable {
        let id: String
        let driverId: String
        let name: String
        let lap: Int
        let value: Double
    }

    private var points: [Point] {
        allPoints.filter { selected.contains($0.driverId) }
    }

    var body: some View {
        let activePoints = points
        VStack(alignment: .leading, spacing: 12) {
            if (loading || isInitialLoad) && laps.isEmpty {
                LoadingView(label: loadingLabel)
            } else if laps.isEmpty {
                MessageView(systemImage: emptyIcon, title: "No lap data", subtitle: emptySubtitle)
            } else {
                DriverPicker(metas: metas, selected: $selected)
                if activePoints.isEmpty {
                    MessageView(
                        systemImage: "hand.tap",
                        title: "Select drivers",
                        subtitle: "Tap driver chips above to plot their data."
                    )
                } else {
                    Chart(activePoints) { p in
                        LineMark(
                            x: .value("Lap", p.lap),
                            y: .value(yAxisLabel, p.value)
                        )
                        .foregroundStyle(by: .value("Driver", p.name))
                        .interpolationMethod(interpolation)
                    }
                    .chartForegroundStyleScale(range: metas.colors(forSelected: selected))
                    .chartXAxisLabel("Lap")
                    .chartYAxisLabel(yAxisLabel)
                    .chartYScale(domain: .automatic(includesZero: false, reversed: yScaleReversed))
                }
            }
        }
        .task {
            rebuildData()
            await load()
            rebuildData()
            isInitialLoad = false
        }
        .onChange(of: laps.count) { _, _ in rebuildData() }
        .onChange(of: results.count) { _, _ in rebuildData() }
    }

    private func rebuildData() {
        var computedMetas = driverMetas(from: results)
        if computedMetas.isEmpty, let firstLap = laps.first {
            computedMetas = firstLap.timings.enumerated().map { idx, t in
                DriverMeta(
                    id: t.driverId,
                    name: t.driverId.capitalized,
                    constructorId: t.driverId,
                    finishPosition: idx + 1
                )
            }
        }
        let lookup = Dictionary(uniqueKeysWithValues: computedMetas.map { ($0.id, $0) })
        var out: [Point] = []
        out.reserveCapacity(laps.count * 20)
        for lap in laps {
            guard let n = Int(lap.number) else { continue }
            for t in lap.timings {
                guard let v = valueExtractor(t) else { continue }
                let name = lookup[t.driverId]?.name ?? t.driverId.capitalized
                out.append(Point(id: "\(t.driverId)-\(n)", driverId: t.driverId, name: name, lap: n, value: v))
            }
        }
        self.metas = computedMetas
        self.allPoints = out
        seedSelection()
    }

    private func seedSelection() {
        guard selected.isEmpty, !metas.isEmpty else { return }
        selected = Set(
            metas.sorted { $0.finishPosition < $1.finishPosition }
                .prefix(initialTopCount)
                .map(\.id)
        )
    }
}

// MARK: - Lap time chart

struct LapChartView: View {
    let laps: [Lap]
    let results: [RaceResult]
    let loading: Bool
    let load: () async -> Void

    var body: some View {
        DriverLapSeriesChart(
            laps: laps,
            results: results,
            loading: loading,
            loadingLabel: "Loading lap times…",
            emptyIcon: "chart.xyaxis.line",
            emptySubtitle: "Lap-by-lap times are available from 1996 onward.",
            yAxisLabel: "Lap time (s)",
            interpolation: .monotone,
            yScaleReversed: false,
            initialTopCount: 3,
            valueExtractor: { $0.time.lapTimeSeconds },
            load: load
        )
    }
}

// MARK: - Position progression chart

struct PositionChartView: View {
    let laps: [Lap]
    let results: [RaceResult]
    let loading: Bool
    let load: () async -> Void

    var body: some View {
        DriverLapSeriesChart(
            laps: laps,
            results: results,
            loading: loading,
            loadingLabel: "Loading positions…",
            emptyIcon: "arrow.up.arrow.down",
            emptySubtitle: "Lap-by-lap positions are available from 1996 onward.",
            yAxisLabel: "Position",
            interpolation: .stepEnd,
            yScaleReversed: true,
            initialTopCount: 5,
            valueExtractor: { Double($0.position) },
            load: load
        )
    }
}

// MARK: - Pit stop strategy

struct StrategyView: View {
    let pitStops: [PitStop]
    let results: [RaceResult]
    let year: Int
    let loading: Bool
    let load: () async -> Void

    @State private var isInitialLoad = true
    @State private var rows: [DriverStopsRow] = []

    private struct DriverStopsRow: Identifiable {
        let driverId: String
        let name: String
        let team: String
        let stops: [PitStop]

        var id: String { driverId }
    }

    private func rebuildRows() {
        let lookup: [String: (name: String, team: String)] = Dictionary(
            results.map { ($0.driver.driverId, ($0.driver.displayName, $0.constructor.constructorId)) },
            uniquingKeysWith: { a, _ in a }
        )
        self.rows = Dictionary(grouping: pitStops, by: \.driverId)
            .map { driverId, stops in
                let sortedStops = stops.sorted { (Int($0.lap) ?? 0) < (Int($1.lap) ?? 0) }
                let meta = lookup[driverId]
                return DriverStopsRow(
                    driverId: driverId,
                    name: meta?.name ?? driverId.capitalized,
                    team: meta?.team ?? driverId,
                    stops: sortedStops
                )
            }
            .sorted { ($0.stops.count, $1.driverId) > ($1.stops.count, $0.driverId) }
    }

    var body: some View {
        Group {
            if year < 2011 {
                MessageView(systemImage: "wrench.and.screwdriver",
                            title: "No pit stop data",
                            subtitle: "Pit stop data is available from 2011 onward.")
            } else if (loading || isInitialLoad) && pitStops.isEmpty {
                LoadingView(label: "Loading strategy…")
            } else if pitStops.isEmpty {
                MessageView(systemImage: "wrench.and.screwdriver",
                            title: "No pit stop data",
                            subtitle: "Pit stop data is available from 2011 onward.")
            } else {
                Chart {
                    ForEach(rows) { row in
                        ForEach(row.stops) { stop in
                            PointMark(
                                x: .value("Lap", Int(stop.lap) ?? 0),
                                y: .value("Driver", row.name)
                            )
                            .foregroundStyle(TeamColor.color(for: row.team))
                            .symbolSize(160)
                            .annotation(position: .top) {
                                Text(stop.duration ?? "")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXAxisLabel("Pit stop lap")
                .chartYAxisLabel("Driver")
                .padding(.top)
            }
        }
        .onAppear { rebuildRows() }
        .onChange(of: pitStops) { rebuildRows() }
        .onChange(of: results) { rebuildRows() }
        .task {
            rebuildRows()
            await load()
            rebuildRows()
            isInitialLoad = false
        }
    }
}
