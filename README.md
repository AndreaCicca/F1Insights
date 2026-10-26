# F1 Insights

Native macOS app (SwiftUI) to browse Formula 1 races and statistics.

## Data source

Uses the **Jolpica-F1 REST API** (`https://api.jolpi.ca/ergast/f1`), the
maintained successor to Ergast and the same public F1 data FastF1 reads under
the hood.

> **Telemetry note.** True car telemetry (speed / throttle / brake / gear
> traces) is **not** part of this REST surface — that data comes from F1's
> live-timing feed that FastF1 scrapes in Python and cannot be reached from a
> pure-Swift app. This project delivers the deepest analysis the REST API
> allows: **lap-time charts, position-progression charts, pit-stop strategy**.
> To add real telemetry later, bundle a FastF1 Python sidecar (FastAPI) and
> point a new API client at it.

## Features

- Season picker (1950 → current) — native toolbar menu + `Season` menu-bar command
- Race calendar with search (`⌘F`)
- Per-race detail tabs:
  - **Results** — finishing order, grid, time/status, points (native `Table`)
  - **Qualifying** — Q1/Q2/Q3 times
  - **Lap Times** — Swift Charts line chart, multi-driver select
  - **Positions** — lap-by-lap position progression
  - **Strategy** — pit-stop laps + durations
- Driver standings — bar chart + sortable table
- Constructor standings — bar chart + sortable table
- Team-colored throughout, SF Symbols, `NavigationSplitView` sidebar

## Native macOS tech

SwiftUI · Swift Charts · `Table` · `NavigationSplitView` · `.searchable`
· `async/await` + `actor` networking · App Sandbox (`network.client` only)

## Build & run

```
open F1Insights.xcodeproj
```

Select the **F1Insights** scheme, press ⌘R. Requires **macOS 14+**, **Xcode 16+**.

Command line:

```
xcodebuild -project F1Insights.xcodeproj -scheme F1Insights -configuration Debug build
```

## Structure

```
F1Insights/
  F1InsightsApp.swift      app entry, menu commands
  ContentView.swift        split view + season toolbar
  Models/ErgastModels.swift  Codable models for the Ergast/Jolpica JSON
  Services/
    F1APIClient.swift      async actor client (paginated lap fetch)
    AppState.swift         season state + caches
  Views/
    ScheduleView.swift     calendar list + search
    RaceDetailView.swift   results / qualifying tabs
    ChartsViews.swift      lap / position / strategy charts
    StandingsView.swift    driver + constructor standings
    Components.swift        loading/empty views, team colors, helpers
```

## License / attribution

F1 data via Jolpica (CC-BY compatible with Ergast terms). Not affiliated with
Formula 1 or the FIA.
