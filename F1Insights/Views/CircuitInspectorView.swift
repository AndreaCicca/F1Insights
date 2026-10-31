import SwiftUI

/// Modern modal Sheet for Circuit & Grand Prix details.
/// Features generous dimensions on macOS and detents on iOS/iPadOS.
struct CircuitInspectorView: View {
    let race: Race
    let results: [RaceResult]

    @Environment(\.dismiss) private var dismiss
    @State private var copiedMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    InspectorCard {
                        InspectorCircuitProfileSection(circuit: race.circuit)
                    }

                    InspectorCard {
                        InspectorRaceOverviewSection(
                            round: race.round,
                            season: race.season,
                            startDate: race.startDate,
                            laps: results.first?.laps
                        )
                    }

                    if !results.isEmpty {
                        InspectorCard {
                            InspectorResultsSummarySection(
                                winner: results.first,
                                fastestLap: results.first(where: { $0.fastestLap?.rank == "1" })
                            )
                        }
                    }

                    InspectorCard {
                        InspectorExportSection(
                            race: race,
                            results: results,
                            onCopy: { message in
                                withAnimation { copiedMessage = message }
                            }
                        )
                    }

                    if let message = copiedMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(message)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(16)
            }
            .navigationTitle(race.circuit.circuitName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 520, idealHeight: 580)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .animation(.easeInOut(duration: 0.25), value: copiedMessage)
        .task(id: copiedMessage) {
            guard copiedMessage != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation {
                copiedMessage = nil
            }
        }
    }
}

// MARK: - Card Container

private struct InspectorCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
    }
}

private struct InspectorSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(.secondary)
    }
}

private struct InspectorRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.medium))
        }
    }
}

// MARK: - Circuit Profile Section

private struct InspectorCircuitProfileSection: View {
    let circuit: Circuit

    private var coordinatesText: String? {
        guard let latStr = circuit.location.lat,
              let lonStr = circuit.location.long,
              let lat = Double(latStr),
              let lon = Double(lonStr) else {
            return nil
        }
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(format: "%.4f° %@, %.4f° %@", abs(lat), latDir, abs(lon), lonDir)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InspectorSectionHeader(title: "CIRCUIT", systemImage: "flag.checkered")

            VStack(alignment: .leading, spacing: 4) {
                Text(circuit.circuitName)
                    .font(.headline.weight(.bold))

                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                    Text("\(circuit.location.locality ?? ""), \(circuit.location.country ?? "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let coords = coordinatesText {
                    Text(coords)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }

            VStack(spacing: 8) {
                Button {
                    PlatformServices.openInAppleMaps(circuit: circuit)
                } label: {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("Open in Apple Maps")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    PlatformServices.openWikipedia(query: "\(circuit.circuitName) circuit Formula One")
                } label: {
                    HStack {
                        Image(systemName: "book.pages")
                        Text("Circuit on Wikipedia")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Race Overview Section

private struct InspectorRaceOverviewSection: View {
    let round: String
    let season: String
    let startDate: Date?
    let laps: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InspectorSectionHeader(title: "EVENT DETAILS", systemImage: "info.circle")

            VStack(alignment: .leading, spacing: 10) {
                InspectorRow(title: "Round", value: "Round \(round) (\(season))")

                if let date = startDate {
                    InspectorRow(title: "Race Date", value: date.formatted(date: .abbreviated, time: .omitted))
                    InspectorRow(title: "Local Time", value: date.formatted(date: .omitted, time: .shortened))
                }

                if let laps {
                    InspectorRow(title: "Scheduled Laps", value: "\(laps) laps")
                }
            }
        }
    }
}

// MARK: - Results Summary Section

private struct InspectorResultsSummarySection: View {
    let winner: RaceResult?
    let fastestLap: RaceResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InspectorSectionHeader(title: "RACE HIGHLIGHTS", systemImage: "trophy")

            VStack(alignment: .leading, spacing: 10) {
                if let w = winner {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Winner")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(TeamColor.color(for: w.constructor.constructorId))
                                .frame(width: 4, height: 18)
                            Text(w.driver.fullName)
                                .font(.subheadline.weight(.semibold))
                            Text(w.constructor.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let fl = fastestLap,
                   let time = fl.fastestLap?.time?.time {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fastest Lap")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Image(systemName: "stopwatch.fill")
                                .font(.caption)
                                .foregroundStyle(.purple)
                            Text(fl.driver.fullName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(time)
                                .font(.subheadline.monospacedDigit().weight(.medium))
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Export Section

private struct InspectorExportSection: View {
    let race: Race
    let results: [RaceResult]
    let onCopy: (String) -> Void

    private var shareSummaryText: String {
        var parts: [String] = []
        parts.append("🏎️ \(race.raceName) (Round \(race.round), \(race.season))")
        parts.append("📍 \(race.circuit.circuitName) - \(race.circuit.location.country ?? "")")
        if let d = race.startDate {
            parts.append("📅 \(d.formatted(date: .abbreviated, time: .shortened))")
        }
        if let w = results.first {
            parts.append("🏆 Winner: \(w.driver.fullName) (\(w.constructor.name))")
        }
        if let fl = results.first(where: { $0.fastestLap?.rank == "1" }), let t = fl.fastestLap?.time?.time {
            parts.append("⚡ Fastest Lap: \(fl.driver.fullName) (\(t))")
        }
        return parts.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InspectorSectionHeader(title: "SHARE & EXPORT", systemImage: "square.and.arrow.up")

            VStack(spacing: 8) {
                ShareLink(
                    item: shareSummaryText,
                    subject: Text(race.raceName),
                    message: Text("Formula 1 \(race.season) - \(race.raceName)")
                ) {
                    Label("Share Grand Prix…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    PlatformServices.copyToPasteboard(shareSummaryText)
                    onCopy("Summary copied to pasteboard")
                } label: {
                    Label("Copy Summary", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                if !results.isEmpty {
                    Button {
                        let md = PlatformServices.generateMarkdownTable(race: race, results: results)
                        PlatformServices.copyToPasteboard(md)
                        onCopy("Markdown table copied!")
                    } label: {
                        Label("Copy Markdown Table", systemImage: "tablecells")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button {
                        let csv = PlatformServices.generateCSV(race: race, results: results)
                        PlatformServices.copyToPasteboard(csv)
                        onCopy("CSV copied!")
                    } label: {
                        Label("Copy as CSV (Excel / Numbers)", systemImage: "doc.plaintext")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
    }
}
