import SwiftUI

/// Inspector panel view for Circuit & Grand Prix details.
/// Adapts seamlessly between a macOS trailing inspector and an iOS modal sheet.
struct CircuitInspectorView: View {
    let race: Race
    let results: [RaceResult]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var copiedMessage: String?

    private var coordinatesText: String? {
        guard let latStr = race.circuit.location.lat,
              let lonStr = race.circuit.location.long,
              let lat = Double(latStr),
              let lon = Double(lonStr) else {
            return nil
        }
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(format: "%.4f° %@, %.4f° %@", abs(lat), latDir, abs(lon), lonDir)
    }

    private var winner: RaceResult? {
        results.first
    }

    private var fastestLap: RaceResult? {
        results.first(where: { $0.fastestLap?.rank == "1" })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                inspectorCard { circuitProfileSection }
                inspectorCard { raceOverviewSection }

                if !results.isEmpty {
                    inspectorCard { resultsSummarySection }
                }

                inspectorCard { exportSection }

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
        #if os(macOS)
        .frame(minWidth: 260, idealWidth: 280)
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

    // MARK: - Card Container

    private func inspectorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(.secondary)
    }

    // MARK: - Sections

    private var circuitProfileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("CIRCUITO", systemImage: "flag.checkered")

            VStack(alignment: .leading, spacing: 4) {
                Text(race.circuit.circuitName)
                    .font(.headline.weight(.bold))

                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                    Text("\(race.circuit.location.locality ?? ""), \(race.circuit.location.country ?? "")")
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
                externalLinkButton("Apri in Apple Maps", systemImage: "map.fill", prominent: true) {
                    PlatformServices.openInAppleMaps(circuit: race.circuit)
                }

                externalLinkButton("Circuito su Wikipedia", systemImage: "book.pages", prominent: false) {
                    PlatformServices.openWikipedia(query: "\(race.circuit.circuitName) circuit Formula One")
                }
            }
            .padding(.top, 4)
        }
    }

    private func externalLinkButton(_ title: String, systemImage: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(prominent ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered))
        .controlSize(.regular)
    }

    private var raceOverviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("DETTAGLI EVENTO", systemImage: "info.circle")

            VStack(alignment: .leading, spacing: 10) {
                inspectorRow(title: "Round", value: "Round \(race.round) (\(race.season))")

                if let date = race.startDate {
                    inspectorRow(title: "Data Gara", value: date.formatted(date: .abbreviated, time: .omitted))
                    inspectorRow(title: "Orario Locale", value: date.formatted(date: .omitted, time: .shortened))
                }

                if let laps = results.first?.laps {
                    inspectorRow(title: "Giri Previsti", value: "\(laps) giri")
                }
            }
        }
    }

    private var resultsSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("HIGHLIGHT GARA", systemImage: "trophy")

            VStack(alignment: .leading, spacing: 10) {
                if let w = winner {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vincitore")
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
                        Text("Giro Più Veloce")
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

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("CONDIVISIONE ED ESPORTAZIONE", systemImage: "square.and.arrow.up")

            VStack(spacing: 8) {
                ShareLink(
                    item: shareSummaryText,
                    subject: Text(race.raceName),
                    message: Text("Formula 1 \(race.season) - \(race.raceName)")
                ) {
                    Label("Condividi Gran Premio…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                copyButton("Copia Riepilogo", systemImage: "doc.on.doc", toast: "Riepilogo copiato negli appunti") {
                    shareSummaryText
                }

                if !results.isEmpty {
                    copyButton("Copia Tabella Markdown", systemImage: "tablecells", toast: "Tabella Markdown copiata!") {
                        PlatformServices.generateMarkdownTable(race: race, results: results)
                    }

                    copyButton("Copia come CSV (Excel / Numbers)", systemImage: "doc.plaintext", toast: "CSV copiato!") {
                        PlatformServices.generateCSV(race: race, results: results)
                    }
                }
            }
        }
    }

    private func copyButton(_ title: String, systemImage: String, toast: String, content: @escaping () -> String) -> some View {
        Button {
            PlatformServices.copyToPasteboard(content())
            withAnimation { copiedMessage = toast }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    // MARK: - Helpers

    private func inspectorRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.medium))
        }
    }

    private var shareSummaryText: String {
        var parts: [String] = []
        parts.append("🏎️ \(race.raceName) (Round \(race.round), \(race.season))")
        parts.append("📍 \(race.circuit.circuitName) - \(race.circuit.location.country ?? "")")
        if let d = race.startDate {
            parts.append("📅 \(d.formatted(date: .abbreviated, time: .shortened))")
        }
        if let w = winner {
            parts.append("🏆 Vincitore: \(w.driver.fullName) (\(w.constructor.name))")
        }
        if let fl = fastestLap, let t = fl.fastestLap?.time?.time {
            parts.append("⚡ Giro più veloce: \(fl.driver.fullName) (\(t))")
        }
        return parts.joined(separator: "\n")
    }
}

private struct AnyButtonStyle: PrimitiveButtonStyle {
    private let _makeBody: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        _makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}
