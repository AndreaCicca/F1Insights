import Foundation
import simd

/// Thread-safe two-tier cache (L1 in-memory + L2 persistent on-disk in Caches directory)
/// for API responses and pre-processed visualization datasets.
actor LocalDataCache {
    static let shared = LocalDataCache()

    // MARK: - Serializable Track Map Models

    struct CachedDriverTrack: Codable, Sendable {
        let code: String
        let colorR: Float
        let colorG: Float
        let colorB: Float
        let colorA: Float
        let timesData: Data
        let ptsData: Data

        var color: SIMD4<Float> {
            SIMD4<Float>(colorR, colorG, colorB, colorA)
        }

        var times: [Double] {
            LocalDataCache.decodeArray(Double.self, from: timesData)
        }

        var pts: [SIMD2<Float>] {
            LocalDataCache.decodeArray(SIMD2<Float>.self, from: ptsData)
        }

        init(code: String, color: SIMD4<Float>, times: [Double], pts: [SIMD2<Float>]) {
            self.code = code
            self.colorR = color.x
            self.colorG = color.y
            self.colorB = color.z
            self.colorA = color.w
            self.timesData = LocalDataCache.encodeArray(times)
            self.ptsData = LocalDataCache.encodeArray(pts)
        }
    }

    struct CachedTrackMapEnvelope: Codable, Sendable {
        let outlineData: Data
        let drivers: [CachedDriverTrack]
        let duration: Double

        func toDecoded() -> DecodedTrackMap {
            let outline = LocalDataCache.decodeArray(SIMD2<Float>.self, from: outlineData)
            let decodedDrivers = drivers.map { d in
                DecodedDriverTrack(
                    code: d.code,
                    color: d.color,
                    times: d.times,
                    pts: d.pts
                )
            }
            return DecodedTrackMap(outline: outline, drivers: decodedDrivers, duration: duration)
        }

        init(from decoded: DecodedTrackMap) {
            self.outlineData = LocalDataCache.encodeArray(decoded.outline)
            self.drivers = decoded.drivers.map {
                CachedDriverTrack(code: $0.code, color: $0.color, times: $0.times, pts: $0.pts)
            }
            self.duration = decoded.duration
        }
    }

    struct DecodedDriverTrack: Sendable {
        let code: String
        let color: SIMD4<Float>
        let times: [Double]
        let pts: [SIMD2<Float>]
    }

    struct DecodedTrackMap: Sendable {
        let outline: [SIMD2<Float>]
        let drivers: [DecodedDriverTrack]
        let duration: Double
    }

    // MARK: - L1 In-Memory Storage

    private var schedulesByYear: [Int: [Race]] = [:]
    private var driverStandingsByYear: [Int: [DriverStanding]] = [:]
    private var constructorStandingsByYear: [Int: [ConstructorStanding]] = [:]

    private var raceResultsByKey: [String: Race] = [:]
    private var qualifyingByKey: [String: [QualifyingResult]] = [:]
    private var pitStopsByKey: [String: [PitStop]] = [:]
    private var lapsByKey: [String: [Lap]] = [:]

    private var of1SessionsByYear: [Int: [OF1Session]] = [:]
    private var of1DriversBySession: [Int: [OF1Driver]] = [:]
    private var trackMapByRaceID: [String: DecodedTrackMap] = [:]

    // MARK: - L2 Disk Configuration

    private let cacheDirectory: URL
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    private let plistEncoder: PropertyListEncoder = {
        let e = PropertyListEncoder()
        e.outputFormat = .binary
        return e
    }()
    private let plistDecoder = PropertyListDecoder()

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("F1InsightsCache_v1", isDirectory: true)
        self.cacheDirectory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Season Schedule

    func schedule(forYear year: Int) -> [Race]? {
        if let mem = schedulesByYear[year] { return mem }
        if let disk = readJSON([Race].self, filename: "schedule_\(year).json"), !disk.isEmpty {
            schedulesByYear[year] = disk
            return disk
        }
        return nil
    }

    func saveSchedule(_ races: [Race], forYear year: Int) {
        guard !races.isEmpty else { return }
        schedulesByYear[year] = races
        writeJSON(races, filename: "schedule_\(year).json")
    }

    // MARK: - Standings

    func driverStandings(forYear year: Int) -> [DriverStanding]? {
        if let mem = driverStandingsByYear[year] { return mem }
        if let disk = readJSON([DriverStanding].self, filename: "driver_standings_\(year).json"), !disk.isEmpty {
            driverStandingsByYear[year] = disk
            return disk
        }
        return nil
    }

    func saveDriverStandings(_ standings: [DriverStanding], forYear year: Int) {
        guard !standings.isEmpty else { return }
        driverStandingsByYear[year] = standings
        writeJSON(standings, filename: "driver_standings_\(year).json")
    }

    func constructorStandings(forYear year: Int) -> [ConstructorStanding]? {
        if let mem = constructorStandingsByYear[year] { return mem }
        if let disk = readJSON([ConstructorStanding].self, filename: "constructor_standings_\(year).json"), !disk.isEmpty {
            constructorStandingsByYear[year] = disk
            return disk
        }
        return nil
    }

    func saveConstructorStandings(_ standings: [ConstructorStanding], forYear year: Int) {
        guard !standings.isEmpty else { return }
        constructorStandingsByYear[year] = standings
        writeJSON(standings, filename: "constructor_standings_\(year).json")
    }

    // MARK: - Race Core Details (Results, Qualifying, Pit Stops)

    private func raceKey(year: Int, round: Int) -> String { "\(year)-\(round)" }

    func raceResults(year: Int, round: Int) -> Race? {
        let key = raceKey(year: year, round: round)
        if let mem = raceResultsByKey[key] { return mem }
        if let disk = readJSON(Race.self, filename: "results_\(year)_\(round).json"),
           !(disk.results ?? []).isEmpty {
            raceResultsByKey[key] = disk
            return disk
        }
        return nil
    }

    func saveRaceResults(_ race: Race, year: Int, round: Int) {
        guard !(race.results ?? []).isEmpty else { return }
        let key = raceKey(year: year, round: round)
        raceResultsByKey[key] = race
        writeJSON(race, filename: "results_\(year)_\(round).json")
    }

    func qualifying(year: Int, round: Int) -> [QualifyingResult]? {
        let key = raceKey(year: year, round: round)
        if let mem = qualifyingByKey[key] { return mem }
        if let disk = readJSON([QualifyingResult].self, filename: "qualifying_\(year)_\(round).json"),
           !disk.isEmpty {
            qualifyingByKey[key] = disk
            return disk
        }
        return nil
    }

    func saveQualifying(_ qualifying: [QualifyingResult], year: Int, round: Int) {
        guard !qualifying.isEmpty else { return }
        let key = raceKey(year: year, round: round)
        qualifyingByKey[key] = qualifying
        writeJSON(qualifying, filename: "qualifying_\(year)_\(round).json")
    }

    func pitStops(year: Int, round: Int) -> [PitStop]? {
        let key = raceKey(year: year, round: round)
        if let mem = pitStopsByKey[key] { return mem }
        if let disk = readJSON([PitStop].self, filename: "pitstops_\(year)_\(round).json"),
           !disk.isEmpty {
            pitStopsByKey[key] = disk
            return disk
        }
        return nil
    }

    func savePitStops(_ pitStops: [PitStop], year: Int, round: Int) {
        guard !pitStops.isEmpty else { return }
        let key = raceKey(year: year, round: round)
        pitStopsByKey[key] = pitStops
        writeJSON(pitStops, filename: "pitstops_\(year)_\(round).json")
    }

    // MARK: - Lap Times

    func lapTimes(year: Int, round: Int) -> [Lap]? {
        let key = raceKey(year: year, round: round)
        if let mem = lapsByKey[key] { return mem }
        if let disk = readPlist([Lap].self, filename: "laps_\(year)_\(round).plist"),
           !disk.isEmpty {
            lapsByKey[key] = disk
            return disk
        }
        return nil
    }

    func saveLapTimes(_ laps: [Lap], year: Int, round: Int) {
        guard !laps.isEmpty else { return }
        let key = raceKey(year: year, round: round)
        lapsByKey[key] = laps
        writePlist(laps, filename: "laps_\(year)_\(round).plist")
    }

    // MARK: - OpenF1 & Track Map Telemetry

    func openF1Sessions(forYear year: Int) -> [OF1Session]? {
        if let mem = of1SessionsByYear[year] { return mem }
        if let disk = readJSON([OF1Session].self, filename: "of1_sessions_\(year).json"),
           !disk.isEmpty {
            of1SessionsByYear[year] = disk
            return disk
        }
        return nil
    }

    func saveOpenF1Sessions(_ sessions: [OF1Session], forYear year: Int) {
        guard !sessions.isEmpty else { return }
        of1SessionsByYear[year] = sessions
        writeJSON(sessions, filename: "of1_sessions_\(year).json")
    }

    func openF1Drivers(sessionKey: Int) -> [OF1Driver]? {
        if let mem = of1DriversBySession[sessionKey] { return mem }
        if let disk = readJSON([OF1Driver].self, filename: "of1_drivers_\(sessionKey).json"),
           !disk.isEmpty {
            of1DriversBySession[sessionKey] = disk
            return disk
        }
        return nil
    }

    func saveOpenF1Drivers(_ drivers: [OF1Driver], sessionKey: Int) {
        guard !drivers.isEmpty else { return }
        of1DriversBySession[sessionKey] = drivers
        writeJSON(drivers, filename: "of1_drivers_\(sessionKey).json")
    }

    func trackMap(forRaceID raceID: String) -> DecodedTrackMap? {
        if let mem = trackMapByRaceID[raceID] { return mem }
        let safeID = raceID.replacingOccurrences(of: "/", with: "_")
        if let env = readPlist(CachedTrackMapEnvelope.self, filename: "trackmap_\(safeID).plist") {
            let decoded = env.toDecoded()
            if !decoded.drivers.isEmpty {
                trackMapByRaceID[raceID] = decoded
                return decoded
            }
        }
        return nil
    }

    func saveTrackMap(_ trackMap: DecodedTrackMap, forRaceID raceID: String) {
        guard !trackMap.drivers.isEmpty else { return }
        trackMapByRaceID[raceID] = trackMap
        let safeID = raceID.replacingOccurrences(of: "/", with: "_")
        let env = CachedTrackMapEnvelope(from: trackMap)
        writePlist(env, filename: "trackmap_\(safeID).plist")
    }

    // MARK: - Invalidation

    func invalidateSeason(_ year: Int) {
        schedulesByYear.removeValue(forKey: year)
        driverStandingsByYear.removeValue(forKey: year)
        constructorStandingsByYear.removeValue(forKey: year)
        removeFile("schedule_\(year).json")
        removeFile("driver_standings_\(year).json")
        removeFile("constructor_standings_\(year).json")
    }

    // MARK: - Disk Helpers

    private func fileURL(_ filename: String) -> URL {
        cacheDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    private func readJSON<T: Decodable>(_ type: T.Type, filename: String) -> T? {
        let url = fileURL(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? jsonDecoder.decode(T.self, from: data)
    }

    private func writeJSON<T: Encodable>(_ value: T, filename: String) {
        let url = fileURL(filename)
        guard let data = try? jsonEncoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func readPlist<T: Decodable>(_ type: T.Type, filename: String) -> T? {
        let url = fileURL(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? plistDecoder.decode(T.self, from: data)
    }

    private func writePlist<T: Encodable>(_ value: T, filename: String) {
        let url = fileURL(filename)
        guard let data = try? plistEncoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func removeFile(_ filename: String) {
        try? FileManager.default.removeItem(at: fileURL(filename))
    }

    // MARK: - Contiguous Binary Array Helpers

    nonisolated static func encodeArray<T>(_ array: [T]) -> Data {
        array.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    nonisolated static func decodeArray<T>(_ type: T.Type, from data: Data) -> [T] {
        let stride = MemoryLayout<T>.stride
        guard stride > 0, !data.isEmpty, data.count % stride == 0 else { return [] }
        let count = data.count / stride
        return [T](unsafeUninitializedCapacity: count) { buffer, initializedCount in
            _ = data.copyBytes(to: buffer)
            initializedCount = count
        }
    }
}

