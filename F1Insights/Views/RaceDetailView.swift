import SwiftUI

@MainActor
@Observable
final class RaceDetailModel {
    var results: [RaceResult] = []
    var qualifying: [QualifyingResult] = []
    var laps: [Lap] = []
    var pitStops: [PitStop] = []

    var loadingResults = true
    var loadingQualifying = true
    var loadingPitStops = true
    var loadingLaps = false
    var error: String?

    private var currentRaceID: String?
    private let api = F1APIClient.shared
    private let cache = LocalDataCache.shared

    func prepare(for raceID: String, year: Int) {
        guard currentRaceID != raceID else { return }
        currentRaceID = raceID
        results = []
        qualifying = []
        laps = []
        pitStops = []
        error = nil
        loadingResults = true
        loadingQualifying = true
        loadingPitStops = year >= 2011
        loadingLaps = false
    }

    func loadCore(year: Int, round: Int, raceID: String) async {
        prepare(for: raceID, year: year)
        error = nil

        // 1. Check local cache first for immediate display without loading flicker
        async let cachedRace = cache.raceResults(year: year, round: round)
        async let cachedQual = cache.qualifying(year: year, round: round)
        async let cachedPits = cache.pitStops(year: year, round: round)
        async let cachedLaps = cache.lapTimes(year: year, round: round)

        let (cRace, cQual, cPits, cLaps) = await (cachedRace, cachedQual, cachedPits, cachedLaps)
        guard currentRaceID == raceID else { return }

        if let cLaps, !cLaps.isEmpty {
            self.laps = cLaps
        }
        if let cResults = cRace?.results, !cResults.isEmpty {
            self.results = cResults
            self.loadingResults = false
        }
        if let cQual, !cQual.isEmpty {
            self.qualifying = cQual
            self.loadingQualifying = false
        }
        if let cPits, !cPits.isEmpty {
            self.pitStops = cPits
            self.loadingPitStops = false
        }

        // 2. Fetch any missing core datasets from network (paced + automatic 429 retry)
        let needResults = self.results.isEmpty
        let needQualifying = self.qualifying.isEmpty
        let needPitStops = self.pitStops.isEmpty && year >= 2011

        guard needResults || needQualifying || needPitStops else {
            loadingResults = false
            loadingQualifying = false
            loadingPitStops = false
            return
        }

        async let fetchedResults: [RaceResult]? = needResults
            ? (try? await api.raceResults(year: year, round: round).results)
            : nil
        async let fetchedQualifying: [QualifyingResult]? = needQualifying
            ? (try? await api.qualifying(year: year, round: round))
            : nil
        async let fetchedPitStops: [PitStop]? = needPitStops
            ? (try? await api.pitStops(year: year, round: round))
            : nil

        let (res, qual, pits) = await (fetchedResults, fetchedQualifying, fetchedPitStops)
        guard currentRaceID == raceID else { return }

        if let res {
            self.results = res
        }
        if let qual {
            self.qualifying = qual
        }
        if let pits {
            self.pitStops = pits
        }
        self.loadingResults = false
        self.loadingQualifying = false
        self.loadingPitStops = false
    }

    func loadQualifying(year: Int, round: Int, raceID: String) async {
        prepare(for: raceID, year: year)
        guard qualifying.isEmpty else { return }

        loadingQualifying = true
        defer {
            if currentRaceID == raceID {
                loadingQualifying = false
            }
        }

        if let cached = await cache.qualifying(year: year, round: round), !cached.isEmpty {
            guard currentRaceID == raceID else { return }
            self.qualifying = cached
            return
        }

        if let loaded = try? await api.qualifying(year: year, round: round), currentRaceID == raceID {
            self.qualifying = loaded
        }
    }

    func loadPitStops(year: Int, round: Int, raceID: String) async {
        prepare(for: raceID, year: year)
        guard year >= 2011, pitStops.isEmpty else {
            loadingPitStops = false
            return
        }

        loadingPitStops = true
        defer {
            if currentRaceID == raceID {
                loadingPitStops = false
            }
        }

        if let cached = await cache.pitStops(year: year, round: round), !cached.isEmpty {
            guard currentRaceID == raceID else { return }
            self.pitStops = cached
            return
        }

        if let loaded = try? await api.pitStops(year: year, round: round), currentRaceID == raceID {
            self.pitStops = loaded
        }
    }

    func loadLaps(year: Int, round: Int, raceID: String) async {
        prepare(for: raceID, year: year)
        guard year >= 1996, laps.isEmpty else {
            loadingLaps = false
            return
        }

        loadingLaps = true
        defer {
            if currentRaceID == raceID {
                loadingLaps = false
            }
        }

        if let cached = await cache.lapTimes(year: year, round: round), !cached.isEmpty {
            guard currentRaceID == raceID else { return }
            self.laps = cached
            return
        }

        do {
            let loadedLaps = try await api.lapTimes(year: year, round: round)
            guard currentRaceID == raceID else { return }
            self.laps = loadedLaps
        } catch {
            if currentRaceID == raceID && self.laps.isEmpty {
                self.laps = []
            }
        }
    }
}

struct RaceDetailView: View {
    let race: Race
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var model = RaceDetailModel()
    @State private var tab: RaceTab = .results
    @State private var showInspector = false

    private var year: Int { Int(race.season) ?? 0 }
    private var round: Int { Int(race.round) ?? 0 }

    var body: some View {
        VStack(spacing: horizontalSizeClass == .compact ? 8 : 12) {
            RaceSummaryHeader(
                race: race,
                results: model.results,
                loadingResults: model.loadingResults,
                isSlimCompact: horizontalSizeClass == .compact && (tab == .replay || tab == .trackMap),
                isCompact: horizontalSizeClass == .compact
            )

            SegmentedTabBar(selection: $tab)

            ZStack {
                content
                    .id("\(race.id)-\(tab.rawValue)")
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: tab)
        }
        .padding(.horizontal, horizontalSizeClass == .compact ? 12 : 16)
        .padding(.bottom, horizontalSizeClass == .compact ? 8 : 16)
        .padding(.top, horizontalSizeClass == .compact ? 4 : 10)
        .navigationTitle(race.raceName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
        .navigationSubtitle("\(race.circuit.circuitName) · Round \(race.round)")
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    PlatformServices.openInAppleMaps(circuit: race.circuit)
                } label: {
                    Label("Maps", systemImage: "map")
                }
                .help("Open Circuit in Apple Maps (Satellite view)")

                ShareLink(
                    item: "🏎️ \(race.raceName) (\(race.circuit.circuitName), \(race.circuit.location.country ?? "")) - Round \(race.round), \(race.season)",
                    subject: Text(race.raceName)
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share Grand Prix summary")

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showInspector.toggle()
                    }
                } label: {
                    if horizontalSizeClass == .compact {
                        Label("Info", systemImage: showInspector ? "info.circle.fill" : "info.circle")
                    } else {
                        Label("Inspector", systemImage: "sidebar.trailing")
                    }
                }
                .help(horizontalSizeClass == .compact ? "Dettagli circuito ed evento" : "Toggle Circuit Inspector (⌥⌘I)")
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .inspector(isPresented: $showInspector) {
            CircuitInspectorView(race: race, results: model.results)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
        .task(id: race.id) { await model.loadCore(year: year, round: round, raceID: race.id) }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var content: some View {
        let loadLapsAction: () async -> Void = {
            await model.loadLaps(year: year, round: round, raceID: race.id)
        }
        switch tab {
        case .results:
            ResultsTab(results: model.results, race: race, loading: model.loadingResults)
        case .qualifying:
            QualifyingTab(
                results: model.qualifying,
                loading: model.loadingQualifying,
                load: { await model.loadQualifying(year: year, round: round, raceID: race.id) }
            )
        case .lapTimes:
            LapChartView(laps: model.laps, results: model.results,
                         loading: model.loadingLaps || model.loadingResults,
                         load: loadLapsAction)
        case .positions:
            PositionChartView(laps: model.laps, results: model.results,
                              loading: model.loadingLaps || model.loadingResults,
                              load: loadLapsAction)
        case .replay:
            RaceReplayView(laps: model.laps, results: model.results,
                           pitStops: model.pitStops,
                           loading: model.loadingLaps || model.loadingResults,
                           load: loadLapsAction)
        case .trackMap:
            TrackMapView(race: race)
        case .strategy:
            StrategyView(
                pitStops: model.pitStops,
                results: model.results,
                year: year,
                loading: model.loadingPitStops || model.loadingResults,
                load: { await model.loadPitStops(year: year, round: round, raceID: race.id) }
            )
        }
    }
}

// MARK: - Race Summary Header

private struct RaceSummaryHeader: View {
    let race: Race
    let results: [RaceResult]
    let loadingResults: Bool
    let isSlimCompact: Bool
    let isCompact: Bool

    var body: some View {
        if isSlimCompact {
            slimBanner
        } else if isCompact {
            stackedCard
                .padding(12)
                .cardStyle()
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    titleSection
                    Spacer(minLength: 8)
                    if !results.isEmpty {
                        kpiChips
                    }
                }
                stackedCard
            }
            .padding(14)
            .cardStyle()
        }
    }

    private var slimBanner: some View {
        HStack(spacing: 8) {
            Text("R\(race.round)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))

            Text(race.circuit.circuitName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 4)

            if let winner = results.first {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(TeamColor.color(for: winner.constructor.constructorId))
                    Text(winner.driver.code ?? winner.driver.familyName)
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.4), in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.3))
        )
    }

    private var stackedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleSection
            if !results.isEmpty {
                ScrollView(.horizontal) {
                    kpiChips
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("ROUND \(race.round)")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))

                if let date = race.startDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if results.isEmpty && !loadingResults {
                    Text("NON DISPUTATO")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                }
            }

            Text(race.raceName)
                .font(.title2.weight(.bold))

            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("\(race.circuit.circuitName), \(race.circuit.location.country ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    PlatformServices.openInAppleMaps(circuit: race.circuit)
                } label: {
                    HStack(spacing: 2) {
                        Text("Apple Maps")
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Open track location in Apple Maps")
            }
        }
    }

    private var kpiChips: some View {
        HStack(spacing: 10) {
            if let winner = results.first {
                summaryChip(
                    title: "WINNER",
                    value: winner.driver.fullName,
                    color: TeamColor.color(for: winner.constructor.constructorId),
                    symbol: "trophy.fill"
                )
            }

            if let fl = results.first(where: { $0.fastestLap?.rank == "1" }),
               let lapTime = fl.fastestLap?.time?.time {
                summaryChip(
                    title: "FASTEST LAP",
                    value: "\(fl.driver.code ?? fl.driver.familyName) (\(lapTime))",
                    color: .purple,
                    symbol: "stopwatch.fill"
                )
            }

            if let maxLaps = results.first?.laps {
                summaryChip(
                    title: "LAPS",
                    value: "\(maxLaps) laps",
                    color: .secondary,
                    symbol: "flag.checkered"
                )
            }
        }
    }

    private func summaryChip(title: String, value: String, color: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Segmented Tab Bar

private enum RaceTab: String, CaseIterable, Identifiable {
    case results = "Results"
    case qualifying = "Qualifying"
    case lapTimes = "Lap Times"
    case positions = "Position Changes"
    case replay = "Race Replay"
    case trackMap = "Track Map"
    case strategy = "Strategy"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .results: return "list.number"
        case .qualifying: return "stopwatch"
        case .lapTimes: return "chart.line.uptrend.xyaxis"
        case .positions: return "arrow.up.arrow.down"
        case .replay: return "play.circle"
        case .trackMap: return "map"
        case .strategy: return "wrench.and.screwdriver"
        }
    }
}

private struct SegmentedTabBar: View {
    @Binding var selection: RaceTab
    @Namespace private var ns

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 3) {
                ForEach(RaceTab.allCases) { t in
                    let active = selection == t
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            selection = t
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: t.symbol)
                                .font(.system(size: 11, weight: active ? .semibold : .regular))
                            Text(t.rawValue)
                                .font(.subheadline.weight(active ? .semibold : .regular))
                                .fixedSize()
                        }
                        .foregroundStyle(active ? Color.primary : Color.secondary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 11)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(0.12))
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(t.rawValue)
                }
            }
            .padding(3)
        }
        .scrollIndicators(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        )
    }
}

// MARK: - Results tab

private struct ResultsTab: View {
    let results: [RaceResult]
    let race: Race
    let loading: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var sortOrder = [KeyPathComparator(\RaceResult.positionInt)]

    private var sortedResults: [RaceResult] {
        results.sorted(using: sortOrder)
    }

    var body: some View {
        if loading && results.isEmpty {
            LoadingView(label: "Loading results…")
        } else if results.isEmpty {
            MessageView(systemImage: "calendar.badge.clock", title: "Gara non ancora disputata",
                        subtitle: "I risultati saranno disponibili al termine del Gran Premio.")
        } else if horizontalSizeClass == .compact {
            List(sortedResults) { r in
                RaceResultCompactRow(result: r, race: race)
            }
            .listStyle(.plain)
        } else {
            regularResultsTable
        }
    }

    private var regularResultsTable: some View {
        Table(sortedResults, sortOrder: $sortOrder) {
            TableColumn("Pos", value: \.positionInt) { r in
                Podium.Pill(text: r.positionText, position: r.positionInt)
            }
            .width(min: 36, ideal: 44, max: 56)

            TableColumn("Driver", value: \.driver.familyName) { r in
                TeamDotLabel(
                    title: r.driver.fullName,
                    teamId: r.constructor.constructorId,
                    subtitle: r.driver.code
                )
                .contextMenu {
                    Button {
                        PlatformServices.openWikipedia(query: "\(r.driver.fullName) Formula One")
                    } label: {
                        Label("Driver on Wikipedia", systemImage: "book.pages")
                    }

                    Divider()

                    Button {
                        let md = PlatformServices.generateMarkdownTable(race: race, results: sortedResults)
                        PlatformServices.copyToPasteboard(md)
                    } label: {
                        Label("Copy Full Table as Markdown", systemImage: "tablecells")
                    }

                    Button {
                        let csv = PlatformServices.generateCSV(race: race, results: sortedResults)
                        PlatformServices.copyToPasteboard(csv)
                    } label: {
                        Label("Copy Full Table as CSV", systemImage: "doc.plaintext")
                    }
                }
            }
            .width(min: 110, ideal: 160)

            TableColumn("Team", value: \.constructor.name) { r in
                Text(r.constructor.name)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Grid", value: \.gridInt) { r in
                HStack(spacing: 4) {
                    Text(r.grid ?? "—")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let delta = r.gridDelta, delta != 0 {
                        let color: Color = delta > 0 ? .green : .red
                        HStack(spacing: 1) {
                            Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                            Text("\(abs(delta))")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                        }
                        .foregroundStyle(color)
                    }
                }
            }
            .width(min: 44, ideal: 60)

            TableColumn("Time / Status") { r in
                if let time = r.time?.time {
                    Text(time)
                        .font(.callout.monospacedDigit().weight(.medium))
                } else {
                    let dnf = r.isDNF
                    Text(r.status)
                        .font(.caption.weight(dnf ? .semibold : .regular))
                        .foregroundStyle(dnf ? Color.red.opacity(0.9) : Color.secondary)
                        .padding(.horizontal, dnf ? 6 : 0)
                        .padding(.vertical, dnf ? 2 : 0)
                        .background(dnf ? Color.red.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .width(min: 85, ideal: 115)

            TableColumn("Pts", value: \.pointsDouble) { r in
                Text(r.points)
                    .font(.callout.monospacedDigit().weight(.bold))
                    .foregroundStyle(r.pointsDouble > 0 ? Color.primary : Color.secondary)
            }
            .width(min: 36, ideal: 46, max: 56)
        }
        .f1TableStyle()
    }
}

private struct RaceResultCompactRow: View {
    let result: RaceResult
    let race: Race

    var body: some View {
        HStack(spacing: 12) {
            Podium.Pill(text: result.positionText, position: result.positionInt)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.driver.fullName)
                        .font(.body.weight(.semibold))
                    if let code = result.driver.code {
                        Text(code)
                            .font(.caption.monospaced().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(TeamColor.color(for: result.constructor.constructorId))
                        .frame(width: 7, height: 7)
                    Text(result.constructor.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let laps = result.laps {
                        Text("• \(laps) laps")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(result.time?.time ?? result.status)
                    .font(.callout.monospacedDigit().weight(result.positionInt == 1 ? .bold : .regular))
                    .foregroundStyle(result.positionInt == 1 ? Color.purple : (result.status == "Finished" || result.time != nil ? Color.primary : Color.red))

                if result.pointsDouble > 0 {
                    Text("+\(result.points) pts")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                PlatformServices.copyToPasteboard("\(result.positionText). \(result.driver.fullName) (\(result.constructor.name)) - \(result.time?.time ?? result.status), \(result.points) pts")
            } label: {
                Label("Copy Driver Result", systemImage: "doc.on.doc")
            }
            ShareLink(item: "\(result.driver.fullName) finished P\(result.positionText) in the \(race.raceName) with \(result.constructor.name)") {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Qualifying tab

private struct QualifyingTab: View {
    let results: [QualifyingResult]
    let loading: Bool
    let load: () async -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var sortOrder = [KeyPathComparator(\QualifyingResult.positionInt)]
    @State private var isInitialLoad = true

    private var sortedResults: [QualifyingResult] {
        results.sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if (loading || isInitialLoad) && results.isEmpty {
                LoadingView(label: "Loading qualifying…")
            } else if results.isEmpty {
                MessageView(systemImage: "stopwatch", title: "Qualifiche non ancora disputate",
                            subtitle: "I tempi di qualifica saranno disponibili al termine della sessione.")
            } else if horizontalSizeClass == .compact {
                List(sortedResults) { r in
                    QualifyingCompactRow(result: r)
                }
                .listStyle(.plain)
            } else {
                regularQualifyingTable
            }
        }
        .task {
            await load()
            isInitialLoad = false
        }
    }

    private var regularQualifyingTable: some View {
        Table(sortedResults, sortOrder: $sortOrder) {
            TableColumn("Pos", value: \.positionInt) { r in
                QualifyingPositionBadge(result: r)
            }
            .width(min: 36, ideal: 44, max: 56)

            TableColumn("Driver", value: \.driver.familyName) { r in
                TeamDotLabel(
                    title: r.driver.fullName,
                    teamId: r.constructor.constructorId,
                    subtitle: r.driver.code
                )
                .contextMenu {
                    qualifyingContextMenu(for: r)
                }
            }
            .width(min: 110, ideal: 160)

            TableColumn("Team", value: \.constructor.name) { r in
                Text(r.constructor.name)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Q1") { r in
                sessionTimeCell(r.q1)
            }
            .width(min: 60, ideal: 75)

            TableColumn("Q2") { r in
                sessionTimeCell(r.q2)
            }
            .width(min: 60, ideal: 75)

            TableColumn("Q3") { r in
                sessionTimeCell(r.q3, isPole: r.positionInt == 1)
            }
            .width(min: 60, ideal: 75)
        }
        .f1TableStyle()
    }

    private func sessionTimeCell(_ time: String?, isPole: Bool = false) -> some View {
        Text(time ?? "—")
            .font(.callout.monospacedDigit().weight(isPole && time != nil ? .bold : .regular))
            .foregroundStyle(time != nil ? (isPole ? Color.purple : Color.primary) : Color.secondary)
    }
}

private struct QualifyingPositionBadge: View {
    let result: QualifyingResult

    var body: some View {
        if result.positionInt == 1 {
            Text("POLE")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.purple)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
        } else {
            Text(result.position)
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct QualifyingCompactRow: View {
    let result: QualifyingResult

    var body: some View {
        HStack(spacing: 12) {
            QualifyingPositionBadge(result: result)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.driver.fullName)
                    .font(.body.weight(.semibold))

                HStack(spacing: 6) {
                    Circle()
                        .fill(TeamColor.color(for: result.constructor.constructorId))
                        .frame(width: 7, height: 7)
                    Text(result.constructor.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            let isPole = result.positionInt == 1 && result.q3 != nil
            Text(result.bestTime)
                .font(.callout.monospacedDigit().weight(isPole ? .bold : (result.q3 != nil ? .medium : .regular)))
                .foregroundStyle(isPole ? Color.purple : (result.q3 != nil ? Color.primary : Color.secondary))
        }
        .padding(.vertical, 4)
        .contextMenu {
            qualifyingContextMenu(for: result)
        }
    }
}

@ViewBuilder
private func qualifyingContextMenu(for r: QualifyingResult) -> some View {
    Button {
        let summary = "P\(r.position): \(r.driver.fullName) (\(r.constructor.name)) - Qualifying: \(r.bestTime)"
        PlatformServices.copyToPasteboard(summary)
    } label: {
        Label("Copy Lap Time", systemImage: "doc.on.doc")
    }

    Button {
        PlatformServices.openWikipedia(query: "\(r.driver.fullName) Formula One")
    } label: {
        Label("Driver on Wikipedia", systemImage: "book.pages")
    }
}
