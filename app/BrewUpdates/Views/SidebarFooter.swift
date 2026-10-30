import AppKit
import SwiftUI

/// The app's icon, name and versions, pinned below the sidebar's sections. Clicking it opens
/// the standard About panel.
struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            NSApplication.shared.orderFrontStandardAboutPanel(nil)
        } label: {
            HStack(spacing: 10) {
                // The same artwork as the Dock and Finder (Assets.xcassets/AppIcon)
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Brew Updates")
                        .font(.callout.weight(.semibold))
                    Text(versionLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            // Makes the whole row clickable, not just the icon and text
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("About Brew Updates")
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// "1.0.0 · script 2.4.1"
    private var versionLine: String {
        let script = model.scriptVersion.map { " · script \($0.description)" } ?? ""
        return AppVersion.current.version + script
    }
}
