import Foundation
import Observation
import SwiftUI

/// Sidebar destinations.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case schedule = "Race Calendar"
    case driverStandings = "Driver Standings"
    case constructorStandings = "Constructor Standings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .schedule: return "flag.checkered.2.crossed"
        case .driverStandings: return "person.2.fill"
        case .constructorStandings: return "car.2.fill"
        }
    }

    var compactTitle: String {
        switch self {
        case .schedule: return "Calendar"
        case .driverStandings: return "Drivers"
        case .constructorStandings: return "Constructors"
        }
    }

    var compactSystemImage: String {
        switch self {
        case .schedule: return "flag.checkered"
        case .driverStandings: return "person.crop.circle"
        case .constructorStandings: return "car.2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .schedule: return .red
        case .driverStandings: return .orange
        case .constructorStandings: return .blue
        }
    }
}

/// Season-wide state shared across views. Owns the selected season and caches
/// so switching sidebar items does not re-hit the network needlessly.
@MainActor
@Observable
final class AppState {
    var season: Int {
        didSet {
            guard season != oldValue else { return }
            UserDefaults.standard.set(season, forKey: Self.lastSelectedSeasonKey)
            errorMessage = nil
            selectedRaceID = nil
            selectedDriverID = nil
            selectedConstructorID = nil
            races = []
            driverStandings = []
            constructorStandings = []
            isLoadingSchedule = true
            isLoadingDrivers = true
            isLoadingConstructors = true
            seasonLoadTask?.cancel()
            seasonLoadTask = Task { await reloadForSeason() }
        }
    }
    var selection: SidebarItem? = .schedule

    var selectedRaceID: Race.ID?
    var selectedDriverID: DriverStanding.ID?
    var selectedConstructorID: ConstructorStanding.ID?

    var selectedRace: Race? {
        races.first(where: { $0.id == selectedRaceID })
    }

    var selectedDriverStanding: DriverStanding? {
        driverStandings.first(where: { $0.id == selectedDriverID })
    }

    var selectedConstructorStanding: ConstructorStanding? {
        constructorStandings.first(where: { $0.id == selectedConstructorID })
    }

    var races: [Race] = [] {
        didSet {
            nextRace = races.nextUpcoming() ?? races.last
            if selectedRaceID == nil || !races.contains(where: { $0.id == selectedRaceID }) {
                selectedRaceID = (races.nextUpcoming() ?? races.last ?? races.first)?.id
            }
            MacServices.updateDockTile(with: races)
        }
    }
    private(set) var nextRace: Race?
    var driverStandings: [DriverStanding] = [] {
        didSet {
            if selectedDriverID == nil || !driverStandings.contains(where: { $0.id == selectedDriverID }) {
                selectedDriverID = driverStandings.first?.id
            }
        }
    }
    var constructorStandings: [ConstructorStanding] = [] {
        didSet {
            if selectedConstructorID == nil || !constructorStandings.contains(where: { $0.id == selectedConstructorID }) {
                selectedConstructorID = constructorStandings.first?.id
            }
        }
    }

    var isLoadingSchedule = false
    var isLoadingDrivers = false
    var isLoadingConstructors = false
    var errorMessage: String?

    var isAnyLoading: Bool {
        isLoadingSchedule || isLoadingDrivers || isLoadingConstructors
    }

    /// F1 world-championship era Ergast/Jolpica has data from 1950 onward.
    let availableSeasons: [Int]

    private static let lastSelectedSeasonKey = "lastSelectedSeason"
    @ObservationIgnored private let api = F1APIClient.shared
    @ObservationIgnored private var seasonLoadTask: Task<Void, Never>?

    init(season: Int? = nil) {
        // 1950...current calendar year, newest first.
        let current = Calendar(identifier: .gregorian)
            .dateComponents([.year], from: .now).year ?? 2024
        let seasons = Array(stride(from: current, through: 1950, by: -1))
        self.availableSeasons = seasons

        if let season {
            self.season = season
        } else if UserDefaults.standard.object(forKey: Self.lastSelectedSeasonKey) != nil {
            let savedYear = UserDefaults.standard.integer(forKey: Self.lastSelectedSeasonKey)
            self.season = seasons.contains(savedYear) ? savedYear : 2024
        } else {
            self.season = 2024
        }
    }

    func stepSeason(by delta: Int) {
        guard let newest = availableSeasons.first, let oldest = availableSeasons.last else { return }
        let clamped = min(newest, max(oldest, season + delta))
        guard clamped != season else { return }
        withAnimation(.snappy(duration: 0.35, extraBounce: 0.1)) {
            season = clamped
        }
    }

    func badgeCount(for item: SidebarItem) -> Int {
        switch item {
        case .schedule: return races.count
        case .driverStandings: return driverStandings.count
        case .constructorStandings: return constructorStandings.count
        }
    }

    func loadInitial(forceRefresh: Bool = false) async {
        seasonLoadTask?.cancel()
        let task = Task { await reloadForSeason(forceRefresh: forceRefresh) }
        seasonLoadTask = task
        await task.value
    }

    private func reloadForSeason(forceRefresh: Bool = false) async {
        let targetSeason = season
        if forceRefresh {
            await LocalDataCache.shared.invalidateSeason(targetSeason)
        }
        async let s: Void = loadSchedule(forYear: targetSeason, forceRefresh: forceRefresh)
        async let d: Void = loadDriverStandings(forYear: targetSeason, forceRefresh: forceRefresh)
        async let c: Void = loadConstructorStandings(forYear: targetSeason, forceRefresh: forceRefresh)
        _ = await (s, d, c)
    }

    private func loadTask(
        forYear targetYear: Int,
        loading: ReferenceWritableKeyPath<AppState, Bool>,
        _ action: () async throws -> Void
    ) async {
        self[keyPath: loading] = true
        defer {
            if season == targetYear {
                self[keyPath: loading] = false
            }
        }
        do {
            try await action()
        } catch is CancellationError {
            return
        } catch {
            if season == targetYear {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadSchedule(forYear year: Int? = nil, forceRefresh: Bool = false) async {
        let targetYear = year ?? season
        await loadTask(forYear: targetYear, loading: \.isLoadingSchedule) { [self] in
            let fetched = try await api.seasonSchedule(year: targetYear, forceRefresh: forceRefresh)
            guard !Task.isCancelled, season == targetYear else { return }
            races = fetched
        }
    }

    func loadDriverStandings(forYear year: Int? = nil, forceRefresh: Bool = false) async {
        let targetYear = year ?? season
        await loadTask(forYear: targetYear, loading: \.isLoadingDrivers) { [self] in
            let fetched = try await api.driverStandings(year: targetYear, forceRefresh: forceRefresh)
            guard !Task.isCancelled, season == targetYear else { return }
            driverStandings = fetched
        }
    }

    func loadConstructorStandings(forYear year: Int? = nil, forceRefresh: Bool = false) async {
        let targetYear = year ?? season
        await loadTask(forYear: targetYear, loading: \.isLoadingConstructors) { [self] in
            let fetched = try await api.constructorStandings(year: targetYear, forceRefresh: forceRefresh)
            guard !Task.isCancelled, season == targetYear else { return }
            constructorStandings = fetched
        }
    }
}
