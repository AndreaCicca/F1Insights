import Foundation

/// Thin async client over the OpenF1 REST API (no auth, JSON, historical data).
///
/// Used only for the Track Map feature — everything else in the app stays on
/// Jolpica. `/location` is heavy, so callers always fetch a bounded time window.
actor OpenF1Client {
    static let shared = OpenF1Client()

    private let base = "https://api.openf1.org/v1"
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let cache = LocalDataCache.shared

    init(session: URLSession = .shared) { self.session = session }

    private func get<T: Decodable & Sendable>(_ type: T.Type, urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw F1APIError.badURL }
        return try await session.decode(T.self, from: url, decoder: decoder)
    }

    /// All race sessions in a season (used to resolve a `session_key`).
    func raceSessions(year: Int) async throws -> [OF1Session] {
        if let cached = await cache.openF1Sessions(forYear: year) {
            return cached
        }
        let sessions = try await get([OF1Session].self, urlString: "\(base)/sessions?year=\(year)&session_name=Race")
        await cache.saveOpenF1Sessions(sessions, forYear: year)
        return sessions
    }

    /// Drivers registered for a session (numbers, acronyms, team colours).
    func drivers(sessionKey: Int) async throws -> [OF1Driver] {
        if let cached = await cache.openF1Drivers(sessionKey: sessionKey) {
            return cached
        }
        let roster = try await get([OF1Driver].self, urlString: "\(base)/drivers?session_key=\(sessionKey)")
        await cache.saveOpenF1Drivers(roster, sessionKey: sessionKey)
        return roster
    }

    /// Location samples inside a UTC time window. Omit `driverNumber` to get
    /// **all** cars in a single request — far lighter than 20 parallel calls
    /// (which OpenF1 rate-limits) and returns everyone at once.
    /// `startUTC` / `endUTC` are naive UTC strings: "yyyy-MM-dd'T'HH:mm:ss".
    /// `>` / `<` are sent url-encoded (`%3E` / `%3C`) — the form OpenF1 accepts.
    func location(sessionKey: Int, driverNumber: Int? = nil,
                  startUTC: String, endUTC: String) async throws -> [OF1Location] {
        var s = "\(base)/location?session_key=\(sessionKey)"
        if let n = driverNumber { s += "&driver_number=\(n)" }
        s += "&date%3E=\(startUTC)&date%3C=\(endUTC)"
        return try await get([OF1Location].self, urlString: s)
    }
}
