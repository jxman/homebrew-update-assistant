import Charts
import SwiftUI

/// Vulnerability counts over time, one line per scanner, with a range picker.
struct SecurityTrendChart: View {
    @Environment(AppModel.self) private var model

    /// Counts read from `*.security.log` for runs without a summary (before script v2.2.0)
    @State private var logCounts: [Run.ID: Int] = [:]
    /// How far back the trend chart looks
    @State private var trendRange = TrendRange.week

    var body: some View {
        trendChart
            .task(id: runsNeedingLogCounts.map(\.id)) { await loadLogCounts() }
    }

    /// Runs inside the chosen range (all of them for All)
    private var recentRuns: [Run] {
        guard let start = trendRange.start() else { return model.runs }
        return model.runs.filter { $0.date >= start }
    }

    /// Older runs have no summary, only the scan's text report
    private var runsNeedingLogCounts: [Run] {
        recentRuns.filter { $0.summary == nil && $0.files[.security] != nil }
    }

    /// Vulnerability counts over the chosen range, oldest first, one line per scanner. grype's
    /// come from run summaries, or are counted from the text report for runs from before
    /// summaries existed; brew vulns's from summaries (script 2.4.0+). The two count different
    /// things (grype: fixable Critical/High/Medium; brew vulns: everything), so compare trends,
    /// not heights.
    private var trend: [TrendPoint] {
        let grype: [TrendPoint] = recentRuns.compactMap { run in
            if let security = run.summary?.security {
                return security.status == "completed"
                    ? TrendPoint(date: run.date, count: security.vulnerabilityCount, source: .grype) : nil
            }
            return logCounts[run.id].map { TrendPoint(date: run.date, count: $0, source: .grype) }
        }
        let brewVulns: [TrendPoint] = recentRuns.compactMap { run in
            guard let vulns = run.summary?.vulns, vulns.status == "completed" else { return nil }
            return TrendPoint(date: run.date, count: vulns.findingCount, source: .brewVulns)
        }
        return (grype + brewVulns).sorted { $0.date < $1.date }
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            // A segmented picker: each case of the enum is one segment, and choosing one sets
            // `trendRange`, which re-renders the chart with the new span
            Picker("Range", selection: $trendRange) {
                ForEach(TrendRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 380)
            Chart(trend) { point in
                // `foregroundStyle(by:)` splits the marks into one series (and colour) per scanner
                LineMark(x: .value("Date", point.date), y: .value("Vulnerabilities", point.count))
                    .foregroundStyle(by: .value("Scanner", point.source.title))
                // Dots on every run would run together over a year of runs, so only the line then
                if trend.count <= 120 {
                    PointMark(x: .value("Date", point.date), y: .value("Vulnerabilities", point.count))
                        .foregroundStyle(by: .value("Scanner", point.source.title))
                        .symbolSize(20)
                }
            }
            .chartForegroundStyleScale([
                VulnerabilitySource.grype.title: Color.blue, VulnerabilitySource.brewVulns.title: Color.orange
            ])
            .chartLegend(position: .top, alignment: .trailing)
            .chartYAxisLabel("Findings")
            // A fixed span, so the chart always covers the whole range however many runs there were
            .chartXScale(domain: trendRange.domain(oldest: trend.first?.date))
            .chartXAxis { trendAxis }
            // Start at zero so a drop (e.g. after upgrading) looks as big as it is
            .chartYScale(domain: 0...max(1, trend.map(\.count).max() ?? 0))
            .overlay {
                if trend.isEmpty {
                    Text("No scans in this range").font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(width: 380, height: 130)
        }
    }

    /// One labelled tick per hour block, day, week or month, depending on the range.
    /// `@AxisContentBuilder` lets the `switch` return different axis marks per case.
    @AxisContentBuilder
    private var trendAxis: some AxisContent {
        switch trendRange {
        case .day:
            AxisMarks(values: .stride(by: .hour, count: 6)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        case .week:
            AxisMarks(values: .stride(by: .day)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        case .month:
            AxisMarks(values: .stride(by: .day, count: 7)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        case .year:
            AxisMarks(values: .stride(by: .month, count: 2)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        case .all:
            // Any length of history: let Charts pick the ticks
            AxisMarks()
        }
    }

    private func loadLogCounts() async {
        let store = RunStore(paths: model.paths)
        for run in runsNeedingLogCounts where logCounts[run.id] == nil {
            guard let url = run.files[.security] else { continue }
            logCounts[run.id] = try? await store.vulnerabilityCount(at: url)
        }
    }
}

/// One scan's count on the trend chart
private struct TrendPoint: Identifiable {
    let date: Date
    let count: Int
    let source: VulnerabilitySource

    var id: String { "\(source.rawValue)|\(date.timeIntervalSince1970)" }
}
