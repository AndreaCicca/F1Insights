import SwiftUI
import simd

/// Track Map tab: real car positions on the circuit, rendered natively with SwiftUI `Canvas`
/// and Metal-backed `.drawingGroup()`.
/// Data via OpenF1 (`/location`), 2023 onward, historical playback.
struct TrackMapView: View {
    let race: Race

    @State private var model = TrackMapModel()
    @State private var displayTime: Double = 0
    @State private var isPlaying = false
    @State private var speed: Double = 20

    private func clock(_ t: Double) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }

    private var duration: Double {
        model.payload?.duration ?? 0.1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.state {
            case .idle, .loading:
                LoadingView(label: "Loading track telemetry…")
            case .unsupported:
                MessageView(systemImage: "map",
                            title: "Track map needs 2023+",
                            subtitle: "OpenF1 car positions only exist from 2023 onward.")
            case .empty(let why):
                MessageView(systemImage: "mappin.slash", title: "No track data", subtitle: why)
            case .failed(let msg):
                MessageView(systemImage: "exclamationmark.triangle", title: "Couldn’t load", subtitle: msg)
            case .ready:
                legendStrip
                mapArea
                PlaybackTransportBar(
                    isPlaying: isPlaying,
                    progressText: "\(clock(displayTime)) / \(clock(duration))",
                    value: $displayTime,
                    range: 0...max(duration, 0.1),
                    speed: $speed,
                    speedOptions: [5.0, 20.0, 60.0],
                    onRestart: { displayTime = 0 },
                    onTogglePlay: {
                        if displayTime >= duration { displayTime = 0 }
                        isPlaying.toggle()
                    }
                )
            }
        }
        .task(id: race.id) {
            isPlaying = false
            displayTime = 0
            await model.load(race: race)
            if model.state == .ready {
                isPlaying = true
            }
        }
        .onChange(of: model.token) { _, _ in
            displayTime = 0
            isPlaying = model.state == .ready
        }
        .task(id: isPlaying) {
            guard isPlaying else { return }
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled && isPlaying {
                try? await Task.sleep(for: .milliseconds(16))
                let now = clock.now
                let dt = Double((now - last).components.attoseconds) / 1e18
                last = now
                let next = displayTime + max(0, min(dt, 0.1)) * speed
                if next >= duration {
                    displayTime = duration
                    isPlaying = false
                } else {
                    displayTime = next
                }
            }
        }
        .onDisappear {
            isPlaying = false
        }
    }

    private var mapArea: some View {
        ZStack {
            Color(red: 0.055, green: 0.060, blue: 0.082)

            Canvas { context, size in
                guard let payload = model.payload else { return }
                drawTrackMap(in: context, size: size, payload: payload, time: displayTime)
            }
            .drawingGroup()
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .frame(minHeight: 360)
    }

    private func drawTrackMap(
        in context: GraphicsContext,
        size: CGSize,
        payload: TrackMapModel.Payload,
        time: Double
    ) {
        let pad: CGFloat = 28
        let availW = max(size.width - pad * 2, 1)
        let availH = max(size.height - pad * 2, 1)
        let scaleX = availW / CGFloat(payload.extent.x)
        let scaleY = availH / CGFloat(payload.extent.y)
        let scale = min(scaleX, scaleY)
        let cx = size.width * 0.5
        let cy = size.height * 0.5

        func project(_ pt: SIMD2<Float>) -> CGPoint {
            let dx = CGFloat(pt.x - payload.center.x) * scale
            let dy = CGFloat(pt.y - payload.center.y) * scale
            // Flip Y so North is up
            return CGPoint(x: cx + dx, y: cy - dy)
        }

        // 1. Track outline (subtle outer border + inner asphalt ribbon)
        if payload.outline.count > 1 {
            var trackPath = Path()
            trackPath.move(to: project(payload.outline[0]))
            for pt in payload.outline.dropFirst() {
                trackPath.addLine(to: project(pt))
            }

            context.stroke(
                trackPath,
                with: .color(.white.opacity(0.10)),
                style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                trackPath,
                with: .color(.white.opacity(0.24)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }

        // 2. Cars: soft outer halo + saturated team disc + white core + driver code
        for driver in payload.drivers {
            guard let worldPt = driver.position(at: time) else { continue }
            let p = project(worldPt)

            let haloR: CGFloat = 11
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - haloR, y: p.y - haloR, width: haloR * 2, height: haloR * 2)),
                with: .color(driver.color.opacity(0.32))
            )

            let discR: CGFloat = 6
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - discR, y: p.y - discR, width: discR * 2, height: discR * 2)),
                with: .color(driver.color)
            )

            let coreR: CGFloat = 2.2
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - coreR, y: p.y - coreR, width: coreR * 2, height: coreR * 2)),
                with: .color(.white)
            )

            context.draw(
                Text(driver.code)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88)),
                at: CGPoint(x: p.x + 9, y: p.y),
                anchor: .leading
            )
        }
    }

    private var legendStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.legend) { row in
                    HStack(spacing: 5) {
                        Circle().fill(row.color).frame(width: 9, height: 9)
                        Text(row.code).font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}
