import SwiftUI

// MARK: - Race replay (shader-embellished lap-by-lap position animation)

/// Animated lap-by-lap position replay. Each driver is a glowing comet trace
/// that draws forward as the race plays; a leading pulse + code label marks the
/// car's current position, and a live leaderboard tracks the running order.
///
/// Multiplatform techniques used:
/// - `speedGrid` Metal `colorEffect` for the animated backdrop.
/// - Neon glow WITHOUT `layerEffect`: a blurred duplicate `Canvas` under a
///   sharp one, composited in a Metal-backed `.drawingGroup()`.
/// - `Canvas` + `TimelineView` + a structured `.task(id:)` loop for smooth playback.
/// - Adaptive layout: pinned transport bar at bottom and scrollable middle area on iPhone.
struct RaceReplayView: View {
    let laps: [Lap]
    let results: [RaceResult]
    let pitStops: [PitStop]
    let loading: Bool
    let load: () async -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selected: Set<String> = []
    @State private var lap: Double = 1
    @State private var playing = false
    @State private var speed: Double = 3          // laps per second
    @State private var isInitialLoad = true

    // MARK: Derived data

    private struct Track: Identifiable {
        let id: String
        let name: String
        let color: Color
        let byLap: [Int: Int]        // lap -> position
        let laps: [Int]              // sorted lap numbers with data
        let pitLaps: Set<Int>
    }

    private var metas: [DriverMeta] {
        let fromResults = driverMetas(from: results)
        if !fromResults.isEmpty { return fromResults }
        guard let firstLap = laps.first else { return [] }
        return firstLap.timings.enumerated().map { idx, t in
            DriverMeta(id: t.driverId, name: t.driverId.capitalized, constructorId: t.driverId, finishPosition: idx + 1)
        }
    }

    private var teamOf: [String: String] {
        Dictionary(results.map { ($0.driver.driverId, $0.constructor.constructorId) },
                   uniquingKeysWith: { a, _ in a })
    }
    private var nameOf: [String: String] {
        Dictionary(results.map { ($0.driver.driverId, $0.driver.displayName) },
                   uniquingKeysWith: { a, _ in a })
    }
    private var pitLapsOf: [String: Set<Int>] {
        var out: [String: Set<Int>] = [:]
        for p in pitStops { if let n = Int(p.lap) { out[p.driverId, default: []].insert(n) } }
        return out
    }

    private var tracks: [Track] {
        var byDriver: [String: [Int: Int]] = [:]
        for l in laps {
            guard let n = Int(l.number) else { continue }
            for t in l.timings {
                guard let p = Int(t.position) else { continue }
                byDriver[t.driverId, default: [:]][n] = p
            }
        }
        return byDriver.compactMap { id, byLap -> Track? in
            guard selected.contains(id) else { return nil }
            return Track(id: id,
                         name: nameOf[id] ?? id.capitalized,
                         color: TeamColor.color(for: teamOf[id] ?? id),
                         byLap: byLap,
                         laps: byLap.keys.sorted(),
                         pitLaps: pitLapsOf[id] ?? [])
        }
    }

    private var maxLap: Int { laps.compactMap { Int($0.number) }.max() ?? 1 }
    private var maxPos: Int {
        laps.flatMap { $0.timings }.compactMap { Int($0.position) }.max() ?? 20
    }

    /// Running order at the current (floored) lap: (position, track).
    private var leaderboard: [(pos: Int, track: Track)] {
        let L = min(maxLap, max(1, Int(lap.rounded(.down))))
        return tracks.compactMap { tr -> (Int, Track)? in
            if let p = tr.byLap[L] { return (p, tr) }
            if let prior = tr.laps.filter({ $0 <= L }).last, let p = tr.byLap[prior] { return (p, tr) }
            return nil
        }
        .sorted { $0.0 < $1.0 }
        .map { (pos: $0.0, track: $0.1) }
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if (loading || isInitialLoad) && laps.isEmpty {
                LoadingView(label: "Loading replay…")
            } else if laps.isEmpty {
                MessageView(systemImage: "flag.checkered",
                            title: "No lap data",
                            subtitle: "Lap-by-lap positions are available from 1996 onward.")
            } else if horizontalSizeClass == .compact {
                VStack(spacing: 8) {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 10) {
                            DriverPicker(metas: metas, selected: $selected)
                            canvas
                                .frame(height: 190)
                            compactLeaderboard
                        }
                        .padding(.bottom, 4)
                    }
                    .scrollIndicators(.hidden)
                    transportBar(forceCompact: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    DriverPicker(metas: metas, selected: $selected)
                    HStack(alignment: .top, spacing: 12) {
                        canvas
                        leaderboardColumn
                    }
                    transportBar(forceCompact: false)
                }
            }
        }
        .task {
            seed()
            await load()
            seed()
            isInitialLoad = false
        }
        .onChange(of: results.count) { _, _ in seed() }
        .onChange(of: laps.count) { _, _ in seed() }
        .task(id: playing) {
            guard playing else { return }
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled && playing {
                try? await Task.sleep(for: .milliseconds(16))
                let now = clock.now
                let dt = Double((now - last).components.attoseconds) / 1e18
                last = now
                lap = min(Double(maxLap), lap + speed * max(0, min(dt, 0.1)))
                if lap >= Double(maxLap) {
                    playing = false
                }
            }
        }
    }

    private func transportBar(forceCompact: Bool) -> some View {
        PlaybackTransportBar(
            isPlaying: playing,
            progressText: "LAP \(Int(lap.rounded())) / \(maxLap)",
            value: $lap,
            range: 1...Double(max(maxLap, 1)),
            speed: $speed,
            speedOptions: [1.0, 2.0, 4.0, 8.0],
            forceCompact: forceCompact,
            onRestart: { lap = 1 },
            onTogglePlay: {
                if lap >= Double(maxLap) { lap = 1 }
                playing.toggle()
            },
            onStepBackward: { lap = max(1, lap - 1) },
            onStepForward: { lap = min(Double(maxLap), lap + 1) }
        )
    }

    // MARK: Canvas (glow + sharp, composited in a drawingGroup)

    private var canvas: some View {
        let mp = max(maxPos, 2)
        let ml = max(maxLap, 2)
        return ZStack {
            // Animated shader backdrop (colorEffect path — stable).
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600)
                Rectangle().colorEffect(
                    ShaderLibrary.speedGrid(.float2(1, 1), .float(Float(t)))
                )
            }

            // Glow: blurred fat strokes under the sharp layer.
            ZStack {
                Canvas { c, size in draw(in: c, size: size, maxPos: mp, maxLap: ml, glow: true) }
                    .blur(radius: 6)
                Canvas { c, size in draw(in: c, size: size, maxPos: mp, maxLap: ml, glow: false) }
            }
            .drawingGroup()      // Metal-backed offscreen composite
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .frame(minWidth: 240, minHeight: 190)
    }

    private func draw(in context: GraphicsContext, size: CGSize,
                      maxPos: Int, maxLap: Int, glow: Bool) {
        let padL: CGFloat = 38, padR: CGFloat = 58, padV: CGFloat = 24
        let plotW = size.width - padL - padR
        let plotH = size.height - padV * 2

        func x(_ l: Double) -> CGFloat { padL + CGFloat((l - 1) / Double(maxLap - 1)) * plotW }
        func y(_ p: Double) -> CGFloat { padV + CGFloat((p - 1) / Double(maxPos - 1)) * plotH }

        // Grid (sharp layer only).
        if !glow {
            for p in stride(from: 1, through: maxPos, by: maxPos > 12 ? 2 : 1) {
                let yy = y(Double(p))
                var line = Path()
                line.move(to: CGPoint(x: padL, y: yy)); line.addLine(to: CGPoint(x: padL + plotW, y: yy))
                context.stroke(line, with: .color(.white.opacity(0.05)), lineWidth: 1)
                context.draw(Text("P\(p)").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5)),
                             at: CGPoint(x: 19, y: yy), anchor: .center)
            }
            for l in stride(from: 5, through: maxLap, by: 5) {
                context.draw(Text("\(l)").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45)),
                             at: CGPoint(x: x(Double(l)), y: size.height - 10), anchor: .center)
            }
            // Playhead.
            let phx = x(lap)
            var ph = Path(); ph.move(to: CGPoint(x: phx, y: padV)); ph.addLine(to: CGPoint(x: phx, y: padV + plotH))
            context.stroke(ph, with: .color(.white.opacity(0.16)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }

        // Comet traces.
        for tr in tracks {
            var pts: [CGPoint] = []
            for n in tr.laps where Double(n) <= lap {
                if let p = tr.byLap[n] { pts.append(CGPoint(x: x(Double(n)), y: y(Double(p)))) }
            }
            if let head = position(of: tr, at: lap) {
                pts.append(CGPoint(x: x(head.lap), y: y(head.pos)))
            }
            guard pts.count >= 1 else { continue }

            // Segment opacity/width ramp: brighter & thicker toward the head.
            if pts.count >= 2 {
                for i in 1..<pts.count {
                    let recency = Double(i) / Double(pts.count - 1)       // 0 old -> 1 head
                    let op = glow ? (0.05 + 0.35 * recency) : (0.18 + 0.82 * recency)
                    let w: CGFloat = glow ? (3 + 6 * recency) : (1.4 + 2.2 * recency)
                    var seg = Path(); seg.move(to: pts[i - 1]); seg.addLine(to: pts[i])
                    context.stroke(seg, with: .color(tr.color.opacity(op)),
                                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
                }
            }

            // Pit-stop markers (sharp layer).
            if !glow {
                for pl in tr.pitLaps where Double(pl) <= lap {
                    guard let p = tr.byLap[pl] else { continue }
                    let c = CGPoint(x: x(Double(pl)), y: y(Double(p)))
                    var d = Path()
                    d.move(to: CGPoint(x: c.x, y: c.y - 4)); d.addLine(to: CGPoint(x: c.x + 4, y: c.y))
                    d.addLine(to: CGPoint(x: c.x + 4, y: c.y)); d.addLine(to: CGPoint(x: c.x - 4, y: c.y)); d.closeSubpath()
                    context.fill(d, with: .color(.white.opacity(0.9)))
                }
            }

            // Head pulse + label.
            if let head = pts.last {
                let r: CGFloat = glow ? 8 : 4.5
                context.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)),
                             with: .color(tr.color.opacity(glow ? 0.6 : 1)))
                if !glow {
                    context.fill(Path(ellipseIn: CGRect(x: head.x - 2, y: head.y - 2, width: 4, height: 4)),
                                 with: .color(.white))
                    context.draw(Text(tr.name).font(.system(size: 13, weight: .bold)).foregroundStyle(tr.color),
                                 at: CGPoint(x: head.x + 11, y: head.y), anchor: .leading)
                }
            }
        }
    }

    /// Interpolated (lap, position) at a fractional lap for smooth motion.
    private func position(of tr: Track, at l: Double) -> (lap: Double, pos: Double)? {
        guard let first = tr.laps.first, Double(first) <= l else { return nil }
        let lo = Int(l.rounded(.down)), hi = lo + 1
        guard let pLo = tr.byLap[lo] else {
            if let prior = tr.laps.filter({ Double($0) <= l }).last, let p = tr.byLap[prior] { return (l, Double(p)) }
            return nil
        }
        let frac = l - Double(lo)
        if let pHi = tr.byLap[hi] { return (l, Double(pLo) + (Double(pHi) - Double(pLo)) * frac) }
        return (l, Double(pLo))
    }

    // MARK: Live leaderboard (iPad / Mac sidebar column)

    private var leaderboardColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ORDER · LAP \(min(maxLap, max(1, Int(lap.rounded()))))")
                .font(.system(size: 12, weight: .heavy)).tracking(1)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(leaderboard, id: \.track.id) { row in
                HStack(spacing: 7) {
                    RollText("\(row.pos)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 2).fill(row.track.color).frame(width: 4, height: 15)
                    RollText(row.track.name, duration: 0.5)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 156)
        .animation(.easeInOut(duration: 0.25), value: leaderboard.map(\.track.id))
    }

    // MARK: Compact Leaderboard (iPhone horizontal chips)

    private var compactLeaderboard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ORDER · LAP \(min(maxLap, max(1, Int(lap.rounded()))))")
                .font(.system(size: 11, weight: .heavy)).tracking(1)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(leaderboard, id: \.track.id) { row in
                        HStack(spacing: 6) {
                            Text("P\(row.pos)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(row.track.color)
                                .frame(width: 3, height: 12)
                            Text(row.track.name)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func seed() {
        guard selected.isEmpty else { return }
        if !results.isEmpty {
            selected = Set(results.map { $0.driver.driverId })
        } else if let firstLap = laps.first {
            selected = Set(firstLap.timings.map(\.driverId))
        }
    }
}
