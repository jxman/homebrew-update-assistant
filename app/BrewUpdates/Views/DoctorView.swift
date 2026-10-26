import Charts
import SwiftUI

/// `brew doctor` findings explained, with suggested fixes and how each issue has changed
/// across runs. Issues on the left, the selected issue's details on the right.
struct DoctorView: View {
    @Environment(AppModel.self) private var model

    /// nil follows the newest report, so a new run or check shows up automatically
    @State private var selectedSnapshotID: DoctorSnapshot.ID?
    @State private var selectedIssueID: DoctorIssue.ID?

    private var doctor: DoctorModel { model.doctor }

    private var snapshot: DoctorSnapshot? {
        doctor.snapshots.first { $0.id == selectedSnapshotID } ?? doctor.latest
    }

    private var isShowingLatest: Bool { snapshot?.id == doctor.latest?.id }

    /// Most urgent first
    private var issues: [DoctorIssue] {
        (snapshot?.report.issues ?? []).sorted { ($0.importance, $0.headline) < ($1.importance, $1.headline) }
    }

    /// Only offered next to the newest report; "fixed" means fixed as of now
    private var resolved: [DoctorIssueHistory] {
        isShowingLatest ? doctor.resolved : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding()
            Divider()
            content
        }
        .navigationTitle("Doctor")
        .toolbar {
            ToolbarItem {
                Picker("Report", selection: snapshotBinding) {
                    ForEach(doctor.snapshots) { snapshot in
                        Text(title(for: snapshot)).tag(Optional(snapshot.id))
                    }
                }
                .frame(minWidth: 200)
                .disabled(doctor.snapshots.isEmpty)
            }
            ToolbarItem {
                Button {
                    Task {
                        await doctor.checkNow(runs: model.runs)
                        selectedSnapshotID = nil
                    }
                } label: {
                    Label("Check Now", systemImage: "stethoscope")
                }
                .disabled(doctor.isChecking)
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .help("Run brew doctor now, e.g. to confirm a fix worked (⇧⌘D)")
            }
        }
        // Keep the selected issue if it is still listed, otherwise pick the most urgent one
        .onChange(of: snapshot, initial: true) {
            let ids = issues.map(\.id) + resolved.map(\.latest.id)
            if selectedIssueID == nil || !ids.contains(selectedIssueID ?? "") {
                selectedIssueID = ids.first
            }
        }
    }

    /// Choosing the newest report goes back to following new reports
    private var snapshotBinding: Binding<DoctorSnapshot.ID?> {
        Binding(
            get: { snapshot?.id },
            set: { selectedSnapshotID = $0 == doctor.latest?.id ? nil : $0 }
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                if let snapshot {
                    statusLine(issues)
                    Text(sourceDescription(snapshot))
                        .foregroundStyle(.secondary)
                    environmentPills(snapshot)
                } else {
                    Text("No doctor reports yet").font(.title2.weight(.semibold))
                }
                if doctor.isChecking {
                    ProgressView("Running brew doctor…").controlSize(.small)
                }
                if let error = doctor.checkError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            if trend.count > 1 {
                trendChart
            }
        }
    }

    private func statusLine(_ issues: [DoctorIssue]) -> some View {
        let worst = issues.map(\.importance).min()
        let text = switch issues.count {
        case 0: "No issues found"
        case 1: "1 issue"
        default: "\(issues.count) issues"
        }
        return Label(text, systemImage: worst?.systemImage ?? "checkmark.seal.fill")
            .font(.title2.weight(.semibold))
            .foregroundStyle(worst?.color ?? .green)
    }

    private func environmentPills(_ snapshot: DoctorSnapshot) -> some View {
        HStack(spacing: 6) {
            if let version = snapshot.report.homebrewVersion {
                Pill(text: "Homebrew \(version)")
            }
            if let macOS = snapshot.report.macOSVersion {
                Pill(text: "macOS \(macOS)")
            }
            if let tier = snapshot.report.supportTier {
                Pill(text: "\(tier) configuration", color: .orange)
                    .help("Homebrew supports this setup with limits; see docs.brew.sh/Support-Tiers")
            }
            if let url = snapshot.logURL {
                Button("Open Full Report") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.link)
                    .padding(.leading, 6)
            }
        }
    }

    /// Issue counts over time, oldest first, for the chart
    private var trend: [(date: Date, count: Int)] {
        doctor.snapshots.map { ($0.date, $0.report.issues.count) }.reversed()
    }

    private var trendChart: some View {
        Chart(trend, id: \.date) { point in
            // `.stepEnd`: the count holds until the next report, rather than sloping between them
            LineMark(x: .value("Date", point.date), y: .value("Issues", point.count))
                .interpolationMethod(.stepEnd)
            PointMark(x: .value("Date", point.date), y: .value("Issues", point.count))
                .symbolSize(16)
        }
        .chartYAxisLabel("Issues")
        .chartYScale(domain: 0...max(2, trend.map(\.count).max() ?? 0))
        .frame(width: 280, height: 90)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if doctor.snapshots.isEmpty {
            EmptyStateView(
                title: "No doctor reports",
                systemImage: "stethoscope",
                message: "Each run saves brew doctor's report. Click Check Now to run it straight away."
            )
        } else {
            // A fixed-width list next to a flexible detail pane
            HStack(spacing: 0) {
                issueList
                    .frame(width: 300)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var issueList: some View {
        let histories = doctor.histories
        return List(selection: $selectedIssueID) {
            Section(issues.isEmpty ? "Current Issues" : "Current Issues (\(issues.count))") {
                if issues.isEmpty {
                    Label("Your system is ready to brew", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .selectionDisabled()
                }
                ForEach(issues) { issue in
                    DoctorIssueRow(issue: issue, history: histories[issue.id], resolved: false)
                        .tag(issue.id)
                }
            }
            if !resolved.isEmpty {
                Section("Fixed Recently") {
                    ForEach(resolved, id: \.latest.id) { history in
                        DoctorIssueRow(issue: history.latest, history: history, resolved: true)
                            .tag(history.latest.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let snapshot, let issue = issues.first(where: { $0.id == selectedIssueID }) {
            DoctorIssueDetail(issue: issue, report: snapshot.report, history: doctor.histories[issue.id])
        } else if let history = resolved.first(where: { $0.latest.id == selectedIssueID }),
                  let report = doctor.snapshots.first(where: { $0.date == history.lastSeen })?.report {
            DoctorIssueDetail(issue: history.latest, report: report, history: history)
        } else {
            EmptyStateView(
                title: "Your system is ready to brew",
                systemImage: "checkmark.seal",
                message: "brew doctor found nothing to fix in this report."
            )
        }
    }

    // MARK: Labels

    private func title(for snapshot: DoctorSnapshot) -> String {
        let date = snapshot.date.formatted(date: .abbreviated, time: .shortened)
        return snapshot.source == .manual ? "\(date) (Check Now)" : date
    }

    private func sourceDescription(_ snapshot: DoctorSnapshot) -> String {
        let when = "\(snapshot.date.formatted(date: .abbreviated, time: .shortened)) · \(snapshot.date.relativeDescription)"
        switch snapshot.source {
        case .manual:
            return "Checked from the app, \(when)"
        case .run(let id):
            let trigger = model.run(withID: id)?.summary?.trigger
            return "From the \(trigger.map { "\($0) " } ?? "")run on \(when)"
        }
    }
}

/// One issue in the list: importance icon, headline, and how long it has been around.
private struct DoctorIssueRow: View {
    let issue: DoctorIssue
    let history: DoctorIssueHistory?
    let resolved: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: resolved ? "checkmark.circle.fill" : issue.importance.systemImage)
                .foregroundStyle(resolved ? .green : issue.importance.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.headline)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        guard let history else { return issue.importance.title }
        if resolved, let fixed = history.resolvedAt {
            return "Fixed \(fixed.relativeDescription)"
        }
        return "\(issue.importance.title) · since \(history.firstSeen.formatted(date: .abbreviated, time: .omitted))"
    }
}

extension DoctorImportance {
    var color: Color {
        switch self {
        case .important: .red
        case .recommended: .orange
        case .informational: .blue
        }
    }

    var systemImage: String {
        switch self {
        case .important: "exclamationmark.octagon.fill"
        case .recommended: "exclamationmark.triangle.fill"
        case .informational: "info.circle.fill"
        }
    }
}

#Preview {
    DoctorView()
        .environment(AppModel())
        .frame(width: 1000, height: 640)
}
