import SwiftUI

/// App entry point. A SwiftUI app is a set of *scenes*: here, one main window and one
/// menu bar item, both sharing the same `AppModel`.
@main
struct BrewUpdatesApp: App {
    /// `@State` makes SwiftUI create the model once and keep it alive for the app's lifetime.
    @State private var model = AppModel()

    var body: some Scene {
        // `Window` (not `WindowGroup`) because there is only ever one main window
        Window("Brew Updates", id: "main") {
            ContentView()
                // Puts the model in the environment so any view below can read it
                // with `@Environment(AppModel.self)`
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r")
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
    }
}
