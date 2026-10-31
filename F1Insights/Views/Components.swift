import SwiftUI

/// Centered progress indicator with a caption.
struct LoadingView: View {
    let label: String
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(label).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Empty / error placeholder.
struct MessageView: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let subtitle { Text(subtitle) }
        }
    }
}

/// Small rounded pill for positions / points.
struct Pill: View {
    let text: String
    var tint: Color = .accentColor
    var body: some View {
        RollText(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - Shared Podium Helpers

enum Podium {
    static func color(for position: Int?) -> Color? {
        switch position {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return nil
        }
    }

    static func color(for position: String?, fallback: Color = .secondary) -> Color {
        guard let pos = position, let p = Int(pos), let c = color(for: p) else {
            return fallback
        }
        return c
    }

    /// Position text styled with podium colors (used in rank lists and menu bar).
    struct Badge: View {
        let position: String?
        var font: Font = .callout.monospacedDigit()

        private var posInt: Int? { position.flatMap(Int.init) }

        var body: some View {
            if let p = posInt {
                Text("\(p)")
                    .font(font.weight(p == 1 ? .heavy : (p <= 3 ? .bold : .semibold)))
                    .foregroundStyle(Podium.color(for: p) ?? .secondary)
            } else {
                Text(position ?? "—")
                    .font(font.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Rounded podium pill for race result tables and lists.
    struct Pill: View {
        let text: String
        let position: Int

        var body: some View {
            ZStack {
                if let color = Podium.color(for: position) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(color.opacity(0.25))
                    Text("\(position)")
                        .font(.callout.monospacedDigit().weight(position == 1 ? .heavy : .bold))
                        .foregroundStyle(color)
                } else {
                    Text(text)
                        .font(.callout.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 20)
        }
    }
}

/// Team-colored circle indicator next to a title (driver/team) with optional subtitle or code.
struct TeamDotLabel: View {
    let title: String
    let teamId: String
    var subtitle: String? = nil
    var dotSize: CGFloat = 9

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(TeamColor.color(for: teamId))
                .frame(width: dotSize, height: dotSize)
            Text(title)
                .font(.body.weight(.medium))
            if let subtitle {
                Text(subtitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Deterministic colour per team, used across charts and lists.
enum TeamColor {
    static let palette: [String: Color] = [
        "red_bull": Color(red: 0.11, green: 0.24, blue: 0.55),
        "ferrari": Color(red: 0.86, green: 0.00, blue: 0.00),
        "mercedes": Color(red: 0.00, green: 0.82, blue: 0.77),
        "mclaren": Color(red: 1.00, green: 0.53, blue: 0.00),
        "aston_martin": Color(red: 0.00, green: 0.44, blue: 0.39),
        "alpine": Color(red: 0.01, green: 0.56, blue: 0.90),
        "williams": Color(red: 0.00, green: 0.63, blue: 0.94),
        "rb": Color(red: 0.42, green: 0.55, blue: 0.86),
        "sauber": Color(red: 0.32, green: 0.78, blue: 0.20),
        "haas": Color(red: 0.70, green: 0.70, blue: 0.70)
    ]

    static func color(for constructorId: String) -> Color {
        if let c = palette[constructorId] { return c }
        let hash = abs(constructorId.hashValue)
        return Color(hue: Double(hash % 256) / 256.0, saturation: 0.65, brightness: 0.85)
    }
}

// MARK: - Driver selection chip bar

struct DriverMeta: Identifiable, Equatable {
    let id: String
    let name: String
    let constructorId: String
    let finishPosition: Int
}

func driverMetas(from results: [RaceResult]) -> [DriverMeta] {
    results.map {
        DriverMeta(id: $0.driver.driverId,
                   name: $0.driver.displayName,
                   constructorId: $0.constructor.constructorId,
                   finishPosition: Int($0.position) ?? 99)
    }
}

/// Driver multi-select chip bar shared by the chart and replay views.
struct DriverPicker: View {
    let metas: [DriverMeta]
    @Binding var selected: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                quickButton("Top 3") {
                    selected = Set(metas.sorted { $0.finishPosition < $1.finishPosition }.prefix(3).map(\.id))
                }
                quickButton("Top 5") {
                    selected = Set(metas.sorted { $0.finishPosition < $1.finishPosition }.prefix(5).map(\.id))
                }
                quickButton("All") {
                    selected = Set(metas.map(\.id))
                }
                quickButton("Clear") {
                    selected.removeAll()
                }

                Divider()
                    .frame(height: 12)
                    .padding(.horizontal, 2)

                Text("\(selected.count) of \(metas.count) selected")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(metas) { m in
                        let on = selected.contains(m.id)
                        Button {
                            if on { selected.remove(m.id) } else { selected.insert(m.id) }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(on ? Color.white : TeamColor.color(for: m.constructorId))
                                    .frame(width: 6, height: 6)
                                Text(m.name)
                                    .font(.subheadline.weight(on ? .semibold : .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                on ? AnyShapeStyle(TeamColor.color(for: m.constructorId))
                                   : AnyShapeStyle(Color.primary.opacity(0.06)),
                                in: Capsule()
                            )
                            .foregroundStyle(on ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Playback Transport Bar

/// Adaptive playback transport bar shared between RaceReplayView and TrackMapView.
struct PlaybackTransportBar: View {
    let isPlaying: Bool
    let progressText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Binding var speed: Double
    let speedOptions: [Double]
    let onRestart: () -> Void
    let onTogglePlay: () -> Void
    var onStepBackward: (() -> Void)? = nil
    var onStepForward: (() -> Void)? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularLayout
            compactLayout
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 10) {
            transportButtons(compact: false)

            RollText(progressText)
                .font(.system(.body, design: .monospaced).weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Slider(value: $value, in: range)

            Picker("", selection: $speed) {
                ForEach(speedOptions, id: \.self) { opt in
                    Text("\(Int(opt))×").tag(opt)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .cardStyle(cornerRadius: 10, fillOpacity: 0.4)
    }

    private var compactLayout: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                RollText(progressText)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Slider(value: $value, in: range)
            }

            HStack(spacing: 12) {
                transportButtons(compact: true)

                Spacer()

                Menu {
                    ForEach(speedOptions, id: \.self) { opt in
                        Button("\(Int(opt))×") { speed = opt }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(Int(speed))×")
                            .font(.system(size: 12, weight: .bold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .cardStyle(cornerRadius: 12, fillOpacity: 0.4)
    }

    @ViewBuilder
    private func transportButtons(compact: Bool) -> some View {
        let iconSize: CGFloat = compact ? 13 : 11
        let btnW: CGFloat = compact ? 32 : 26
        let btnH: CGFloat = compact ? 28 : 24

        Button(action: onRestart) {
            Image(systemName: "backward.end.fill")
                .font(.system(size: iconSize, weight: .bold))
                .frame(width: btnW, height: btnH)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Restart from beginning")

        if let onStepBackward {
            Button(action: onStepBackward) {
                Image(systemName: "backward.frame.fill")
                    .font(.system(size: iconSize, weight: .bold))
                    .frame(width: btnW, height: btnH)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Step backward")
        }

        Button(action: onTogglePlay) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: compact ? 15 : 13, weight: .bold))
                .frame(width: compact ? 44 : 30, height: compact ? 32 : 26)
                .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: compact ? 8 : 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help("Play / Pause (Space)")

        if let onStepForward {
            Button(action: onStepForward) {
                Image(systemName: "forward.frame.fill")
                    .font(.system(size: iconSize, weight: .bold))
                    .frame(width: btnW, height: btnH)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Step forward")
        }
    }
}

// MARK: - String & View Extensions

extension String {
    /// Parses a lap/qualifying time like "1:23.456" or "83.456" into seconds.
    var lapTimeSeconds: Double? {
        let parts = split(separator: ":")
        if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
            return m * 60 + s
        }
        return Double(self)
    }
}

extension View {
    /// Standard translucent card container with continuous rounded corners and subtle border.
    func cardStyle(
        cornerRadius: CGFloat = 12,
        fillOpacity: Double = 0.35,
        borderColor: Color? = nil
    ) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.quaternary.opacity(fillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        borderColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.separator.opacity(0.4)),
                        lineWidth: borderColor != nil ? 1 : 0.5
                    )
            }
    }

    /// Unified inset table style with alternating row backgrounds on macOS.
    @ViewBuilder
    func f1TableStyle() -> some View {
        #if os(macOS)
        self.tableStyle(.inset).alternatingRowBackgrounds()
        #else
        self.tableStyle(.inset)
        #endif
    }

    @ViewBuilder
    func platformSubtitle(_ text: String) -> some View {
        #if os(macOS)
        self.navigationSubtitle(text)
        #else
        if #available(iOS 26.0, *) {
            self.navigationSubtitle(text)
        } else {
            self
        }
        #endif
    }
}

