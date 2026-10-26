import SwiftUI

/// The Settings window (⌘, or "Settings…" in the app and menu bar menus).
///
/// Each tab edits a *draft* copy and writes it only on Save: saving the schedule reloads the
/// LaunchAgent, which shouldn't happen on every click.
struct SettingsView: View {
    var body: some View {
        // `Tab` (macOS 15+) gives the toolbar-style tabs used by system Settings windows
        TabView {
            Tab("Schedule", systemImage: "calendar") {
                ScheduleSettingsView()
            }
            Tab("Updates", systemImage: "gearshape") {
                UpdateSettingsView()
            }
        }
        .frame(width: 560, height: 640)
    }
}

/// Bottom bar of a settings tab: unsaved/validation/error message, Revert and Save (⌘S).
struct SaveBar: View {
    let hasChanges: Bool
    let validationError: String?
    let saveError: String?
    let isSaving: Bool
    let onRevert: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            message
            Spacer()
            if isSaving {
                ProgressView().controlSize(.small)
            }
            Button("Revert", action: onRevert)
                .disabled(!hasChanges || isSaving)
            Button("Save", action: onSave)
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges || validationError != nil || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var message: some View {
        if let saveError {
            Label(saveError, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        } else if let validationError {
            Label(validationError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if hasChanges {
            Label("Unsaved changes", systemImage: "pencil.circle.fill")
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
}
