import SwiftUI

/// The single, custom season selector for the whole app. Lives pinned at the
/// top of the sidebar so the current season is shown clearly and compactly.
/// Native-feeling macOS control: a "SEASON" eyebrow, a large rounded year that
/// rolls its digits (.numericText), a menu picker for jumping to any season,
/// and horizontal stepper chevrons.
struct SeasonHeader: View {
    @Binding var season: Int
    /// Seasons in descending order (newest first).
    let seasons: [Int]

    private var newest: Int { seasons.first ?? season }
    private var oldest: Int { seasons.last ?? season }

    private static let anim: Animation = .snappy(duration: 0.35, extraBounce: 0.1)

    private func set(_ year: Int) {
        let clamped = min(newest, max(oldest, year))
        guard clamped != season else { return }
        withAnimation(Self.anim) { season = clamped }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SEASON")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.tertiary)

                Menu {
                    Picker("Season", selection: menuBinding) {
                        ForEach(seasons, id: \.self) { Text(verbatim: String($0)).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 5) {
                        Text(verbatim: String(season))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(season)))
                            .foregroundStyle(.primary)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                #if os(macOS)
                .menuStyle(.button)
                .buttonStyle(.borderless)
                #endif
                .menuIndicator(.hidden)
                .fixedSize()
            }

            Spacer(minLength: 4)

            HStack(spacing: 3) {
                stepper(
                    to: season - 1,
                    symbol: "chevron.left",
                    disabled: season <= oldest,
                    help: "Previous season (⌘[)"
                )
                stepper(
                    to: season + 1,
                    symbol: "chevron.right",
                    disabled: season >= newest,
                    help: "Next season (⌘])"
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .cardStyle(cornerRadius: 8, fillOpacity: 0.4, borderColor: Color.primary.opacity(0.06))
    }

    private func stepper(to year: Int, symbol: String, disabled: Bool, help: String) -> some View {
        Button { set(year) } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(disabled ? Color.clear : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
        .disabled(disabled)
        .help(help)
    }

    private var menuBinding: Binding<Int> {
        Binding(get: { season }, set: { set($0) })
    }
}

/// Compact season picker for iOS navigation toolbars.
struct SeasonCompactPicker: View {
    @Binding var season: Int
    let seasons: [Int]

    var body: some View {
        Menu {
            Picker("Season", selection: $season) {
                ForEach(seasons, id: \.self) { year in
                    Text(verbatim: String(year)).tag(year)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: String(season))
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
    }
}

