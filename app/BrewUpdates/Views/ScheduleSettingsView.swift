import SwiftUI

/// When the LaunchAgent runs the script, and with which options.
struct ScheduleSettingsView: View {
    @Environment(AppModel.self) private var model

    /// What is on disk, and the edited copy. Comparing them tells us if there are unsaved changes.
    @State private var original = ScheduleDraft()
    @State private var draft = ScheduleDraft()
    @State private var isSaving = false
    @State private var isTogglingEnabled = false
    @State private var saveError: String?

    private var hasChanges: Bool { draft != original }
    private var isInstalled: Bool { model.schedule != nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                statusSection
                if isInstalled {
                    if !original.isRepresentable {
                        Section {
                            Label(
                                "The current schedule (\(model.schedule?.description ?? "")) can't be shown here. Saving replaces it.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
                        }
                    }
                    whenSection
                    optionsSection
                }
            }
            .formStyle(.grouped)
            Divider()
            SaveBar(
                hasChanges: hasChanges,
                validationError: draft.validationError,
                saveError: saveError,
                isSaving: isSaving,
                onRevert: { draft = original },
                onSave: { Task { await save() } }
            )
        }
        // Re-read the plist each time the tab opens, in case it was edited elsewhere
        .task {
            await model.reloadSettings()
            load()
        }
        // Pick up outside changes, but never throw away the user's unsaved edits
        .onChange(of: model.schedule) {
            if !hasChanges { load() }
        }
    }

    // MARK: Sections

    private var statusSection: some View {
        Section {
            Toggle("Run updates on a schedule", isOn: enabledBinding)
                .disabled(!isInstalled || isTogglingEnabled)
            if !isInstalled {
                Text("The LaunchAgent isn't installed. Run scripts/setup.sh in the repo to install it.")
                    .foregroundStyle(.secondary)
            } else if model.isLaunchAgentLoaded == true, let next = original.schedule.nextRun(after: .now) {
                LabeledContent("Next run", value: next.formatted(date: .abbreviated, time: .shortened))
            } else if model.isLaunchAgentLoaded == false {
                Text("Scheduled updates are off. Updates only run when started from the app or Terminal.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var whenSection: some View {
        Section("When") {
            Picker("Repeat", selection: $draft.frequency) {
                ForEach(ScheduleDraft.Frequency.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            switch draft.frequency {
            case .daily:
                EmptyView()
            case .weekly:
                LabeledContent("On") {
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { weekday in
                            Toggle(Calendar.current.shortWeekdaySymbols[weekday], isOn: weekdayBinding(weekday))
                                .toggleStyle(.button)
                        }
                    }
                }
            case .monthly:
                Stepper("On day \(draft.dayOfMonth) of the month", value: $draft.dayOfMonth, in: 1...28)
            }

            DatePicker("At", selection: timeBinding, displayedComponents: .hourAndMinute)

            if let next = draft.schedule.nextRun(after: .now) {
                LabeledContent("Next run would be", value: next.formatted(date: .complete, time: .shortened))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle("Verbose logging", isOn: $draft.verbose)
            Toggle("Skip casks", isOn: $draft.skipCasks)
            Toggle("Skip cleanup", isOn: $draft.skipCleanup)
            Toggle("Skip security scan", isOn: $draft.skipSecurityScan)
            LabeledContent("Command") {
                Text((["brew-updates.command"] + draft.scriptArguments).joined(separator: " "))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        } header: {
            Text("Scheduled Run Options")
        } footer: {
            Text("--yes is always included because nobody is there to answer prompts at night.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Bindings
    // A custom `Binding(get:set:)` adapts a value to what a control expects: here a
    // DatePicker that edits a Date, and toggles that edit membership of a Set.

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: draft.hour, minute: draft.minute)) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.hour = parts.hour ?? draft.hour
                draft.minute = parts.minute ?? draft.minute
            }
        )
    }

    private func weekdayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { draft.weekdays.contains(weekday) },
            set: { isOn in
                if isOn { draft.weekdays.insert(weekday) } else { draft.weekdays.remove(weekday) }
            }
        )
    }

    /// The toggle applies immediately (it doesn't touch the plist, only whether launchd runs it)
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.isLaunchAgentLoaded == true },
            set: { enabled in
                Task {
                    isTogglingEnabled = true
                    defer { isTogglingEnabled = false }
                    do {
                        try await model.setScheduleEnabled(enabled)
                        saveError = nil
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
            }
        )
    }

    // MARK: Loading and saving

    private func load() {
        let loaded = model.schedule.map(ScheduleDraft.init(schedule:)) ?? ScheduleDraft()
        original = loaded
        draft = loaded
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.saveSchedule(draft)
            saveError = nil
            load()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    ScheduleSettingsView()
        .environment(AppModel())
        .frame(width: 560, height: 640)
}
