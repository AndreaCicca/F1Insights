import Foundation

enum F1APIError: LocalizedError {
    case badURL
    case badStatus(Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid request URL."
        case .badStatus(let code): return "Server returned status \(code)."
        case .empty: return "No data returned for this request."
        }
    }
}

extension URLSession {
    /// Shared network request helper with User-Agent header, automatic retry on HTTP 429 / 5xx
    /// and transient network errors, HTTP status validation, and JSON decoding.
    func decode<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        decoder: JSONDecoder = JSONDecoder(),
        maxAttempts: Int = 5
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("F1Insights/1.0 (Apple)", forHTTPHeaderField: "User-Agent")

        var lastError: Error = F1APIError.empty
        for attempt in 0..<max(1, maxAttempts) {
            try Task.checkCancellation()
            do {
                let (data, response) = try await self.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if (200...299).contains(http.statusCode) {
                        return try decoder.decode(T.self, from: data)
                    }
                    // Retry on HTTP 429 (Too Many Requests) or 5xx server errors
                    if (http.statusCode == 429 || (500...599).contains(http.statusCode)),
                       attempt + 1 < maxAttempts {
                        let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                        let baseDelay = retryAfter ?? (0.65 * pow(1.65, Double(attempt)))
                        let jitter = Double.random(in: 0.05...0.20)
                        try await Task.sleep(for: .seconds(min(baseDelay + jitter, 5.0)))
                        continue
                    }
                    throw F1APIError.badStatus(http.statusCode)
                }
                return try decoder.decode(T.self, from: data)
            } catch let urlError as URLError where attempt + 1 < maxAttempts {
                lastError = urlError
                let retryable: Set<URLError.Code> = [
                    .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed
                ]
                guard retryable.contains(urlError.code) else { throw urlError }
                try await Task.sleep(for: .seconds(0.5 * Double(attempt + 1)))
            } catch {
                throw error
            }
        }
        throw lastError
    }
}

/// Paces outgoing network requests to Jolpica's origin server (~4 req/sec limit)
/// so burst loads (season switch + race details + paginated laps) never trigger HTTP 429.
private actor RequestPacer {
    private var nextAllowedTime: ContinuousClock.Instant = .now
    private let clock = ContinuousClock()
    private let minInterval: Duration = .milliseconds(260)

    func acquireSlot() async throws {
        try Task.checkCancellation()
        let now = clock.now
        if now < nextAllowedTime {
            let delay = nextAllowedTime - now
            nextAllowedTime = nextAllowedTime + minInterval
            try await Task.sleep(for: delay)
        } else {
            nextAllowedTime = now + minInterval
        }
    }
}

/// Thin async client over the Jolpica-F1 API (Ergast-compatible).
///
/// FastF1 uses the same public F1 endpoints under the hood; Jolpica is the
/// maintained successor to the retired Ergast service and exposes identical
/// JSON. Car telemetry (speed/throttle/brake traces) is NOT part of this REST
/// surface — that requires FastF1's Python live-timing scraper.
actor F1APIClient {
    static let shared = F1APIClient()

    private let base = URL(string: "https://api.jolpi.ca/ergast/f1")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let cache = LocalDataCache.shared
    private let pacer = RequestPacer()

    /// Deduplicates concurrent in-flight requests so tab switches or parallel callers share the same network task.
    private var inFlightResultsTasks: [String: Task<Race, Error>] = [:]
    private var inFlightQualifyingTasks: [String: Task<[QualifyingResult], Error>] = [:]
    private var inFlightPitStopTasks: [String: Task<[PitStop], Error>] = [:]
    private var inFlightLapTasks: [String: Task<[Lap], Error>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Generic fetch

    private func fetch<T: Decodable & Sendable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        guard var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw F1APIError.badURL
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw F1APIError.badURL }

        try await pacer.acquireSlot()
        return try await session.decode(T.self, from: url, decoder: decoder)
    }

    // MARK: - Schedule

    func seasonSchedule(year: Int, forceRefresh: Bool = false) async throws -> [Race] {
        if !forceRefresh, let cached = await cache.schedule(forYear: year) {
            return cached
        }
        let env = try await fetch(MRDataEnvelope<RaceTableEnvelope>.self, path: "\(year).json")
        let races = env.mrData.raceTable.races
        await cache.saveSchedule(races, forYear: year)
        return races
    }

    // MARK: - Results, qualifying & pit stops

    func raceResults(year: Int, round: Int, forceRefresh: Bool = false) async throws -> Race {
        if !forceRefresh, let cached = await cache.raceResults(year: year, round: round) {
            return cached
        }
        let key = "\(year)-\(round)"
        if !forceRefresh, let existing = inFlightResultsTasks[key] {
            return try await existing.value
        }

        let task = Task<Race, Error> {
            let env = try await self.fetch(MRDataEnvelope<RaceTableEnvelope>.self, path: "\(year)/\(round)/results.json")
            guard let race = env.mrData.raceTable.races.first else { throw F1APIError.empty }
            await self.cache.saveRaceResults(race, year: year, round: round)
            return race
        }
        inFlightResultsTasks[key] = task
        defer { inFlightResultsTasks.removeValue(forKey: key) }
        return try await task.value
    }

    func qualifying(year: Int, round: Int, forceRefresh: Bool = false) async throws -> [QualifyingResult] {
        if !forceRefresh, let cached = await cache.qualifying(year: year, round: round) {
            return cached
        }
        let key = "\(year)-\(round)"
        if !forceRefresh, let existing = inFlightQualifyingTasks[key] {
            return try await existing.value
        }

        let task = Task<[QualifyingResult], Error> {
            let env = try await self.fetch(MRDataEnvelope<RaceTableEnvelope>.self, path: "\(year)/\(round)/qualifying.json")
            let results = env.mrData.raceTable.races.first?.qualifyingResults ?? []
            await self.cache.saveQualifying(results, year: year, round: round)
            return results
        }
        inFlightQualifyingTasks[key] = task
        defer { inFlightQualifyingTasks.removeValue(forKey: key) }
        return try await task.value
    }

    func pitStops(year: Int, round: Int, forceRefresh: Bool = false) async throws -> [PitStop] {
        if !forceRefresh, let cached = await cache.pitStops(year: year, round: round) {
            return cached
        }
        let key = "\(year)-\(round)"
        if !forceRefresh, let existing = inFlightPitStopTasks[key] {
            return try await existing.value
        }

        let task = Task<[PitStop], Error> {
            let env = try await self.fetch(
                MRDataEnvelope<RaceTableEnvelope>.self,
                path: "\(year)/\(round)/pitstops.json",
                query: [URLQueryItem(name: "limit", value: "100")]
            )
            let stops = env.mrData.raceTable.races.first?.pitStops ?? []
            await self.cache.savePitStops(stops, year: year, round: round)
            return stops
        }
        inFlightPitStopTasks[key] = task
        defer { inFlightPitStopTasks.removeValue(forKey: key) }
        return try await task.value
    }

    // MARK: - Lap times (paginated — a race holds thousands of timing rows)

    func lapTimes(year: Int, round: Int, maxPages: Int = 40, forceRefresh: Bool = false) async throws -> [Lap] {
        if !forceRefresh, let cached = await cache.lapTimes(year: year, round: round) {
            return cached
        }

        let key = "\(year)-\(round)"
        if !forceRefresh, let existing = inFlightLapTasks[key] {
            return try await existing.value
        }

        let task = Task<[Lap], Error> {
            try await self.fetchLapTimesFromNetwork(year: year, round: round, maxPages: maxPages)
        }
        inFlightLapTasks[key] = task
        defer { inFlightLapTasks.removeValue(forKey: key) }

        let laps = try await task.value
        await cache.saveLapTimes(laps, year: year, round: round)
        return laps
    }

    private func fetchLapTimesFromNetwork(year: Int, round: Int, maxPages: Int) async throws -> [Lap] {
        let limit = 100
        let path = "\(year)/\(round)/laps.json"

        // 1. Fetch first page to discover total count
        let firstEnv = try await fetch(
            MRDataEnvelope<RaceTableEnvelope>.self,
            path: path,
            query: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "0")
            ]
        )
        let firstPage = firstEnv.mrData.raceTable.races.first?.laps ?? []
        let total = firstEnv.mrData.pagination.total
        guard !firstPage.isEmpty else { return [] }

        let maxOffset = min(total, maxPages * limit)
        let remainingOffsets = Array(stride(from: limit, to: maxOffset, by: limit))

        var pagesByOffset: [(offset: Int, laps: [Lap])] = [(0, firstPage)]
        pagesByOffset.reserveCapacity(1 + remainingOffsets.count)

        // 2. Fetch remaining pages with bounded parallelism (paced by RequestPacer + automatic 429 retry)
        if !remainingOffsets.isEmpty {
            let maxConcurrent = 3
            try await withThrowingTaskGroup(of: (Int, [Lap]).self) { group in
                var index = 0
                let initialCount = min(maxConcurrent, remainingOffsets.count)
                while index < initialCount {
                    let offset = remainingOffsets[index]
                    index += 1
                    group.addTask {
                        let env = try await self.fetch(
                            MRDataEnvelope<RaceTableEnvelope>.self,
                            path: path,
                            query: [
                                URLQueryItem(name: "limit", value: "\(limit)"),
                                URLQueryItem(name: "offset", value: "\(offset)")
                            ]
                        )
                        return (offset, env.mrData.raceTable.races.first?.laps ?? [])
                    }
                }

                for try await result in group {
                    pagesByOffset.append(result)
                    if index < remainingOffsets.count {
                        let offset = remainingOffsets[index]
                        index += 1
                        group.addTask {
                            let env = try await self.fetch(
                                MRDataEnvelope<RaceTableEnvelope>.self,
                                path: path,
                                query: [
                                    URLQueryItem(name: "limit", value: "\(limit)"),
                                    URLQueryItem(name: "offset", value: "\(offset)")
                                ]
                            )
                            return (offset, env.mrData.raceTable.races.first?.laps ?? [])
                        }
                    }
                }
            }
        }

        // 3. Merge pages in deterministic offset order
        pagesByOffset.sort { $0.offset < $1.offset }
        var lapsByNumber: [String: [Timing]] = [:]
        var lapOrder: [String] = []

        for (_, page) in pagesByOffset {
            for lap in page {
                if lapsByNumber[lap.number] == nil { lapOrder.append(lap.number) }
                lapsByNumber[lap.number, default: []].append(contentsOf: lap.timings)
            }
        }

        return lapOrder
            .sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
            .map { Lap(number: $0, timings: lapsByNumber[$0] ?? []) }
    }

    // MARK: - Standings

    func driverStandings(year: Int, forceRefresh: Bool = false) async throws -> [DriverStanding] {
        if !forceRefresh, let cached = await cache.driverStandings(forYear: year) {
            return cached
        }
        let env = try await fetch(MRDataEnvelope<StandingsTableEnvelope>.self, path: "\(year)/driverStandings.json")
        let standings = env.mrData.standingsTable.standingsLists.first?.driverStandings ?? []
        await cache.saveDriverStandings(standings, forYear: year)
        return standings
    }

    func constructorStandings(year: Int, forceRefresh: Bool = false) async throws -> [ConstructorStanding] {
        if !forceRefresh, let cached = await cache.constructorStandings(forYear: year) {
            return cached
        }
        let env = try await fetch(MRDataEnvelope<StandingsTableEnvelope>.self, path: "\(year)/constructorStandings.json")
        let standings = env.mrData.standingsTable.standingsLists.first?.constructorStandings ?? []
        await cache.saveConstructorStandings(standings, forYear: year)
        return standings
    }
}
