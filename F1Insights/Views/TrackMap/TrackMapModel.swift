import SwiftUI
import simd

/// Coordinates and deduplicates in-flight Track Map telemetry downloads and
/// performs heavy 500k-point parsing off the main actor.
private actor TrackMapCoordinator {
    static let shared = TrackMapCoordinator()

    enum Outcome: Sendable {
        case empty(String)
        case ready(LocalDataCache.DecodedTrackMap)
    }

    private struct ParsedSample: Sendable {
        let driverNumber: Int
        let time: Double
        let pt: SIMD2<Float>
    }

    private let api = OpenF1Client.shared
    private let cache = LocalDataCache.shared
    private let chunkLength: Double = 900     // 15 min per slice
    private let maxParallel = 4

    private var inFlight: [String: Task<Outcome, Error>] = [:]

    func loadOrBuild(race: Race, year: Int) async throws -> Outcome {
        if let cached = await cache.trackMap(forRaceID: race.id) {
            return .ready(cached)
        }
        if let existing = inFlight[race.id] {
            return try await existing.value
        }

        let task = Task<Outcome, Error> { [api, cache, chunkLength, maxParallel] in
            // 1) Resolve the Race session for this round by date match.
            let sessions = try await api.raceSessions(year: year)
            guard let session = sessions.first(where: { $0.dateStart.hasPrefix(race.date) }),
                  let start = TrackMapModel.parseSessionStart(session.dateStart) else {
                return .empty("No OpenF1 session found for this race.")
            }

            // 2) Build time windows [start, end] and fetch driver roster concurrently.
            let key = session.sessionKey
            let end = TrackMapModel.parseSessionStart(session.dateEnd ?? "")
                ?? start.addingTimeInterval(2.5 * 3600)
            var windows: [(String, String)] = []
            var cursor = start
            while cursor < end {
                let next = min(cursor.addingTimeInterval(chunkLength), end)
                windows.append((TrackMapModel.utc(cursor), TrackMapModel.utc(next)))
                cursor = next
            }

            let roster = try await api.drivers(sessionKey: key)
            guard !roster.isEmpty else { return .empty("No driver data.") }
            let byNumber = Dictionary(roster.map { ($0.driverNumber, $0) },
                                      uniquingKeysWith: { a, _ in a })

            // 3) Sliding-window parallel fetch + immediate background timestamp parsing.
            let samples: [ParsedSample] = await withTaskGroup(of: [ParsedSample].self) { group in
                var idx = 0
                let initial = min(maxParallel, windows.count)
                while idx < initial {
                    let (s, e) = windows[idx]
                    idx += 1
                    group.addTask {
                        let raw = (try? await api.location(sessionKey: key, startUTC: s, endUTC: e)) ?? []
                        return raw.map {
                            ParsedSample(
                                driverNumber: $0.driverNumber,
                                time: TrackMapModel.seconds($0.date),
                                pt: SIMD2<Float>(Float($0.x), Float($0.y))
                            )
                        }
                    }
                }

                var acc: [ParsedSample] = []
                acc.reserveCapacity(windows.count * 25_000)
                for await chunk in group {
                    acc.append(contentsOf: chunk)
                    if idx < windows.count {
                        let (s, e) = windows[idx]
                        idx += 1
                        group.addTask {
                            let raw = (try? await api.location(sessionKey: key, startUTC: s, endUTC: e)) ?? []
                            return raw.map {
                                ParsedSample(
                                    driverNumber: $0.driverNumber,
                                    time: TrackMapModel.seconds($0.date),
                                    pt: SIMD2<Float>(Float($0.x), Float($0.y))
                                )
                            }
                        }
                    }
                }
                return acc
            }

            guard !samples.isEmpty else {
                return .empty("No track positions for this race (telemetry gap).")
            }

            // 4) Single-pass min/max time & grouping by driver off the main thread.
            var t0 = Double.greatestFiniteMagnitude
            var tEnd = -Double.greatestFiniteMagnitude
            var grouped: [Int: [ParsedSample]] = [:]
            grouped.reserveCapacity(24)

            for s in samples {
                if s.time < t0 { t0 = s.time }
                if s.time > tEnd { tEnd = s.time }
                grouped[s.driverNumber, default: []].append(s)
            }

            guard t0 <= tEnd else {
                return .empty("No track positions for this race.")
            }
            let duration = max(tEnd - t0, 0.1)

            // 5) Sort each driver's trajectory and build serializable DecodedTrackMap.
            var decodedDrivers: [LocalDataCache.DecodedDriverTrack] = []
            decodedDrivers.reserveCapacity(grouped.count)

            for number in grouped.keys.sorted() {
                guard var list = grouped[number], list.count > 1 else { continue }
                list.sort { $0.time < $1.time }

                var times = [Double]()
                var pts = [SIMD2<Float>]()
                times.reserveCapacity(list.count)
                pts.reserveCapacity(list.count)
                for item in list {
                    times.append(item.time - t0)
                    pts.append(item.pt)
                }

                let drv = byNumber[number]
                let c = TrackMapModel.color(hex: drv?.teamColour)
                let code = drv?.nameAcronym ?? "\(number)"
                decodedDrivers.append(
                    LocalDataCache.DecodedDriverTrack(code: code, color: c, times: times, pts: pts)
                )
            }

            guard !decodedDrivers.isEmpty else {
                return .empty("No usable track positions for this race.")
            }

            let outline = decodedDrivers.max(by: { $0.pts.count < $1.pts.count })?.pts ?? []
            let decoded = LocalDataCache.DecodedTrackMap(
                outline: outline,
                drivers: decodedDrivers,
                duration: duration
            )
            await cache.saveTrackMap(decoded, forRaceID: race.id)
            return .ready(decoded)
        }

        inFlight[race.id] = task
        defer { inFlight.removeValue(forKey: race.id) }
        return try await task.value
    }
}

/// Loads and prepares OpenF1 track-map data for one race.
///
/// Pipeline: check local cache (L1 memory / L2 binary disk) → otherwise resolve
/// `session_key` → fetch driver roster → fetch & parse bounded location windows
/// in parallel off the main thread → persist to local cache for instant reuse.
@MainActor
@Observable
final class TrackMapModel {

    enum State: Equatable {
        case idle
        case unsupported          // season < 2023
        case loading
        case empty(String)
        case failed(String)
        case ready
    }

    struct DriverTrack: Identifiable, Equatable {
        let id: String
        let code: String
        let color: Color
        let times: [Double]
        let pts: [SIMD2<Float>]

        /// Binary-search + linear interpolation of the car's position at time `t`.
        func position(at t: Double) -> SIMD2<Float>? {
            guard !times.isEmpty, times.count == pts.count else { return nil }
            if t <= times[0] { return pts[0] }
            if let last = times.last, t >= last { return pts[pts.count - 1] }

            var lo = 0, hi = times.count - 1
            while lo + 1 < hi {
                let mid = (lo + hi) >> 1
                if times[mid] <= t { lo = mid } else { hi = mid }
            }
            let dt = times[hi] - times[lo]
            let f = dt > 0 ? Float((t - times[lo]) / dt) : 0
            return pts[lo] + (pts[hi] - pts[lo]) * f
        }
    }

    struct LegendItem: Identifiable, Equatable {
        var id: String { code }
        let code: String
        let color: Color
    }

    struct Payload: Equatable {
        let outline: [SIMD2<Float>]
        let drivers: [DriverTrack]
        let duration: Double
        let center: SIMD2<Float>
        let extent: SIMD2<Float>
    }

    private(set) var state: State = .idle
    private(set) var legend: [LegendItem] = []
    private(set) var token = 0
    private(set) var payload: Payload?
    private var loadedRaceID: String?

    func load(race: Race) async {
        if loadedRaceID == race.id, state == .ready, payload != nil {
            return
        }

        guard let year = Int(race.season), year >= 2023 else {
            loadedRaceID = race.id
            payload = nil
            legend = []
            state = .unsupported
            return
        }

        // Fast path: check local cache before resetting state to .loading
        if let cached = await LocalDataCache.shared.trackMap(forRaceID: race.id) {
            apply(decoded: cached, raceID: race.id)
            return
        }

        await Task.yield()
        payload = nil
        legend = []
        state = .loading

        do {
            let outcome = try await TrackMapCoordinator.shared.loadOrBuild(race: race, year: year)
            switch outcome {
            case .empty(let reason):
                loadedRaceID = race.id
                state = .empty(reason)
            case .ready(let decoded):
                apply(decoded: decoded, raceID: race.id)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func apply(decoded: LocalDataCache.DecodedTrackMap, raceID: String) {
        let drivers: [DriverTrack] = decoded.drivers.enumerated().map { idx, d in
            let swiftColor = Color(
                .sRGB,
                red: Double(d.color.x),
                green: Double(d.color.y),
                blue: Double(d.color.z)
            )
            return DriverTrack(
                id: "\(d.code)-\(idx)",
                code: d.code,
                color: swiftColor,
                times: d.times,
                pts: d.pts
            )
        }
        let legendRows = drivers.map { LegendItem(code: $0.code, color: $0.color) }

        // Downsample track outline if huge so SwiftUI Canvas path construction stays instantaneous
        let rawOutline = decoded.outline
        let step = max(1, rawOutline.count / 1_800)
        let sampledOutline: [SIMD2<Float>] = step > 1
            ? stride(from: 0, to: rawOutline.count, by: step).map { rawOutline[$0] }
            : rawOutline

        // Precompute bounding box for aspect-fit projection
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for p in sampledOutline {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        let center = (lo + hi) * 0.5
        let extent = simd_max(hi - lo, SIMD2<Float>(repeating: 1))

        loadedRaceID = raceID
        payload = Payload(
            outline: sampledOutline,
            drivers: drivers,
            duration: max(decoded.duration, 0.1),
            center: center,
            extent: extent
        )
        legend = legendRows
        token &+= 1
        state = .ready
    }

    // MARK: - Parsing helpers

    nonisolated static func parseSessionStart(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    nonisolated static func utc(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    /// Fast parse of "YYYY-MM-DDTHH:MM:SS.ffffff±zz:zz" to seconds. Only relative
    /// values matter (all deltas share the same day base), so the day-of-month is
    /// folded into the base — races never cross a month boundary. ISO8601
    /// formatters are far too slow across ~500k rows.
    nonisolated static func seconds(_ s: String) -> Double {
        let a = Array(s.utf8)
        guard a.count >= 19 else { return 0 }
        func d(_ i: Int) -> Double { Double(a[i] - 48) }        // '0' == 48
        let day  = d(8) * 10 + d(9)
        let hh   = d(11) * 10 + d(12)
        let mm   = d(14) * 10 + d(15)
        let ss   = d(17) * 10 + d(18)
        var frac = 0.0
        if a.count > 20, a[19] == 46 {                          // '.'
            var scale = 0.1, i = 20
            while i < a.count, a[i] >= 48, a[i] <= 57 {
                frac += Double(a[i] - 48) * scale; scale *= 0.1; i += 1
            }
        }
        return day * 86_400 + hh * 3_600 + mm * 60 + ss + frac
    }

    nonisolated static func color(hex: String?) -> SIMD4<Float> {
        guard let h = hex, h.count == 6, let v = Int(h, radix: 16) else {
            return SIMD4(0.80, 0.82, 0.88, 1)
        }
        return SIMD4(Float((v >> 16) & 0xff) / 255,
                     Float((v >> 8) & 0xff) / 255,
                     Float(v & 0xff) / 255, 1)
    }
}
