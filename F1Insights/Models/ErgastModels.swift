import Foundation

// MARK: - Envelope

/// Root of every Ergast / Jolpica JSON response.
struct MRDataEnvelope<Table: Decodable & Sendable>: Decodable, Sendable {
    let mrData: Table

    enum CodingKeys: String, CodingKey { case mrData = "MRData" }
}

/// Ergast returns pagination hints at the MRData level; decoded when needed.
struct Pagination: Decodable, Sendable {
    let total: Int
    let limit: Int
    let offset: Int

    enum CodingKeys: String, CodingKey { case total, limit, offset }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = Int(try c.decode(String.self, forKey: .total)) ?? 0
        limit = Int(try c.decode(String.self, forKey: .limit)) ?? 0
        offset = Int(try c.decode(String.self, forKey: .offset)) ?? 0
    }
}

// MARK: - Season schedule

struct RaceTableEnvelope: Decodable, Sendable {
    let raceTable: RaceTable
    let pagination: Pagination

    enum CodingKeys: String, CodingKey { case raceTable = "RaceTable" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        raceTable = try c.decode(RaceTable.self, forKey: .raceTable)
        pagination = try Pagination(from: decoder)
    }
}

struct RaceTable: Decodable, Sendable {
    let season: String?
    let races: [Race]

    enum CodingKeys: String, CodingKey { case season, races = "Races" }
}

struct Race: Codable, Identifiable, Hashable, Sendable {
    let season: String
    let round: String
    let raceName: String
    let circuit: Circuit
    let date: String
    let time: String?
    let results: [RaceResult]?
    let qualifyingResults: [QualifyingResult]?
    let laps: [Lap]?
    let pitStops: [PitStop]?

    var id: String { "\(season)-\(round)" }

    enum CodingKeys: String, CodingKey {
        case season, round, raceName, date, time
        case circuit = "Circuit"
        case results = "Results"
        case qualifyingResults = "QualifyingResults"
        case laps = "Laps"
        case pitStops = "PitStops"
    }

    static func == (lhs: Race, rhs: Race) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let dateOnlyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        return df
    }()

    /// Combined date+time as a `Date` when both are present.
    var startDate: Date? {
        if let time { return Self.isoFormatter.date(from: "\(date)T\(time)") }
        return Self.dateOnlyFormatter.date(from: date)
    }

    /// Checks whether the race name, circuit, or country matches a search string.
    func matches(query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return raceName.localizedCaseInsensitiveContains(query) ||
            circuit.circuitName.localizedCaseInsensitiveContains(query) ||
            (circuit.location.country?.localizedCaseInsensitiveContains(query) ?? false)
    }
}

extension Collection where Element == Race {
    /// Returns the earliest upcoming race after `now`, or nil if all races have passed.
    func nextUpcoming(after now: Date = .now) -> Race? {
        self.filter { ($0.startDate ?? .distantPast) > now }
            .min { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }
}

struct Circuit: Codable, Hashable, Sendable {
    let circuitId: String
    let circuitName: String
    let location: Location

    enum CodingKeys: String, CodingKey {
        case circuitId, circuitName
        case location = "Location"
    }
}

struct Location: Codable, Hashable, Sendable {
    let locality: String?
    let country: String?
    let lat: String?
    let long: String?
}

// MARK: - Drivers & constructors

struct Driver: Codable, Identifiable, Hashable, Sendable {
    let driverId: String
    let permanentNumber: String?
    let code: String?
    let givenName: String
    let familyName: String
    let dateOfBirth: String?
    let nationality: String?

    var id: String { driverId }
    var fullName: String { "\(givenName) \(familyName)" }
    var displayName: String { code ?? familyName }
}

struct Constructor: Codable, Identifiable, Hashable, Sendable {
    let constructorId: String
    let name: String
    let nationality: String?

    var id: String { constructorId }
}

// MARK: - Results

struct RaceResult: Codable, Identifiable, Hashable, Sendable {
    let number: String?
    let position: String
    let positionText: String
    let points: String
    let driver: Driver
    let constructor: Constructor
    let grid: String?
    let laps: String?
    let status: String
    let time: TimeValue?
    let fastestLap: FastestLap?

    var id: String { driver.driverId }

    enum CodingKeys: String, CodingKey {
        case number, position, positionText, points, grid, laps, status
        case driver = "Driver"
        case constructor = "Constructor"
        case time = "Time"
        case fastestLap = "FastestLap"
    }
}

struct TimeValue: Codable, Hashable, Sendable {
    let millis: String?
    let time: String?
}

struct FastestLap: Codable, Hashable, Sendable {
    let rank: String?
    let lap: String?
    let time: TimeValue?
    let averageSpeed: AverageSpeed?

    enum CodingKeys: String, CodingKey {
        case rank, lap
        case time = "Time"
        case averageSpeed = "AverageSpeed"
    }
}

struct AverageSpeed: Codable, Hashable, Sendable {
    let units: String?
    let speed: String?
}

// MARK: - Qualifying

struct QualifyingResult: Codable, Identifiable, Hashable, Sendable {
    let number: String?
    let position: String
    let driver: Driver
    let constructor: Constructor
    let q1: String?
    let q2: String?
    let q3: String?

    var id: String { driver.driverId }

    enum CodingKeys: String, CodingKey {
        case number, position
        case driver = "Driver"
        case constructor = "Constructor"
        case q1 = "Q1"
        case q2 = "Q2"
        case q3 = "Q3"
    }
}

// MARK: - Laps & pit stops

struct Lap: Codable, Hashable, Sendable {
    let number: String
    let timings: [Timing]

    enum CodingKeys: String, CodingKey { case number, timings = "Timings" }
}

struct Timing: Codable, Hashable, Sendable {
    let driverId: String
    let position: String
    let time: String
}

struct PitStop: Codable, Identifiable, Hashable, Sendable {
    let driverId: String
    let lap: String
    let stop: String
    let time: String
    let duration: String?

    var id: String { "\(driverId)-\(stop)" }
}

// MARK: - Standings

struct StandingsTableEnvelope: Decodable, Sendable {
    let standingsTable: StandingsTable

    enum CodingKeys: String, CodingKey { case standingsTable = "StandingsTable" }
}

struct StandingsTable: Decodable, Sendable {
    let season: String?
    let standingsLists: [StandingsList]

    enum CodingKeys: String, CodingKey { case season, standingsLists = "StandingsLists" }
}

struct StandingsList: Decodable, Sendable {
    let season: String
    let round: String
    let driverStandings: [DriverStanding]?
    let constructorStandings: [ConstructorStanding]?

    enum CodingKeys: String, CodingKey {
        case season, round
        case driverStandings = "DriverStandings"
        case constructorStandings = "ConstructorStandings"
    }
}

struct DriverStanding: Codable, Identifiable, Hashable, Sendable {
    let position: String?
    let points: String
    let wins: String
    let driver: Driver
    let constructors: [Constructor]

    var id: String { driver.driverId }

    enum CodingKeys: String, CodingKey {
        case position, points, wins
        case driver = "Driver"
        case constructors = "Constructors"
    }
}

struct ConstructorStanding: Codable, Identifiable, Hashable, Sendable {
    let position: String?
    let points: String
    let wins: String
    let constructor: Constructor

    var id: String { constructor.constructorId }

    enum CodingKeys: String, CodingKey {
        case position, points, wins
        case constructor = "Constructor"
    }
}

// MARK: - Sorting & UI Helpers

extension RaceResult {
    var positionInt: Int { Int(position) ?? 99 }
    var pointsDouble: Double { Double(points) ?? 0 }
    var gridInt: Int { Int(grid ?? "") ?? 99 }
    var lapsInt: Int { Int(laps ?? "") ?? 0 }
    var gridDelta: Int? {
        guard let g = Int(grid ?? ""), g > 0, let p = Int(position) else { return nil }
        return g - p
    }

    private static let dnfKeywords = [
        "collision", "engine", "accident", "retired", "damage", "gearbox", "suspension", "spun"
    ]

    var isDNF: Bool {
        Self.dnfKeywords.contains { status.localizedCaseInsensitiveContains($0) }
    }
}

extension QualifyingResult {
    var positionInt: Int { Int(position) ?? 99 }
    var bestTime: String { q3 ?? q2 ?? q1 ?? "—" }
}

