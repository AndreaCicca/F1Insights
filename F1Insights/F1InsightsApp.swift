import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct F1InsightsApp: App {
    @State private var state = AppState()

    init() {
        #if os(macOS)
        if let iconImage = NSImage(named: "AppIcon") ?? Bundle.main.path(forResource: "AppIcon", ofType: "icns").flatMap({ NSImage(contentsOfFile: $0) }) {
            NSApplication.shared.applicationIconImage = iconImage
        }
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(state)
                #if os(macOS)
                .frame(minWidth: 1020, minHeight: 660)
                #endif
                .task { await state.loadInitial() }
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        #endif
        .commands {
            appCommands
        }

        #if os(macOS)
        MenuBarExtra("F1 Insights", systemImage: "flag.checkered.2.crossed") {
            F1MenuBarView()
                .environment(state)
        }
        .menuBarExtraStyle(.window)
        #endif
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandMenu("Navigation") {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element.id) { idx, item in
                Button(item.rawValue) {
                    state.selection = item
                }
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: .command)
            }

            Divider()

            Button("Refresh Data") {
                Task { await state.loadInitial(forceRefresh: true) }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu("Grand Prix") {
            Button("Explore Next Grand Prix in Apple Maps") {
                if let next = state.nextRace {
                    PlatformServices.openInAppleMaps(circuit: next.circuit)
                }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("Next Grand Prix on Wikipedia") {
                if let next = state.nextRace {
                    PlatformServices.openWikipedia(query: "\(next.raceName) \(next.season)")
                }
            }
        }

        CommandMenu("Season") {
            Button("Next Season") {
                state.stepSeason(by: 1)
            }
            .keyboardShortcut("]", modifiers: .command)

            Button("Previous Season") {
                state.stepSeason(by: -1)
            }
            .keyboardShortcut("[", modifiers: .command)

            Divider()

            Picker("Season", selection: $state.season) {
                ForEach(state.availableSeasons, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
        }

        CommandGroup(replacing: .newItem) {}
    }
}

