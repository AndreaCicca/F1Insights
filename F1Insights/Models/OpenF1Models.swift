import Foundation

// MARK: - OpenF1 API models
//
// OpenF1 (https://openf1.org) exposes real car telemetry the Ergast/Jolpica
// REST surface lacks — including per-car track coordinates (`/location`).
// Coverage starts in 2023. All data used here is historical ("differita").

/// A timed session (we only ever request `session_name == "Race"`).
struct OF1Session: Codable, Sendable {
    let sessionKey: Int
    let sessionName: String
    let dateStart: String        // e.g. "2023-03-05T15:00:00+00:00"
    let dateEnd: String?
    let year: Int
    let countryName: String?
    let circuitShortName: String?

    enum CodingKeys: String, CodingKey {
        case sessionKey = "session_key"
        case sessionName = "session_name"
        case dateStart = "date_start"
        case dateEnd = "date_end"
        case year
        case countryName = "country_name"
        case circuitShortName = "circuit_short_name"
    }
}

/// A driver entry for a session — carries the official team colour (hex).
struct OF1Driver: Codable, Sendable {
    let driverNumber: Int
    let nameAcronym: String?
    let teamColour: String?      // "3671C6" (no leading #)
    let teamName: String?
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case driverNumber = "driver_number"
        case nameAcronym = "name_acronym"
        case teamColour = "team_colour"
        case teamName = "team_name"
        case fullName = "full_name"
    }
}

/// One positional sample of a car on track (~4 Hz).
struct OF1Location: Codable, Sendable {
    let date: String
    let driverNumber: Int
    let x: Double
    let y: Double

    enum CodingKeys: String, CodingKey {
        case date
        case driverNumber = "driver_number"
        case x, y
    }
}
