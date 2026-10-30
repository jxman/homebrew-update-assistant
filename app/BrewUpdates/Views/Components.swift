import SwiftUI

// Small reusable pieces shared by several screens.

extension RunStatus {
    var title: String {
        switch self {
        case .success: "Success"
        case .partial: "Partial"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .running: "Running"
        case .legacy: "No summary"
        case .unknown: "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "stop.circle.fill"
        case .running: "arrow.triangle.2.circlepath.circle.fill"
        case .legacy, .unknown: "doc.text"
        }
    }

    var color: Color {
        switch self {
        case .success: .green
        case .partial: .orange
        case .failed: .red
        case .running: .blue
        case .cancelled, .legacy, .unknown: .secondary
        }
    }
}

extension Severity {
    var color: Color {
        switch self {
        case .critical: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .blue
        case .negligible, .unknown: .secondary
        }
    }
}

/// Colored icon + label for a run's outcome.
struct StatusBadge: View {
    let status: RunStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .foregroundStyle(status.color)
            .runningAnimation(status)
    }
}

extension View {
    /// Spins the status symbol while a run is in progress. `symbolEffect` animates an SF Symbol
    /// in place; `isActive` starts and stops it as the status changes, so finished runs sit still.
    func runningAnimation(_ status: RunStatus) -> some View {
        symbolEffect(.rotate, options: .repeat(.continuous), isActive: status == .running)
    }
}

/// Places views left to right and starts a new row when the next one wouldn't fit,
/// like words in a paragraph. Each view keeps its natural size.
///
/// A custom `Layout` answers two questions: how big am I for this proposed size
/// (`sizeThatFits`), and where does each child go (`placeSubviews`). Both use `rows(for:)`.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var top = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var left = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: left, y: top), proposal: ProposedViewSize(size))
                left += size.width + spacing
            }
            top += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Small rounded "pill" used for tags like Outdated, Pinned or a severity.
struct Pill: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// A titled box for the dashboard.
///
/// Generic over `Content` so callers pass any views in a trailing closure, the same way
/// `VStack { ... }` works. `@ViewBuilder` is what allows several views in that closure.
struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Centered message for empty or error states.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message {
                Text(message)
            }
        }
    }
}

extension Date {
    /// "3 hours ago", "in 9 hours"
    var relativeDescription: String {
        formatted(.relative(presentation: .named))
    }
}

extension Int {
    /// Seconds -> "8m 27s"
    var durationDescription: String {
        Duration.seconds(self).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow))
    }
}
