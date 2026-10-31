<div align="center">

# F1 Insights

**A modern, multiplatform SwiftUI app for Formula 1 statistics, race analytics, and telemetry replay.**

[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple&style=flat-square)](https://apple.com)
[![iOS 17+](https://img.shields.io/badge/iOS-17.0%2B-blue?logo=apple&style=flat-square)](https://apple.com)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white&style=flat-square)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20Swift%20Charts-007AFF?style=flat-square)](https://developer.apple.com/xcode/swiftui/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

</div>

---

## Overview

**F1 Insights** brings the world of Formula 1 to macOS, iPadOS, and iOS. Built entirely with native SwiftUI and Swift Concurrency, it delivers deep statistical insights and visualization across every Formula 1 World Championship season from 1950 to the present day.

## Key Features

- **Championship Calendar & Standings:** Full historical archive from 1950 to the current season. Search races, circuits, and filter by completion status.
- **Race Detail & Analytics:**
  - **Results & Qualifying:** Native adaptive tables with podium indicators, DNF status, points, and gap tracking.
  - **Lap Times & Position Progression:** Interactive multi-driver telemetry charts powered by Swift Charts.
  - **Pit Stop Strategy:** Visual breakdown of compound stint lengths, pit stop laps, and durations (2011+).
- **60 FPS Animated Race Replay:**
  - Shader-embellished track playback rendered with custom Metal shaders and composited off-screen.
  - Real-time running order leaderboard and interactive transport bar.
- **Circuit Details & Inspector Sheet:**
  - Modal sheet presenting GPS coordinates, satellite tracking via Apple Maps, event schedule, and circuit history.
  - One-click export to Markdown tables and CSV (Excel / Numbers).
- **Adaptive Multiplatform Architecture:**
  - 3-column `NavigationSplitView` on macOS and iPadOS.
  - Responsive `TabView` with persistent navigation state on compact iOS displays.
  - Native macOS Dock tile badges with countdowns to upcoming Grand Prix rounds.

## Tech Stack

| Layer | Technologies |
|---|---|
| **UI Framework** | SwiftUI (iOS 17+ / macOS 14+), Swift Charts, SF Symbols |
| **Graphics & Shaders** | Metal Shading Language (`colorEffect`, speed grid animation) |
| **State & Concurrency** | `@Observable` (Observation framework), `async`/`await`, structured tasks |
| **Networking & Cache** | Jolpica-F1 / Ergast REST API + OpenF1, local disk caching with rate-limit retries |

## Getting Started

### Requirements
- **macOS 14.0+** or **iOS / iPadOS 17.0+**
- **Xcode 15.0+** (Swift 5.9+)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/andread/f1.git
   cd f1
   ```
2. Open the Xcode project:
   ```bash
   open F1Insights.xcodeproj
   ```
3. Select the **F1Insights** scheme and build (`⌘B`) or run (`⌘R`).

## Project Structure

```
F1Insights/
├── F1InsightsApp.swift       # App lifecycle & menu commands
├── ContentView.swift         # Adaptive SplitView / TabView root
├── Shaders.metal             # Metal shader effects for race replay
├── Models/
│   ├── ErgastModels.swift    # Codable models for Ergast/Jolpica payloads
│   └── OpenF1Models.swift    # Models for live session telemetry
├── Services/
│   ├── AppState.swift        # Shared app state, season selection & caching
│   ├── F1APIClient.swift     # Resilient async network client with retry logic
│   ├── LocalDataCache.swift  # Disk persistence for offline access
│   └── MacServices.swift     # Apple Maps, system pasteboard & dock integration
└── Views/
    ├── ColumnsView.swift     # Calendar, Driver, and Constructor ranking columns
    ├── RaceDetailView.swift  # Multi-tab Grand Prix hub
    ├── CircuitInspectorView  # Modal sheet for circuit info and export
    ├── RaceReplayView.swift  # Real-time position replay canvas
    ├── ChartsViews.swift     # Swift Charts telemetry & pit strategy
    └── TrackMap/             # GPS track outline & speed telemetry
```

## Disclaimer & Data Attribution

- Data provided via the public [Jolpica F1 API](https://api.jolpi.ca/ergast/f1) (Ergast successor) and [OpenF1](https://openf1.org).
- This project is an unofficial open-source application and is **not** associated, affiliated, endorsed, or sponsored in any way with Formula 1, the FIA, Formula One Licensing B.V., or any of their subsidiaries.
