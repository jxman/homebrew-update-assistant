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
