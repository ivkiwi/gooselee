import SwiftUI

struct TranscriptCleanupPromptsManagerView: View {
    let appState: AppState
    let controller: GuesliController
    let onClose: () -> Void

    @State private var isCreatingPrompt = false
    @State private var editingPromptID: String?
    @State private var draftPromptName = ""
    @State private var draftPrompt = ""
    @State private var nameValidationMessage: String?
    @State private var showPromptValidationError = false
    @State private var promptToDelete: CustomTranscriptCleanupPrompt?

    private var activePromptID: String {
        appState.config.activeTranscriptCleanupPromptId
    }

    private var builtInPresets: [TranscriptCleanupPromptPreset] {
        TranscriptCleanupPrompts.builtIns
    }

    private var customPresets: [CustomTranscriptCleanupPrompt] {
        appState.config.customTranscriptCleanupPrompts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing20) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: GuesliTheme.spacing16) {
                    presetSection(title: "Built-in Presets") {
                        VStack(spacing: GuesliTheme.spacing8) {
                            ForEach(builtInPresets) { preset in
                                builtInPresetRow(preset)
                            }
                        }
                    }

                    presetSection(title: "Custom Prompts") {
                        if customPresets.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: GuesliTheme.spacing8) {
                                ForEach(customPresets) { preset in
                                    customPresetRow(preset)
                                }
                            }
                        }
                    }

                    if isCreatingPrompt || editingPromptID != nil {
                        promptEditor
                    }
                }
                .padding(.bottom, GuesliTheme.spacing4)
            }
        }
        .padding(GuesliTheme.spacing24)
        .frame(minWidth: 760, minHeight: 560)
        .background(GuesliTheme.backgroundBase)
        .alert(
            "Delete \"\(promptToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { promptToDelete != nil },
                set: { if !$0 { promptToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                promptToDelete = nil
            }
            Button("Delete", role: .destructive) {
                guard let preset = promptToDelete else { return }
                controller.deleteTranscriptCleanupPrompt(id: preset.id)
                if editingPromptID == preset.id {
                    resetPromptEditor()
                }
                promptToDelete = nil
            }
        } message: {
            Text("This prompt will be removed. Existing dictations are not affected.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Manage Cleanup Prompts")
                    .font(GuesliTheme.title2())
                    .foregroundStyle(GuesliTheme.textPrimary)
                Text("Create reusable prompts for Guesli dictation cleanup.")
                    .font(GuesliTheme.callout())
                    .foregroundStyle(GuesliTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: GuesliTheme.spacing8) {
                if isCreatingPrompt || editingPromptID != nil {
                    actionButton("Cancel", systemImage: "xmark") {
                        resetPromptEditor()
                    }
                } else {
                    actionButton("New prompt", systemImage: "plus") {
                        beginCreatingPrompt()
                    }
                }

                actionButton("Done", systemImage: "checkmark") {
                    onClose()
                }
                .disabled(isEditingPromptInProgress)
                .opacity(isEditingPromptInProgress ? 0.55 : 1)
                .help(isEditingPromptInProgress ? "Finish or cancel prompt editing before closing." : "Close prompt manager")
            }
        }
    }

    private func presetSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
            Text(title.uppercased())
                .font(GuesliTheme.captionMedium())
                .foregroundStyle(GuesliTheme.textTertiary)
            content()
        }
    }

    private var emptyState: some View {
        HStack(spacing: GuesliTheme.spacing8) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 11))
                .foregroundStyle(GuesliTheme.textTertiary)
            Text("No custom cleanup prompts yet.")
                .font(GuesliTheme.callout())
                .foregroundStyle(GuesliTheme.textTertiary)
        }
        .padding(.horizontal, GuesliTheme.spacing12)
        .padding(.vertical, 10)
        .background(GuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func builtInPresetRow(_ preset: TranscriptCleanupPromptPreset) -> some View {
        presetRow(
            name: preset.name,
            prompt: preset.prompt,
            isActive: activePromptID == preset.id,
            systemImage: "sparkles"
        ) {
            actionButton("Use", systemImage: "checkmark") {
                controller.selectTranscriptCleanupPrompt(id: preset.id)
            }
            .disabled(activePromptID == preset.id)

            actionButton("Duplicate", systemImage: "doc.on.doc") {
                beginDuplicatingPrompt(name: preset.name, prompt: preset.prompt)
            }
        }
    }

    private func customPresetRow(_ preset: CustomTranscriptCleanupPrompt) -> some View {
        presetRow(
            name: preset.name,
            prompt: preset.prompt,
            isActive: activePromptID == preset.id,
            systemImage: "text.badge.checkmark"
        ) {
            actionButton("Use", systemImage: "checkmark") {
                controller.selectTranscriptCleanupPrompt(id: preset.id)
            }
            .disabled(activePromptID == preset.id)

            actionButton("Edit", systemImage: "pencil") {
                beginEditingPrompt(preset)
            }

            actionButton("Delete", systemImage: "trash", role: .destructive) {
                promptToDelete = preset
            }
        }
    }

    private func presetRow<Actions: View>(
        name: String,
        prompt: String,
        isActive: Bool,
        systemImage: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
            HStack(alignment: .top, spacing: GuesliTheme.spacing12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: systemImage)
                            .font(.system(size: 10))
                            .foregroundStyle(GuesliTheme.accent)
                        Text(name)
                            .font(GuesliTheme.captionMedium())
                            .foregroundStyle(GuesliTheme.textPrimary)
                        if isActive {
                            Text("Active")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(GuesliTheme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(GuesliTheme.accentSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                        }
                    }
                    Text(prompt)
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                HStack(spacing: GuesliTheme.spacing8) {
                    actions()
                }
            }
        }
        .padding(GuesliTheme.spacing12)
        .background(GuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                .strokeBorder(isActive ? GuesliTheme.accent.opacity(0.35) : GuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
            Text(isCreatingPrompt ? "New prompt" : "Edit prompt")
                .font(GuesliTheme.captionMedium())
                .foregroundStyle(GuesliTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textSecondary)
                TextField("Context-aware cleanup", text: $draftPromptName)
                    .textFieldStyle(.roundedBorder)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                nameValidationMessage == nil ? .clear : GuesliTheme.recording.opacity(0.75),
                                lineWidth: 1
                            )
                    }
                    .onChange(of: draftPromptName) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            nameValidationMessage = nil
                        }
                    }
                if let nameValidationMessage {
                    Text(nameValidationMessage)
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.recording)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textSecondary)
                TextEditor(text: $draftPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(GuesliTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                    .padding(GuesliTheme.spacing8)
                    .background(GuesliTheme.backgroundBase)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                            .strokeBorder(
                                showPromptValidationError ? GuesliTheme.recording.opacity(0.75) : GuesliTheme.surfaceBorder,
                                lineWidth: 1
                            )
                    )
                    .onChange(of: draftPrompt) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showPromptValidationError = false
                        }
                    }
                if showPromptValidationError {
                    Text("Enter cleanup instructions for this prompt.")
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.recording)
                }
            }

            HStack {
                Spacer()
                actionButton(
                    isCreatingPrompt ? "Create prompt" : "Save changes",
                    systemImage: isCreatingPrompt ? "plus.circle" : "checkmark.circle"
                ) {
                    savePromptEditor()
                }
            }
        }
        .padding(GuesliTheme.spacing12)
        .background(GuesliTheme.surfacePrimary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium)
                .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func beginCreatingPrompt() {
        isCreatingPrompt = true
        editingPromptID = nil
        draftPromptName = ""
        draftPrompt = ""
        clearValidationErrors()
    }

    private func beginDuplicatingPrompt(name: String, prompt: String) {
        isCreatingPrompt = true
        editingPromptID = nil
        draftPromptName = suggestedUniqueName(for: "\(name) Copy")
        draftPrompt = prompt
        clearValidationErrors()
    }

    private func beginEditingPrompt(_ preset: CustomTranscriptCleanupPrompt) {
        isCreatingPrompt = false
        editingPromptID = preset.id
        draftPromptName = preset.name
        draftPrompt = preset.prompt
        clearValidationErrors()
    }

    private func resetPromptEditor() {
        isCreatingPrompt = false
        editingPromptID = nil
        draftPromptName = ""
        draftPrompt = ""
        clearValidationErrors()
    }

    private func savePromptEditor() {
        let trimmedName = draftPromptName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        nameValidationMessage = nil
        showPromptValidationError = trimmedPrompt.isEmpty
        if trimmedName.isEmpty {
            nameValidationMessage = "Enter a prompt name."
        } else if presetNameExists(trimmedName, excludingID: editingPromptID) {
            nameValidationMessage = "Use a unique prompt name."
        }
        guard nameValidationMessage == nil, !trimmedPrompt.isEmpty else { return }

        if let editingPromptID {
            controller.updateTranscriptCleanupPrompt(
                id: editingPromptID,
                name: trimmedName,
                prompt: trimmedPrompt
            )
        } else {
            controller.createTranscriptCleanupPrompt(
                name: trimmedName,
                prompt: trimmedPrompt
            )
        }
        resetPromptEditor()
    }

    private var isEditingPromptInProgress: Bool {
        isCreatingPrompt || editingPromptID != nil
    }

    private func clearValidationErrors() {
        nameValidationMessage = nil
        showPromptValidationError = false
    }

    private func presetNameExists(_ name: String, excludingID: String?) -> Bool {
        let normalizedName = normalizedPresetName(name)
        if builtInPresets.contains(where: { normalizedPresetName($0.name) == normalizedName }) {
            return true
        }
        return customPresets.contains { preset in
            preset.id != excludingID && normalizedPresetName(preset.name) == normalizedName
        }
    }

    private func suggestedUniqueName(for baseName: String) -> String {
        let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackBase = trimmedBase.isEmpty ? "Custom Cleanup" : trimmedBase
        if !presetNameExists(fallbackBase, excludingID: nil) {
            return fallbackBase
        }
        for suffix in 2...99 {
            let candidate = "\(fallbackBase) \(suffix)"
            if !presetNameExists(candidate, excludingID: nil) {
                return candidate
            }
        }
        return "\(fallbackBase) \(UUID().uuidString.prefix(4))"
    }

    private func normalizedPresetName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private func actionButton(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = role == .destructive
        return Button(role: role, action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isDestructive ? GuesliTheme.recording : GuesliTheme.textPrimary)
            .padding(.horizontal, GuesliTheme.spacing12)
            .frame(height: 28)
            .background(isDestructive ? GuesliTheme.recording.opacity(0.1) : GuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                    .strokeBorder(
                        isDestructive ? GuesliTheme.recording.opacity(0.2) : GuesliTheme.surfaceBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
