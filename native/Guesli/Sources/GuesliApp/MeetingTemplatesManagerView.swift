import SwiftUI
import GuesliCore

struct MeetingTemplatesManagerView: View {
    let appState: AppState
    let controller: GuesliController
    let onClose: () -> Void

    @State private var isCreatingTemplate = false
    @State private var editingTemplateID: String?
    @State private var draftTemplateName = ""
    @State private var draftTemplatePrompt = ""
    @State private var draftTemplateIcon = MeetingTemplates.customIconFallback
    @State private var showNameValidationError = false
    @State private var showPromptValidationError = false
    @State private var templateToDelete: CustomMeetingTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Templates")
                        .font(GuesliTheme.title2())
                        .foregroundStyle(GuesliTheme.textPrimary)
                    Text("Create reusable prompt-based note formats for meetings.")
                        .font(GuesliTheme.callout())
                        .foregroundStyle(GuesliTheme.textSecondary)
                }

                Spacer()

                HStack(spacing: GuesliTheme.spacing8) {
                    if isCreatingTemplate || editingTemplateID != nil {
                        actionButton("Cancel", systemImage: "xmark") {
                            resetTemplateEditor()
                        }
                    } else {
                        actionButton("New template", systemImage: "plus") {
                            beginCreatingTemplate()
                        }
                    }

                    actionButton("Done", systemImage: "checkmark") {
                        onClose()
                    }
                    .disabled(isEditingTemplateInProgress)
                    .opacity(isEditingTemplateInProgress ? 0.55 : 1)
                    .help(isEditingTemplateInProgress ? "Finish or cancel template editing before closing." : "Close template manager")
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
                    if controller.customMeetingTemplates().isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: GuesliTheme.spacing8) {
                            ForEach(controller.customMeetingTemplates()) { template in
                                customTemplateRow(template)
                            }
                        }
                    }

                    if isCreatingTemplate || editingTemplateID != nil {
                        customTemplateEditor
                    }
                }
                .padding(.bottom, GuesliTheme.spacing4)
            }
        }
        .padding(GuesliTheme.spacing24)
        .frame(minWidth: 760, minHeight: 520)
        .background(GuesliTheme.backgroundBase)
        .alert(
            "Delete \"\(templateToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { templateToDelete != nil },
                set: { if !$0 { templateToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                templateToDelete = nil
            }
            Button("Delete", role: .destructive) {
                guard let template = templateToDelete else { return }
                controller.deleteCustomMeetingTemplate(id: template.id)
                if editingTemplateID == template.id {
                    resetTemplateEditor()
                }
                templateToDelete = nil
            }
        } message: {
            Text("This template will be permanently removed. Existing meetings will keep their saved template snapshot.")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack(spacing: GuesliTheme.spacing8) {
            Image(systemName: MeetingTemplates.customIconFallback)
                .font(.system(size: 11))
                .foregroundStyle(GuesliTheme.textTertiary)
            Text("No custom templates yet.")
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

    @ViewBuilder
    private func customTemplateRow(_ template: CustomMeetingTemplate) -> some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
            HStack(alignment: .top, spacing: GuesliTheme.spacing12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: template.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(GuesliTheme.accent)
                        Text(template.name)
                            .font(GuesliTheme.captionMedium())
                            .foregroundStyle(GuesliTheme.textPrimary)
                    }
                    Text(template.prompt)
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                HStack(spacing: GuesliTheme.spacing8) {
                    actionButton("Edit", systemImage: "pencil") {
                        beginEditingTemplate(template)
                    }
                    actionButton("Delete", systemImage: "trash", role: .destructive) {
                        templateToDelete = template
                    }
                }
            }
        }
        .padding(GuesliTheme.spacing12)
        .background(GuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var customTemplateEditor: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
            Text(isCreatingTemplate ? "New template" : "Edit template")
                .font(GuesliTheme.captionMedium())
                .foregroundStyle(GuesliTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textSecondary)
                TextField("Customer follow-up", text: $draftTemplateName)
                    .textFieldStyle(.roundedBorder)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                showNameValidationError ? GuesliTheme.recording.opacity(0.75) : .clear,
                                lineWidth: 1
                            )
                    }
                    .onChange(of: draftTemplateName) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showNameValidationError = false
                        }
                    }
                if showNameValidationError {
                    Text("Enter a template name.")
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.recording)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textSecondary)
                customIconPicker
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textSecondary)
                TextEditor(text: $draftTemplatePrompt)
                    .font(.system(size: 12))
                    .foregroundStyle(GuesliTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
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
                    .onChange(of: draftTemplatePrompt) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showPromptValidationError = false
                        }
                    }
                if showPromptValidationError {
                    Text("Enter the prompt instructions for this template.")
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.recording)
                }
            }

            HStack {
                Spacer()
                actionButton(
                    isCreatingTemplate ? "Create template" : "Save changes",
                    systemImage: isCreatingTemplate ? "plus.circle" : "checkmark.circle"
                ) {
                    saveTemplateEditor()
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

    private func beginCreatingTemplate() {
        isCreatingTemplate = true
        editingTemplateID = nil
        draftTemplateName = ""
        draftTemplatePrompt = ""
        draftTemplateIcon = MeetingTemplates.customIconFallback
        clearValidationErrors()
    }

    private func beginEditingTemplate(_ template: CustomMeetingTemplate) {
        isCreatingTemplate = false
        editingTemplateID = template.id
        draftTemplateName = template.name
        draftTemplatePrompt = template.prompt
        draftTemplateIcon = MeetingTemplates.normalizedCustomIcon(named: template.icon)
        clearValidationErrors()
    }

    private func resetTemplateEditor() {
        isCreatingTemplate = false
        editingTemplateID = nil
        draftTemplateName = ""
        draftTemplatePrompt = ""
        draftTemplateIcon = MeetingTemplates.customIconFallback
        clearValidationErrors()
    }

    private func saveTemplateEditor() {
        let trimmedName = draftTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = draftTemplatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        showNameValidationError = trimmedName.isEmpty
        showPromptValidationError = trimmedPrompt.isEmpty
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }

        if let editingTemplateID {
            controller.updateCustomMeetingTemplate(
                id: editingTemplateID,
                name: trimmedName,
                prompt: trimmedPrompt,
                icon: draftTemplateIcon
            )
        } else {
            controller.createCustomMeetingTemplate(
                name: trimmedName,
                prompt: trimmedPrompt,
                icon: draftTemplateIcon
            )
        }
        resetTemplateEditor()
    }

    private var isEditingTemplateInProgress: Bool {
        isCreatingTemplate || editingTemplateID != nil
    }

    private func clearValidationErrors() {
        showNameValidationError = false
        showPromptValidationError = false
    }

    @ViewBuilder
    private var customIconPicker: some View {
        let columns = [
            GridItem(.adaptive(minimum: 36, maximum: 36), spacing: 6)
        ]

        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
            HStack(spacing: GuesliTheme.spacing8) {
                Image(systemName: draftTemplateIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GuesliTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(GuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                Text(selectedIconLabel)
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textSecondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(MeetingTemplates.customIconOptions) { icon in
                    Button {
                        draftTemplateIcon = icon.symbolName
                    } label: {
                        Image(systemName: icon.symbolName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                draftTemplateIcon == icon.symbolName
                                    ? GuesliTheme.accent
                                    : GuesliTheme.textSecondary
                            )
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(
                                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                                    .fill(
                                        draftTemplateIcon == icon.symbolName
                                            ? GuesliTheme.accent.opacity(0.12)
                                            : GuesliTheme.backgroundRaised
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                                    .strokeBorder(
                                        draftTemplateIcon == icon.symbolName
                                            ? GuesliTheme.accent.opacity(0.35)
                                            : GuesliTheme.surfaceBorder,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(icon.label)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedIconLabel: String {
        MeetingTemplates.customIconOptions.first(where: { $0.symbolName == draftTemplateIcon })?.label ?? "Custom"
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = role == .destructive
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isDestructive ? GuesliTheme.recording : GuesliTheme.textPrimary)
            .padding(.horizontal, GuesliTheme.spacing12)
            .padding(.vertical, 7)
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
