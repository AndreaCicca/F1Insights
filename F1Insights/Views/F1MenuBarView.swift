#if os(macOS)
import SwiftUI
import AppKit

/// macOS Menu Bar Extra popover view, providing quick real-time glance at the next Grand Prix
/// and current championship standings directly from the macOS status bar.
struct F1MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerView

            Divider()

            if let race = state.nextRace {
                nextRaceSection(race)
            } else if state.isLoadingSchedule {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading schedule…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Divider()

            MenuBarStandingsSection(
                title: "DRIVERS CHAMPIONSHIP",
                rows: state.driverStandings.prefix(3).map { s in
                    .init(
                        id: s.id,
                        position: s.position,
                        teamId: s.constructors.first?.constructorId ?? "",
                        name: s.driver.fullName,
                        points: s.points
                    )
                }
            )

            Divider()

            MenuBarStandingsSection(
                title: "CONSTRUCTORS CHAMPIONSHIP",
                rows: state.constructorStandings.prefix(3).map { s in
                    .init(
                        id: s.id,
                        position: s.position,
                        teamId: s.constructor.constructorId,
                        name: s.constructor.name,
                        points: s.points
                    )
                }
            )

            Divider()

            footerView
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Image(systemName: "flag.checkered.2.crossed")
                .foregroundStyle(Color.accentColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 1) {
                Text("F1 Insights")
                    .font(.headline.weight(.bold))
                Text("\(String(state.season)) Season")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await state.loadInitial() }
            } label: {
                if state.isAnyLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh Data")
            .disabled(state.isAnyLoading)
        }
    }

    private func nextRaceSection(_ race: Race) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NEXT GRAND PRIX")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("ROUND \(race.round)")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(race.raceName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(race.circuit.circuitName), \(race.circuit.location.country ?? "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let date = race.startDate {
                HStack {
                    Label {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(relativeTime(from: date))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }

            Button {
                MacServices.openInAppleMaps(circuit: race.circuit)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "map.fill")
                    Text("Explore in Apple Maps")
                }
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var footerView: some View {
        HStack {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open App Window", systemImage: "macwindow")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func relativeTime(from date: Date) -> String {
        let diff = Calendar.current.dateComponents([.day, .hour], from: Date(), to: date)
        if let d = diff.day, d > 1 {
            return "In \(d) days"
        } else if let d = diff.day, d == 1 {
            return "Tomorrow"
        } else if let h = diff.hour, h > 0 {
            return "In \(h)h"
        } else {
            return "Race Day"
        }
    }
}

private struct MenuBarStandingsSection: View {
    struct Row: Identifiable {
        let id: String
        let position: String?
        let teamId: String
        let name: String
        let points: String
    }

    let title: String
    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(.secondary)

            if rows.isEmpty {
                Text("No standings available")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Podium.Badge(
                            position: row.position,
                            font: .system(size: 10, design: .rounded)
                        )
                        .frame(width: 14)

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(TeamColor.color(for: row.teamId))
                            .frame(width: 3, height: 16)

                        Text(row.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)

                        Spacer()

                        Text("\(row.points) pts")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
#endif
