import SwiftUI
import Charts

// MARK: - Shared Selectable Column List

private struct SelectableColumnList<Item: Identifiable & Hashable, RowContent: View>: View where Item.ID == String {
    @Environment(AppState.self) private var state
    let title: String
    let items: [Item]
    let isLoading: Bool
    let loadingLabel: String
    let emptyIcon: String
    let emptyTitle: String
    let emptySubtitle: String
    @Binding var selection: String?
    let isCompactStack: Bool
    @ViewBuilder let rowContent: (Item) -> RowContent

    var body: some View {
        @Bindable var state = state
        content
            .navigationTitle(Text(verbatim: title))
            .toolbar {
                #if os(iOS)
                if isCompactStack {
                    ToolbarItem(placement: .topBarTrailing) {
                        SeasonCompactPicker(season: $state.season, seasons: state.availableSeasons)
                    }
                }
                #endif
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            LoadingView(label: loadingLabel)
        } else if items.isEmpty {
            MessageView(systemImage: emptyIcon, title: emptyTitle, subtitle: emptySubtitle)
        } else if isCompactStack {
            List(items) { item in
                NavigationLink(value: item) {
                    rowContent(item)
                }
            }
            .listStyle(.inset)
            .refreshable {
                await state.loadInitial(forceRefresh: true)
            }
        } else {
            List(items, selection: $selection) { item in
                rowContent(item)
                    .tag(item.id)
            }
            .listStyle(.inset)
            .refreshable {
                await state.loadInitial(forceRefresh: true)
            }
        }
    }
}

// MARK: - Race list (content column for the calendar)

enum RaceStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case completed = "Finished"
    case upcoming = "Upcoming"

    var id: String { rawValue }
}

struct RaceListColumn: View {
    @Environment(AppState.self) private var state
    @Binding var selection: String?          // Race.id
    var isCompactStack: Bool = false
    @State private var search = ""
    @State private var filter: RaceStatusFilter = .all
    @State private var filteredRaces: [Race] = []

    private func updateFilteredRaces() {
        let now = Date()
        filteredRaces = state.races.filter { race in
            guard race.matches(query: search) else { return false }
            switch filter {
            case .all:
                return true
            case .completed:
                return (race.startDate ?? .distantFuture) <= now
            case .upcoming:
                return (race.startDate ?? .distantPast) > now
            }
        }
    }

    var body: some View {
        SelectableColumnList(
            title: "\(state.season) Calendar",
            items: filteredRaces,
            isLoading: state.isLoadingSchedule && state.races.isEmpty,
            loadingLabel: "Loading calendar…",
            emptyIcon: "flag.checkered",
            emptyTitle: search.isEmpty ? "No races" : "No results",
            emptySubtitle: search.isEmpty ? "No calendar data for \(state.season)." : "No races matching \"\(search)\"",
            selection: $selection,
            isCompactStack: isCompactStack
        ) { race in
            RaceRow(
                round: race.round,
                raceName: race.raceName,
                circuitName: race.circuit.circuitName,
                country: race.circuit.location.country,
                startDate: race.startDate,
                circuit: race.circuit,
                season: race.season
            )
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search races, circuits, countries")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Filter", selection: $filter) {
                    ForEach(RaceStatusFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .onAppear { updateFilteredRaces() }
        .onChange(of: state.races) { updateFilteredRaces() }
        .onChange(of: search) { updateFilteredRaces() }
        .onChange(of: filter) { updateFilteredRaces() }
    }
}

private struct RaceRow: View {
    let round: String
    let raceName: String
    let circuitName: String
    let country: String?
    let startDate: Date?
    let circuit: Circuit
    let season: String

    private var isCompleted: Bool {
        guard let d = startDate else { return false }
        return d <= Date()
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isCompleted ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.15))
                Text(round)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(isCompleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(raceName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if isCompleted {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(country ?? circuitName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let d = startDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(d, format: .dateTime.day().month(.abbreviated))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(isCompleted ? .secondary : .primary)

                    if !isCompleted {
                        Text("Upcoming")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button {
                PlatformServices.openInAppleMaps(circuit: circuit)
            } label: {
                Label("Open Circuit in Apple Maps", systemImage: "map.fill")
            }

            Button {
                PlatformServices.openWikipedia(query: "\(circuitName) circuit Formula One")
            } label: {
                Label("Circuit on Wikipedia", systemImage: "book.pages")
            }

            Divider()

            Button {
                let summary = "\(raceName) · \(circuitName) (Round \(round), \(season))"
                PlatformServices.copyToPasteboard(summary)
            } label: {
                Label("Copy Grand Prix Details", systemImage: "doc.on.doc")
            }

            ShareLink(item: "\(raceName) · \(circuitName), \(country ?? "") (Round \(round), \(season))") {
                Label("Share Grand Prix…", systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Driver & Constructor ranking (content columns)

struct DriverRankColumn: View {
    @Environment(AppState.self) private var state
    @Binding var selection: String?          // driverId
    var isCompactStack: Bool = false

    var body: some View {
        SelectableColumnList(
            title: "Drivers",
            items: state.driverStandings,
            isLoading: state.isLoadingDrivers,
            loadingLabel: "Loading standings…",
            emptyIcon: "person.2",
            emptyTitle: "No standings",
            emptySubtitle: "No data for \(state.season).",
            selection: $selection,
            isCompactStack: isCompactStack
        ) { s in
            RankRow(
                position: s.position,
                points: s.points,
                primary: s.driver.fullName,
                secondary: s.constructors.first?.name ?? "",
                code: s.driver.code,
                wins: Int(s.wins) ?? 0,
                teamId: s.constructors.first?.constructorId ?? ""
            )
        }
    }
}

struct ConstructorRankColumn: View {
    @Environment(AppState.self) private var state
    @Binding var selection: String?          // constructorId
    var isCompactStack: Bool = false

    var body: some View {
        SelectableColumnList(
            title: "Constructors",
            items: state.constructorStandings,
            isLoading: state.isLoadingConstructors,
            loadingLabel: "Loading standings…",
            emptyIcon: "car.2",
            emptyTitle: "No standings",
            emptySubtitle: "No data for \(state.season).",
            selection: $selection,
            isCompactStack: isCompactStack
        ) { s in
            RankRow(
                position: s.position,
                points: s.points,
                primary: s.constructor.name,
                secondary: s.constructor.nationality ?? "",
                code: nil,
                wins: Int(s.wins) ?? 0,
                teamId: s.constructor.constructorId
            )
        }
    }
}

private struct RankRow: View {
    let position: String?
    let points: String
    let primary: String
    let secondary: String
    let code: String?
    let wins: Int
    let teamId: String

    var body: some View {
        HStack(spacing: 10) {
            Podium.Badge(position: position)
                .frame(width: 24)

            RoundedRectangle(cornerRadius: 2)
                .fill(TeamColor.color(for: teamId))
                .frame(width: 3.5, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(primary)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if let code {
                        Text(code)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 6) {
                    if !secondary.isEmpty {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if wins > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text("\(wins)")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(points)
                    .font(.callout.monospacedDigit().weight(.bold))
                Text("PTS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button {
                let summary = "\(primary) (\(secondary)) - Position \(position ?? "—"), \(points) pts, \(wins) wins"
                PlatformServices.copyToPasteboard(summary)
            } label: {
                Label("Copy Info", systemImage: "doc.on.doc")
            }

            Button {
                PlatformServices.openWikipedia(query: "\(primary) Formula One")
            } label: {
                Label("Search on Wikipedia", systemImage: "book.pages")
            }

            ShareLink(item: "\(primary) - \(secondary) (\(points) pts)") {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Detail: Driver & Constructor (Unified Components)

struct DriverStandingDetail: View {
    let standing: DriverStanding
    let all: [DriverStanding]

    private var teamId: String { standing.constructors.first?.constructorId ?? "" }
    private var teamName: String { standing.constructors.first?.name ?? "" }
    private var avatarCode: String {
        standing.driver.code ?? String(standing.driver.familyName.prefix(3)).uppercased()
    }

    var body: some View {
        StandingDetailContainer(
            title: standing.driver.fullName,
            wikipediaQuery: "\(standing.driver.fullName) Formula One",
            copySummary: "\(standing.driver.fullName) (\(teamName)) - Position \(standing.position ?? "—"), \(standing.points) pts, \(standing.wins) wins",
            shareItem: "\(standing.driver.fullName) - #\(standing.driver.permanentNumber ?? "") \(teamName) (\(standing.points) pts)",
            hero: StandingHeroCard(
                title: standing.driver.fullName,
                numberTag: standing.driver.permanentNumber,
                subtitle: teamName,
                nationality: standing.driver.nationality,
                position: standing.position,
                teamId: teamId,
                avatarStyle: .driverCode(avatarCode)
            ),
            stats: [
                ("CHAMPIONSHIP POS", standing.position ?? "—", "trophy"),
                ("TOTAL POINTS", standing.points, "chart.line.uptrend.xyaxis"),
                ("RACE WINS", standing.wins, "flag.checkered"),
                ("CONSTRUCTOR", teamName.isEmpty ? "—" : teamName, "car.2.fill"),
                ("NATIONALITY", standing.driver.nationality ?? "—", "globe"),
                ("CAR NUMBER", standing.driver.permanentNumber ?? "—", "number")
            ],
            chart: StandingPointsChartCard(
                title: "Championship Points Comparison",
                yAxisLabel: "Driver",
                height: 340,
                highlightedID: standing.id,
                items: all.prefix(12).map {
                    StandingChartBarItem(
                        id: $0.id,
                        label: $0.driver.familyName,
                        points: $0.points,
                        teamId: $0.constructors.first?.constructorId ?? ""
                    )
                }
            )
        )
    }
}

struct ConstructorStandingDetail: View {
    let standing: ConstructorStanding
    let all: [ConstructorStanding]

    private var teamId: String { standing.constructor.constructorId }

    var body: some View {
        StandingDetailContainer(
            title: standing.constructor.name,
            wikipediaQuery: "\(standing.constructor.name) Formula One",
            copySummary: "\(standing.constructor.name) (\(standing.constructor.nationality ?? "")) - Position \(standing.position ?? "—"), \(standing.points) pts, \(standing.wins) wins",
            shareItem: "\(standing.constructor.name) - Formula 1 (\(standing.points) pts, \(standing.wins) wins)",
            hero: StandingHeroCard(
                title: standing.constructor.name,
                numberTag: nil,
                subtitle: nil,
                nationality: standing.constructor.nationality,
                position: standing.position,
                teamId: teamId,
                avatarStyle: .constructorIcon
            ),
            stats: [
                ("CHAMPIONSHIP POS", standing.position ?? "—", "trophy"),
                ("TOTAL POINTS", standing.points, "chart.line.uptrend.xyaxis"),
                ("RACE WINS", standing.wins, "flag.checkered"),
                ("NATIONALITY", standing.constructor.nationality ?? "—", "globe")
            ],
            chart: StandingPointsChartCard(
                title: "Constructors Championship Points",
                yAxisLabel: "Team",
                height: 320,
                highlightedID: standing.id,
                items: all.map {
                    StandingChartBarItem(
                        id: $0.id,
                        label: $0.constructor.name,
                        points: $0.points,
                        teamId: $0.constructor.constructorId
                    )
                }
            )
        )
    }
}

// MARK: - Shared Standing Detail Subviews

private struct StandingDetailContainer: View {
    let title: String
    let wikipediaQuery: String
    let copySummary: String
    let shareItem: String
    let hero: StandingHeroCard
    let stats: [(String, String, String)]
    let chart: StandingPointsChartCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                StatGrid(stats: stats)
                chart
            }
            .padding(24)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    PlatformServices.openWikipedia(query: wikipediaQuery)
                } label: {
                    Label("Wikipedia", systemImage: "book.pages")
                }
                .help("Open Wikipedia Page")

                Button {
                    PlatformServices.copyToPasteboard(copySummary)
                } label: {
                    Label("Copy Stats", systemImage: "doc.on.doc")
                }
                .help("Copy stats to clipboard")

                ShareLink(item: shareItem, subject: Text(title)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share stats")
            }
        }
    }
}

private struct StandingHeroCard: View {
    enum AvatarStyle {
        case driverCode(String)
        case constructorIcon
    }

    let title: String
    let numberTag: String?
    let subtitle: String?
    let nationality: String?
    let position: String?
    let teamId: String
    let avatarStyle: AvatarStyle

    private var teamColor: Color { TeamColor.color(for: teamId) }

    var body: some View {
        HStack(spacing: 18) {
            avatarView
                .shadow(color: teamColor.opacity(0.4), radius: 8, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.bold))

                    if let num = numberTag {
                        Text("#\(num)")
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if let subtitle, !subtitle.isEmpty, nationality != nil {
                        Text("•")
                            .foregroundStyle(.tertiary)
                    }

                    if let nat = nationality {
                        Text(nat)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(spacing: 2) {
                Text("RANK")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(position ?? "—")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Podium.color(for: position, fallback: .primary))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(18)
        .cardStyle(cornerRadius: 14, fillOpacity: 0.3, borderColor: teamColor.opacity(0.3))
    }

    @ViewBuilder
    private var avatarView: some View {
        switch avatarStyle {
        case .driverCode(let code):
            Circle()
                .fill(teamColor.gradient)
                .frame(width: 56, height: 56)
                .overlay(
                    Text(code)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.white)
                )
        case .constructorIcon:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(teamColor.gradient)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "car.2.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                )
        }
    }
}

private struct StandingChartBarItem: Identifiable {
    let id: String
    let label: String
    let points: String
    let teamId: String

    var numericPoints: Double { Double(points) ?? 0 }
}

private struct StandingPointsChartCard: View {
    let title: String
    let yAxisLabel: String
    let height: CGFloat
    let highlightedID: String
    let items: [StandingChartBarItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Chart(items) { s in
                let isCurrent = s.id == highlightedID
                BarMark(
                    x: .value("Points", s.numericPoints),
                    y: .value(yAxisLabel, s.label)
                )
                .foregroundStyle(TeamColor.color(for: s.teamId))
                .opacity(isCurrent ? 1.0 : 0.35)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text(s.points)
                        .font(.caption2.monospacedDigit().weight(isCurrent ? .bold : .regular))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                }
            }
            .chartXAxisLabel("Points")
            .frame(height: height)
            .padding(.top, 4)
        }
        .padding(18)
        .cardStyle(cornerRadius: 14, fillOpacity: 0.3)
    }
}

// MARK: - Reusable stat grid

private struct StatGrid: View {
    let stats: [(String, String, String)]
    private let cols = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
            ForEach(stats, id: \.0) { label, value, symbol in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(label)
                            .font(.system(size: 9, weight: .bold)).tracking(0.8)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Text(value)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .cardStyle(cornerRadius: 10, fillOpacity: 0.35)
            }
        }
    }
}

