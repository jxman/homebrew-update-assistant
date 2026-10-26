import SwiftUI

/// Settings from `~/.brew_update_config`. They apply to every run: scheduled, from the app,
/// or from Terminal.
struct UpdateSettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var original = ConfigDraft()
    @State private var draft = ConfigDraft()
    @State private var isSaving = false
    @State private var saveError: String?

    private var hasChanges: Bool { draft != original }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Defaults") {
                    // `!draft.skipCasksByDefault` reads more naturally as "include", so invert it
                    Toggle("Include casks (apps)", isOn: Binding(
                        get: { !draft.skipCasksByDefault },
                        set: { draft.skipCasksByDefault = !$0 }
                    ))
                    Toggle("Clean up old versions after upgrading", isOn: $draft.cleanupByDefault)
                }

                Section("Backups & Logs") {
                    Stepper("Keep \(draft.maxBackupCount) Brewfile backups", value: $draft.maxBackupCount, in: 1...50)
                    Stepper("Delete run logs after \(draft.logRetentionDays) days", value: $draft.logRetentionDays, in: 1...365)
                }

                Section {
                    Toggle("Show notifications", isOn: $draft.notificationsEnabled)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("When a run starts, when updates are found, and when it finishes.")
                        .foregroundStyle(.secondary)
                }

                securitySection

                Section("Never Update These Formulae") {
                    ExclusionListEditor(names: $draft.excludedFormulae)
                }
                Section("Never Update These Casks") {
                    ExclusionListEditor(names: $draft.excludedCasks)
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
        .task {
            await model.reloadSettings()
            load()
        }
        // E.g. an exclusion changed from the Installed screen
        .onChange(of: model.config) {
            if !hasChanges { load() }
        }
    }

    private var securitySection: some View {
        Section {
            Toggle("Scan installed packages for vulnerabilities (grype)", isOn: $draft.securityScanEnabled)
            LabeledContent("Report") {
                HStack(spacing: 4) {
                    ForEach(ConfigDraft.scanSeverities) { severity in
                        Toggle(severity.rawValue, isOn: severityBinding(severity))
                            .toggleStyle(.button)
                            .tint(severity.color)
                    }
                }
            }
            .disabled(!draft.securityScanEnabled)
        } header: {
            Text("Security")
        } footer: {
            Text("Needs grype: brew install grype")
                .foregroundStyle(.secondary)
        }
    }

    private func severityBinding(_ severity: Severity) -> Binding<Bool> {
        Binding(
            get: { draft.securitySeverities.contains(severity) },
            set: { isOn in
                if isOn { draft.securitySeverities.insert(severity) } else { draft.securitySeverities.remove(severity) }
            }
        )
    }

    private func load() {
        let loaded = ConfigDraft(config: model.config)
        original = loaded
        draft = loaded
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.saveConfig(draft.changes(from: original))
            saveError = nil
            load()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Rows for an exclusion list: one per name with a remove button, then a field to add one.
///
/// Its `body` returns several views; inside a Form `Section` each becomes its own row.
private struct ExclusionListEditor: View {
    /// `@Binding` is a reference to state owned by the parent view, so edits here change
    /// the parent's draft directly
    @Binding var names: [String]
    @State private var newName = ""

    private var trimmedName: String { newName.trimmingCharacters(in: .whitespaces) }
    private var canAdd: Bool {
        BrewConfig.isValidExclusionName(trimmedName) && !names.contains(trimmedName)
    }

    var body: some View {
        ForEach(names, id: \.self) { name in
            HStack {
                Text(name)
                Spacer()
                Button {
                    names.removeAll { $0 == name }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Remove \(name)")
            }
        }
        HStack {
            TextField("Package name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            Button("Add", action: add)
                .disabled(!canAdd)
        }
        if !trimmedName.isEmpty && !BrewConfig.isValidExclusionName(trimmedName) {
            Text("Only letters, digits and @ . _ / - are allowed.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func add() {
        guard canAdd else { return }
        names.append(trimmedName)
        newName = ""
    }
}

#Preview {
    UpdateSettingsView()
        .environment(AppModel())
        .frame(width: 560, height: 640)
}
