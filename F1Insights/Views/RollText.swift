import SwiftUI

/// Text that *can* roll its digits (Apple's native `.contentTransition`), but
/// only when the value change happens inside an explicit `withAnimation`.
///
/// Why this matters for performance: the roll is deliberately NOT self-driven.
/// There is no timer and no `.animation(value:)` modifier, so sprinkling this
/// across every cell of a large table costs nothing — bulk data (standings,
/// results) loads asynchronously, outside any animation transaction, so those
/// cells simply snap to their new value with zero animation work.
///
/// The roll therefore fires only for isolated, intentionally-animated blocks
/// such as the season number in `SeasonHeader`, which wraps its mutation in
/// `withAnimation`. Use it exactly like `Text`.
struct RollText: View {
    let text: String
    var duration: Double = 0.5

    init(_ text: String, duration: Double = 0.5) {
        self.text = text
        self.duration = duration
    }

    var body: some View {
        Text(text)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}
