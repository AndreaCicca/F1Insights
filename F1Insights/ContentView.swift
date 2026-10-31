import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var tabSelection: Binding<SidebarItem> {
        Binding(
            get: { state.selection ?? .schedule },
            set: { state.selection = $0 }
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
    }

    private var compactTabView: some View {
        @Bindable var state = state
        return TabView(selection: tabSelection) {
            NavigationStack {
                RaceListColumn(selection: $state.selectedRaceID, isCompactStack: true)
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
                DriverRankColumn(selection: $state.selectedDriverID, isCompactStack: true)
                    .navigationDestination(for: DriverStanding.self) { standing in
                        DriverStandingDetail(standing: standing, all: state.driverStandings)
                    }
            }
            .tabItem {
                Label(SidebarItem.driverStandings.compactTitle, systemImage: SidebarItem.driverStandings.compactSystemImage)
            }
            .tag(SidebarItem.driverStandings)

            NavigationStack {
                ConstructorRankColumn(selection: $state.selectedConstructorID, isCompactStack: true)
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
        @Bindable var state = state
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 280, ideal: 330, max: 460)
        } detail: {
            detailColumn
        }
        .navigationTitle("F1 Insights")
        .platformSubtitle(state.isAnyLoading ? "Updating season data…" : "\(String(state.season)) FIA Formula One World Championship™")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    Task { await state.loadInitial(forceRefresh: true) }
                } label: {
                    if state.isAnyLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help(state.isAnyLoading ? "Updating season data…" : "Refresh season data (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(state.isAnyLoading)
            }
        }
    }

    // MARK: Content (column 2)

    @ViewBuilder
    private var contentColumn: some View {
        @Bindable var state = state
        switch state.selection {
        case .schedule, .none:
            RaceListColumn(selection: $state.selectedRaceID, isCompactStack: false)
        case .driverStandings:
            DriverRankColumn(selection: $state.selectedDriverID, isCompactStack: false)
        case .constructorStandings:
            ConstructorRankColumn(selection: $state.selectedConstructorID, isCompactStack: false)
        }
    }

    // MARK: Detail (column 3)

    @ViewBuilder
    private var detailColumn: some View {
        switch state.selection {
        case .schedule, .none:
            if let race = state.selectedRace {
                RaceDetailView(race: race)
            } else {
                MessageView(
                    systemImage: "flag.checkered",
                    title: "Select a Grand Prix",
                    subtitle: "Pick a race from the calendar to view results, telemetry and replay."
                )
            }
        case .driverStandings:
            if let s = state.selectedDriverStanding {
                DriverStandingDetail(standing: s, all: state.driverStandings)
            } else {
                MessageView(
                    systemImage: "person.2",
                    title: "Select a Driver",
                    subtitle: "Pick a driver from the standings to view statistics."
                )
            }
        case .constructorStandings:
            if let s = state.selectedConstructorStanding {
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

// MARK: - Sidebar (column 1)

private struct SidebarView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
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
}

#Preview {
    ContentView().environment(AppState())
}
