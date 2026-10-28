import Foundation

/// How far back the Security trend chart looks
enum TrendRange: String, CaseIterable, Identifiable, Sendable {
    case day = "24 Hours"
    case week = "7 Days"
    case month = "30 Days"
    case year = "1 Year"
    case all = "All"

    var id: Self { self }

    /// Start of the chart, or nil for `.all` (the chart then starts at the oldest scan).
    /// Ranges of whole days start at midnight, so today is the last of the days shown.
    func start(asOf now: Date = .now, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .day: return calendar.date(byAdding: .hour, value: -24, to: now)
        case .week: return calendar.date(byAdding: .day, value: -6, to: today)
        case .month: return calendar.date(byAdding: .day, value: -29, to: today)
        case .year: return calendar.date(byAdding: .year, value: -1, to: today)
        case .all: return nil
        }
    }

    /// The chart's x-axis span. `.all` runs from the oldest point; with no points, or a single
    /// point from right now, it falls back to the last day so the span is never empty.
    func domain(oldest: Date?, asOf now: Date = .now, calendar: Calendar = .current) -> ClosedRange<Date> {
        let fallback = calendar.date(byAdding: .hour, value: -24, to: now) ?? now
        guard let start = start(asOf: now, calendar: calendar) ?? oldest, start < now else {
            return fallback...now
        }
        return start...now
    }
}
