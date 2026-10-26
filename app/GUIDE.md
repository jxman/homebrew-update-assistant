# Brew Updates App — Xcode & SwiftUI Guide

A working guide to the SwiftUI app in `app/`: how to open and run it in Xcode, when to use
Xcode versus the terminal, and the SwiftUI concepts the code uses, each pointing at the file
where it appears.

## Contents

- [How the pieces fit](#how-the-pieces-fit)
- [First-time setup](#first-time-setup)
- [Working in Xcode](#working-in-xcode)
- [When to use Xcode vs. the terminal](#when-to-use-xcode-vs-the-terminal)
- [SwiftUI concepts used in this app](#swiftui-concepts-used-in-this-app)
- [Things to try](#things-to-try)
- [Troubleshooting](#troubleshooting)

## How the pieces fit

```mermaid
flowchart LR
    agent["LaunchAgent<br/>(3 AM)"] --> script["~/bin/brew-updates.command"]
    script --> logs["~/.brew_logs<br/>*.log, *.summary.json, *.security.json"]
    subgraph app["Brew Updates app (read-only in phase 1)"]
        services["Services/<br/>RunStore, BrewService, SystemStatus"] --> model["AppModel<br/>(shared state)"]
        model --> views["Views/<br/>Dashboard, Installed, Runs, Security, menu bar"]
    end
    logs --> services
    brew["brew info --json=v2"] --> services
    plist["LaunchAgent plist<br/>+ ~/.brew_update_config"] --> services
```

| Folder | What lives there | Has UI code? |
|--------|------------------|--------------|
| `BrewUpdates/Models/` | Plain data types and parsers (run summary, logs, schedule, grype report) | No |
| `BrewUpdates/Services/` | Talking to the system: files, `brew`, `launchctl` | No |
| `BrewUpdates/AppModel.swift` | The single shared state object the screens read | No (but drives the UI) |
| `BrewUpdates/Views/` | SwiftUI screens and small components | Yes |
| `BrewUpdatesTests/` | Unit tests for Models and Services | No |
| `project.yml` | XcodeGen definition the Xcode project is generated from | — |

Keeping parsing and file access out of the views is deliberate: that code is testable without
launching the app, and the views stay focused on layout.

## First-time setup

```bash
brew install xcodegen swiftlint     # once
cd app
xcodegen generate                   # creates BrewUpdates.xcodeproj (not committed to git)
open BrewUpdates.xcodeproj
```

Re-run `xcodegen generate` whenever files are **added, removed or renamed**, or after
`project.yml` changes. Xcode notices the regenerated project and reloads it.

> **Don't change build settings in Xcode's project editor.** The next `xcodegen generate`
> overwrites them. Make setting changes in `project.yml` instead.

## Working in Xcode

### The window at a glance

- **Navigator** (left, ⌘0): the file tree. ⌘1 shows files; ⌘⇧O opens any file by name.
- **Editor** (centre): code. Option-click any symbol for its documentation.
- **Canvas** (right of editor, ⌥⌘↩): live SwiftUI previews.
- **Debug area** (bottom, ⌘⇧Y): console output from `print()` and runtime warnings.
- **Toolbar**: the scheme (`BrewUpdates`) and destination (`My Mac`) next to the ▶ button.

### Everyday shortcuts

| Action | Shortcut | Notes |
|--------|----------|-------|
| Build | ⌘B | Compile only; errors show inline and in the Issue navigator (⌘5) |
| Run | ⌘R | Builds, then launches the app. A mug icon appears in the menu bar |
| Stop | ⌘. | Quits the running app |
| Test | ⌘U | Runs `BrewUpdatesTests`; results in the Test navigator (⌘6) |
| Clean build folder | ⌘⇧K | Use when the build acts strangely |
| Show/refresh preview | ⌥⌘↩ / ⌥⌘P | Preview the open SwiftUI file |
| Open quickly | ⌘⇧O | Jump to any file or type |

### Previews

Every screen file ends with a `#Preview { ... }` block. Open, say,
`Views/DashboardView.swift` and press ⌥⌘↩: the canvas renders the view, and edits to the
layout update it within a second or two. Previews here use a real `AppModel()`, so they show
your actual runs and packages. If a preview stops updating, press ⌥⌘P.

### Debugging

- Click a line number to set a **breakpoint** (blue arrow). Run with ⌘R; when execution
  stops there, hover over variables or type `po someVariable` in the console.
- `print("…")` output appears in the debug area.
- Purple runtime warnings (for example "Publishing changes from background threads") point
  at concurrency mistakes. Treat them as bugs.

## When to use Xcode vs. the terminal

| Task | Where | Why |
|------|-------|-----|
| Writing and changing code | Either (Claude edits files from the terminal) | Files are plain Swift; Xcode picks up changes on disk |
| Adding/removing files | Terminal: `xcodegen generate` | The project file is generated |
| Checking it compiles, running tests | Terminal: `xcodebuild … test` (what Claude runs) or ⌘U | Same result |
| **Seeing the app run** | **Xcode: ⌘R** | Launches it with the debugger attached |
| **Tweaking layout and visuals** | **Xcode: previews** | Instant visual feedback |
| Stepping through a bug | Xcode: breakpoints | The debugger is in Xcode |
| Build settings, signing | `project.yml`, then regenerate | Xcode edits would be overwritten |
| Committing | Terminal | Pre-commit hooks (SwiftLint, ShellCheck, gitleaks…) run on `git commit` |

**In practice:** Claude makes changes and verifies them from the terminal. You switch to
Xcode to press ⌘R and look, or to use previews when you want to adjust how something looks.

Terminal equivalents (useful for scripts):

```bash
cd app
xcodebuild -project BrewUpdates.xcodeproj -scheme BrewUpdates -destination 'platform=macOS,arch=arm64' build
xcodebuild -project BrewUpdates.xcodeproj -scheme BrewUpdates -destination 'platform=macOS,arch=arm64' test
swiftlint lint --strict
```

## SwiftUI concepts used in this app

Read these roughly in order; each builds on the previous one.

### 1. Views are values that describe the UI

A view is a `struct` conforming to `View` with a `body` describing what to show. SwiftUI calls
`body` again whenever the data it depends on changes. You never update the screen by hand.

```swift
struct StatusBadge: View {          // Views/Components.swift
    let status: RunStatus
    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .foregroundStyle(status.color)
    }
}
```

`some View` means "some specific view type the compiler works out". You don't have to spell
out the nested type.

### 2. Modifiers wrap views, and order matters

`.padding()`, `.background(...)` and `.font(...)` each return a *new* view wrapping the old one.
`.padding().background(.red)` colours the padded area; `.background(.red).padding()` colours
only the content and pads outside it. See `Card` in `Views/Components.swift`.

### 3. Layout containers

`VStack`/`HStack` stack views vertically or horizontally, `Spacer()` pushes them apart, `Grid`
aligns rows and columns (the System card in `DashboardView`), and `LazyVGrid` flows cards into
as many columns as fit (the dashboard cards).

### 4. `@State`: data a view owns

`@State` stores values that belong to one view and survive re-renders, such as the search text
and filter in `InstalledView`. Changing one re-renders the view. Mark them `private`.

### 5. Bindings (`$`): letting a control edit state

`TextField("…", text: $searchText)` passes a **binding**, a two-way connection, so the text
field can both read and write `searchText`. The `$` prefix makes a binding from a `@State`
property. Custom bindings with `Binding(get:set:)` appear in `LogView` (level toggles) and
`SecurityView` (severity toggles).

### 6. `@Observable` models shared through the environment

`AppModel` is an `@Observable` class holding the app-wide data. It's created once in
`BrewUpdatesApp` with `@State` and injected with `.environment(model)`. Any view reads it with:

```swift
@Environment(AppModel.self) private var model
```

SwiftUI records which properties each view's `body` actually reads and re-renders only those
views when they change. To make a binding into the model (as `ContentView` does for the
sidebar selection), wrap it with `@Bindable var model = model`.

### 7. Derived data as computed properties

Instead of storing filtered lists, views compute them, for example `rows` in `InstalledView`
and `outdatedPackages` in `AppModel`. Computed values can't go stale because they're
recalculated from the source data on every render.

### 8. Lists, tables and identity

`List`, `ForEach` and `Table` need to tell rows apart, so the models conform to `Identifiable`
(an `id` property). `Run.id` is the run timestamp; `InstalledPackage.id` is `formula:name`.
Stable IDs let SwiftUI animate and keep selection correctly. `Table` with `sortOrder:` gives
clickable, sortable column headers (`InstalledView`, `SecurityView`).

### 9. Async work: `async`/`await` and `.task`

Loading data (reading files, running `brew`) is `async` so the UI never freezes.
`.task { await model.start() }` starts work when a view appears and cancels it when the view
disappears. `.task(id: selectedRunID)` reruns whenever the id changes (`SecurityView`).
`async let` in `AppModel.refresh()` runs several loads at the same time.

### 10. `@MainActor` and `Sendable`

UI state must only change on the main thread. `@MainActor` on `AppModel` makes the compiler
enforce that. Background work happens in `Services/` (plain structs marked `Sendable`, safe to
pass between threads) and hands results back to the model. Swift 6 checks this at compile
time, so data races show up as build errors instead of random crashes.

### 11. `@ViewBuilder` and generic containers

`@ViewBuilder` lets a function or property return different views from an `if`/`switch`
(`ContentView.detail(for:)`). `Card<Content: View>` takes a `@ViewBuilder` closure so it can
wrap any content, just like `VStack { … }`.

### 12. Navigation and scenes

- `NavigationSplitView` gives the sidebar-plus-detail layout (`ContentView`).
- `HSplitView` is the resizable list and detail split in `RunsView`.
- `.inspector` is the collapsible details panel on the right of `InstalledView`.
- An `App` is made of **scenes**: here a `Window` and a `MenuBarExtra`
  (`BrewUpdatesApp.swift`). Both share one `AppModel`, so the menu bar and window always agree.

## Things to try

Small, safe changes for practice. Use previews (⌥⌘↩) to see the result immediately.

1. **Change the card layout.** In `DashboardView`, change `GridItem(.adaptive(minimum: 260))`
   to `200` or `400` and watch the columns reflow.
2. **Add a row to the System card.** Add another `GridRow` showing `model.runs.count` as
   "Runs on disk".
3. **Add a filter.** Add `case pinned = "Pinned"` to `InstalledView.Filter` and handle it in
   `matchesFilter` (`package.isPinned`). The segmented control picks it up automatically.
4. **Change colours.** Edit `RunStatus.color` in `Components.swift`, for example make
   `.partial` yellow.
5. **Write a test.** Add a case to `ScheduleTests` for a monthly schedule
   (`<key>Day</key><integer>1</integer>`) and run ⌘U.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| New file doesn't appear in Xcode / "cannot find X in scope" | `cd app && xcodegen generate` |
| macOS asks whether `xctest` or Xcode may access Documents | The repo is in `~/Documents`. Allow it for Xcode. Command-line builds use the default DerivedData in `~/Library` to avoid this |
| Orange banner "Deployed script is v…" | Run `./scripts/setup.sh` from the repo root to deploy the current script |
| Preview shows an error or stops updating | ⌥⌘P to refresh; ⌘⇧K then ⌘B if it persists |
| Build fails after pulling changes | `xcodegen generate`, then ⌘⇧K and build again |
| "Untrusted developer" / signing prompts | The app is ad-hoc signed for local use (`CODE_SIGN_IDENTITY: "-"` in `project.yml`); building it yourself avoids Gatekeeper prompts |
