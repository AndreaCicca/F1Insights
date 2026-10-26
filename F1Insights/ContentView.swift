import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Selection per content type (by id). Reset when the season changes.
    @State private var raceID: String?
    @State private var driverID: String?
    @State private var constructorID: String?

    @State private var isUpdating = true
    @State private var loadingStartTime: Date?
    @State private var dismissTask: Task<Void, Never>?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var compactTab: SidebarItem = .schedule

    private func activeID<T: Identifiable>(for storedID: String?, in items: [T]) -> String? where T.ID == String {
        if let storedID, items.contains(where: { $0.id == storedID }) {
            return storedID
        }
        return items.first?.id
    }

    private func selectionBinding<T: Identifiable>(for storedID: Binding<String?>, in items: [T]) -> Binding<String?> where T.ID == String {
        Binding(
            get: { activeID(for: storedID.wrappedValue, in: items) },
            set: { storedID.wrappedValue = $0 }
        )
    }

    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                compactTabView
            } else {
                regularSplitView
            }
            #else
            regularSplitView
            #endif
        }
        .onChange(of: state.season) {
            raceID = nil
            driverID = nil
            constructorID = nil
        }
        .onChange(of: state.isAnyLoading) {
            handleLoadingStateChange(state.isAnyLoading)
        }
    }

    private var compactTabView: some View {
        TabView(selection: $compactTab) {
            NavigationStack {
                RaceListColumn(selection: $raceID, isCompactStack: true)
                    .navigationDestination(for: Race.self) { race in
                        RaceDetailView(race: race)
                            .id(race.id)
                    }
            }
            .tabItem {
                Label(SidebarItem.schedule.compactTitle, systemImage: SidebarItem.schedule.compactSystemImage)
            }
            .tag(SidebarItem.schedule)

            NavigationStack {
                DriverRankColumn(selection: $driverID, isCompactStack: true)
                    .navigationDestination(for: DriverStanding.self) { standing in
                        DriverStandingDetail(standing: standing, all: state.driverStandings)
                    }
            }
            .tabItem {
                Label(SidebarItem.driverStandings.compactTitle, systemImage: SidebarItem.driverStandings.compactSystemImage)
            }
            .tag(SidebarItem.driverStandings)

            NavigationStack {
                ConstructorRankColumn(selection: $constructorID, isCompactStack: true)
                    .navigationDestination(for: ConstructorStanding.self) { standing in
                        ConstructorStandingDetail(standing: standing, all: state.constructorStandings)
                    }
            }
            .tabItem {
                Label(SidebarItem.constructorStandings.compactTitle, systemImage: SidebarItem.constructorStandings.compactSystemImage)
            }
            .tag(SidebarItem.constructorStandings)
        }
    }

    private var regularSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 280, ideal: 330, max: 460)
        } detail: {
            detailColumn
        }
        .navigationTitle("F1 Insights")
        #if os(macOS)
        .navigationSubtitle(isUpdating ? "Updating season data…" : "\(String(state.season)) FIA Formula One World Championship™")
        #endif
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    Task { await state.loadInitial(forceRefresh: true) }
                } label: {
                    if isUpdating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help(isUpdating ? "Updating season data…" : "Refresh season data (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(state.isAnyLoading || isUpdating)
            }
        }
    }

    private func handleLoadingStateChange(_ isLoading: Bool) {
        if isLoading {
            dismissTask?.cancel()
            loadingStartTime = Date()
            withAnimation(.easeInOut(duration: 0.2)) {
                isUpdating = true
            }
        } else {
            let elapsed = Date().timeIntervalSince(loadingStartTime ?? .distantPast)
            // If satisfied from local cache (< 120ms), dismiss immediately without artificial wait
            let minWait = elapsed < 0.12 ? 0.0 : 0.85
            let remaining = max(0, minWait - elapsed)

            dismissTask?.cancel()
            dismissTask = Task {
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
                if !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isUpdating = false
                    }
                }
            }
        }
    }

    // MARK: Sidebar (column 1)

    private var sidebar: some View {
        @Bindable var state = state
        return VStack(spacing: 0) {
            SeasonHeader(season: $state.season, seasons: state.availableSeasons)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            List(selection: $state.selection) {
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        Label {
                            Text(item.rawValue)
                        } icon: {
                            Image(systemName: item.systemImage)
                                .foregroundStyle(item.tint)
                        }
                        .badge(state.badgeCount(for: item))
                        .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: Content (column 2)

    @ViewBuilder
    private var contentColumn: some View {
        switch state.selection {
        case .schedule, .none:
            RaceListColumn(selection: selectionBinding(for: $raceID, in: state.races), isCompactStack: false)
        case .driverStandings:
            DriverRankColumn(selection: selectionBinding(for: $driverID, in: state.driverStandings), isCompactStack: false)
        case .constructorStandings:
            ConstructorRankColumn(selection: selectionBinding(for: $constructorID, in: state.constructorStandings), isCompactStack: false)
        }
    }

    // MARK: Detail (column 3)

    @ViewBuilder
    private var detailColumn: some View {
        switch state.selection {
        case .schedule, .none:
            let id = activeID(for: raceID, in: state.races)
            if let race = state.races.first(where: { $0.id == id }) {
                RaceDetailView(race: race)
            } else {
                MessageView(
                    systemImage: "flag.checkered",
                    title: "Select a Grand Prix",
                    subtitle: "Pick a race from the calendar to view results, telemetry and replay."
                )
            }
        case .driverStandings:
            let id = activeID(for: driverID, in: state.driverStandings)
            if let s = state.driverStandings.first(where: { $0.id == id }) {
                DriverStandingDetail(standing: s, all: state.driverStandings)
            } else {
                MessageView(
                    systemImage: "person.2",
                    title: "Select a Driver",
                    subtitle: "Pick a driver from the standings to view statistics."
                )
            }
        case .constructorStandings:
            let id = activeID(for: constructorID, in: state.constructorStandings)
            if let s = state.constructorStandings.first(where: { $0.id == id }) {
                ConstructorStandingDetail(standing: s, all: state.constructorStandings)
            } else {
                MessageView(
                    systemImage: "car.2",
                    title: "Select a Constructor",
                    subtitle: "Pick a constructor to view team results and points."
                )
            }
        }
    }
}

#Preview {
    ContentView().environment(AppState())
}

