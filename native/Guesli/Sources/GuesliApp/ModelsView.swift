import FluidAudio
import SwiftUI
import GuesliCore

struct ModelsView: View {
    let appState: AppState
    let controller: GuesliController

    @State private var nemotron35UpdateAvailable = false
    @State private var downloadingModels: Set<String> = []
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadSnapshots: [String: ModelDownloadProgress] = [:]
    @State private var downloadMessages: [String: String] = [:]
    @State private var downloadGenerations: [String: UUID] = [:]
    @State private var downloadedModels: Set<String> = []
    @State private var downloadTasks: [String: Task<Void, Never>] = [:]
    @State private var modelToDelete: BackendOption?
    @State private var isLiveCaptionModelDownloaded = false
    @State private var isDownloadingLiveCaptionModel = false
    @State private var liveCaptionDownloadProgress = 0.0
    @State private var liveCaptionDownloadTask: Task<Void, Never>?
    @State private var showDeleteLiveCaptionModelConfirmation = false

    // Post-processor state
    @State private var downloadingPostProcModels: Set<String> = []
    @State private var downloadProgressPostProc: [String: Double] = [:]
    @State private var downloadedPostProcModels: Set<String> = []
    @State private var downloadTasksPostProc: [String: Task<Void, Never>] = [:]
    @State private var postProcModelToDelete: PostProcessorOption?
    @State private var isEditingSystemPrompt: Bool = false
    @State private var editedSystemPrompt: String

    init(appState: AppState, controller: GuesliController) {
        self.appState = appState
        self.controller = controller

        _editedSystemPrompt = State(initialValue: appState.config.postProcessorSystemPrompt)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuesliTheme.spacing24) {
                Text("Models")
                    .font(GuesliTheme.title1())
                    .foregroundStyle(GuesliTheme.textPrimary)

                Text("Download and manage transcription models. The active model is used for dictation.")
                    .font(GuesliTheme.body())
                    .foregroundStyle(GuesliTheme.textSecondary)

                modelCard(option: .gigaAMV3Russian)
                modelCard(option: .parakeetMultilingual, logo: "nvidia-logo")
                modelCard(option: .nemotron35Multilingual, logo: "nvidia-logo")

                liveCaptionModelCard

                postProcessorSection

                if !BackendOption.comingSoon.isEmpty {
                    VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
                        Text("COMING SOON")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GuesliTheme.textTertiary)
                            .textCase(.uppercase)
                            .padding(.leading, 2)
                            .padding(.top, GuesliTheme.spacing8)

                        VStack(spacing: GuesliTheme.spacing12) {
                            ForEach(BackendOption.comingSoon, id: \.model) { option in
                                comingSoonCard(option: option)
                            }
                        }
                    }
                }
            }
            .padding(GuesliTheme.spacing32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GuesliTheme.backgroundBase)
        .onAppear {
            checkDownloadedModels()
            isLiveCaptionModelDownloaded = MeetingParakeetLiveCaptionModelStore.isDownloaded()
            checkDownloadedPostProcModels()
            checkNemotron35Update()
        }
        .alert(
            "Delete \"\(modelToDelete?.label ?? "")\"?",
            isPresented: Binding(
                get: { modelToDelete != nil },
                set: { if !$0 { modelToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                modelToDelete = nil
            }
            Button("Delete", role: .destructive) {
                guard let option = modelToDelete else { return }
                deleteModel(option)
                modelToDelete = nil
            }
        } message: {
            Text("The downloaded model files will be removed from this Mac. You can download the model again later.")
        }
        .alert(
            "Delete \"\(postProcModelToDelete?.label ?? "")\"?",
            isPresented: Binding(
                get: { postProcModelToDelete != nil },
                set: { if !$0 { postProcModelToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                postProcModelToDelete = nil
            }
            Button("Delete", role: .destructive) {
                guard let option = postProcModelToDelete else { return }
                deletePostProcModel(option)
                postProcModelToDelete = nil
            }
        } message: {
            Text("The downloaded model files will be removed from this Mac. You can download the model again later.")
        }
        .alert(
            "Delete \"\(MeetingParakeetLiveCaptionModelStore.label)\"?",
            isPresented: $showDeleteLiveCaptionModelConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteLiveCaptionModel()
            }
        } message: {
            Text("The optional live-caption model will be removed. Final meeting transcription is unaffected.")
        }
    }

    private var liveCaptionModelCard: some View {
        let isActive = isLiveCaptionModelDownloaded && appState.config.enableLiveStreamingPartials

        return VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
            HStack(alignment: .top, spacing: GuesliTheme.spacing12) {
                brandLogo("nvidia-logo")

                VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                    HStack(spacing: GuesliTheme.spacing8) {
                        Text(MeetingParakeetLiveCaptionModelStore.label)
                            .font(GuesliTheme.headline())
                            .foregroundStyle(GuesliTheme.textPrimary)

                        Text(MeetingParakeetLiveCaptionModelStore.sizeLabel)
                            .font(GuesliTheme.caption())
                            .foregroundStyle(GuesliTheme.textTertiary)
                    }

                    Text("Optional low-latency preview for English meetings only. Final transcript still uses the selected meeting model. Never downloaded or enabled automatically.")
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textSecondary)
                }

                Spacer()

                Text(isActive ? "Active" : (isLiveCaptionModelDownloaded ? "Ready" : "Not downloaded"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isActive ? GuesliTheme.success : GuesliTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isActive ? GuesliTheme.success.opacity(0.15) : GuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if isDownloadingLiveCaptionModel {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: liveCaptionDownloadProgress)
                        .tint(GuesliTheme.accent)
                    Text("\(Int(liveCaptionDownloadProgress * 100))% downloading...")
                        .font(.system(size: 11))
                        .foregroundStyle(GuesliTheme.textTertiary)
                }
            }

            HStack(spacing: GuesliTheme.spacing8) {
                if isDownloadingLiveCaptionModel {
                    Button("Cancel") {
                        cancelLiveCaptionDownload()
                    }
                } else if isLiveCaptionModelDownloaded {
                    Button(isActive ? "Disable" : "Enable") {
                        controller.updateConfig { $0.enableLiveStreamingPartials = !isActive }
                    }

                    Button {
                        showDeleteLiveCaptionModelConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    .help("Delete live-caption model")
                } else {
                    Button("Download") {
                        startLiveCaptionModelDownload()
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(GuesliTheme.accent)
        }
        .padding(GuesliTheme.spacing16)
        .background(GuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium)
                .strokeBorder(isActive ? GuesliTheme.accent.opacity(0.6) : GuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func startLiveCaptionModelDownload() {
        guard !isDownloadingLiveCaptionModel else { return }
        isDownloadingLiveCaptionModel = true
        liveCaptionDownloadProgress = 0
        liveCaptionDownloadTask = Task {
            do {
                try await MeetingParakeetLiveCaptionModelStore.download { progress in
                    Task { @MainActor in
                        liveCaptionDownloadProgress = progress
                    }
                }
                guard !Task.isCancelled else { throw CancellationError() }
                isLiveCaptionModelDownloaded = true
            } catch is CancellationError {
                // User cancelled the explicit download.
            } catch {
                DiagnosticsLog.write("[guesli-native] live-caption model download failed: \(error.localizedDescription)")
            }
            isDownloadingLiveCaptionModel = false
            liveCaptionDownloadProgress = 0
            liveCaptionDownloadTask = nil
        }
    }

    private func cancelLiveCaptionDownload() {
        liveCaptionDownloadTask?.cancel()
        Task {
            let plan = ManagedASRModelPlans.parakeetRealtimeEOU320()
            await ManagedASRModelDownloader.cancelAndWait(modelID: plan.modelID)
        }
    }

    private func deleteLiveCaptionModel() {
        liveCaptionDownloadTask?.cancel()
        Task {
            let plan = ManagedASRModelPlans.parakeetRealtimeEOU320()
            let deletionToken = await ManagedASRModelDownloader.beginDeletion(modelID: plan.modelID)
            do {
                try MeetingParakeetLiveCaptionModelStore.delete()
                await ManagedASRModelDownloader.endDeletion(deletionToken)
                await MainActor.run {
                    isLiveCaptionModelDownloaded = false
                    controller.updateConfig { $0.enableLiveStreamingPartials = false }
                }
            } catch {
                await ManagedASRModelDownloader.endDeletion(deletionToken)
                DiagnosticsLog.write("[guesli-native] live-caption model delete failed: \(error.localizedDescription)")
            }
        }
    }

    private var nemotron35LanguageSelection: Binding<Nemotron35Language> {
        Binding(
            get: { appState.config.resolvedNemotron35Language },
            set: { language in
                Task { await controller.setNemotron35Language(language) }
            }
        )
    }

    private var parakeetLanguageSelection: Binding<ParakeetLanguage> {
        Binding(
            get: { appState.config.resolvedParakeetLanguage },
            set: { language in
                Task { await controller.setParakeetLanguage(language) }
            }
        )
    }

    private var postProcessorSection: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
            VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                Text("POST-PROCESSING")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GuesliTheme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.leading, 2)

                Text("Optional LLM cleanup layer applied after transcription. Removes filler words, formats spoken lists, and corrects common dictation errors.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.textSecondary)
                    .padding(.leading, 2)
            }
            .padding(.top, GuesliTheme.spacing8)

            VStack(spacing: GuesliTheme.spacing12) {
                ForEach(PostProcessorOption.all) { option in
                    postProcModelCard(option)
                }
            }

            systemPromptCard
        }
    }

    private func postProcModelCard(_ option: PostProcessorOption) -> some View {
        let isDownloaded = downloadedPostProcModels.contains(option.id)
        let isActive = appState.activePostProcessor.id == option.id && isDownloaded
        let isDownloading = downloadingPostProcModels.contains(option.id)
        let progress = downloadProgressPostProc[option.id] ?? 0

        return VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
            HStack(alignment: .top, spacing: GuesliTheme.spacing12) {
                brandLogo("qwen-logo")
                VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                    HStack(spacing: GuesliTheme.spacing8) {
                        Text(option.label)
                            .font(GuesliTheme.headline())
                            .foregroundStyle(GuesliTheme.textPrimary)

                        Text(option.sizeLabel)
                            .font(GuesliTheme.caption())
                            .foregroundStyle(GuesliTheme.textTertiary)
                    }

                    Text(option.description)
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textSecondary)
                }

                Spacer()

                if isActive {
                    Text("Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GuesliTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(GuesliTheme.success.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if isDownloaded {
                    Text("Downloaded")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(GuesliTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(GuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .tint(GuesliTheme.accent)
                    Text("\(Int(progress * 100))% downloading...")
                        .font(.system(size: 11))
                        .foregroundStyle(GuesliTheme.textTertiary)
                }
            }

            HStack(spacing: GuesliTheme.spacing8) {
                if isDownloading {
                    Button("Cancel") {
                        cancelPostProcDownload(option)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.textSecondary)
                    .padding(.horizontal, GuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(GuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                } else if isDownloaded {
                    if !isActive {
                        Button("Set Active") {
                            controller.selectPostProcessor(option)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(GuesliTheme.accent)
                        .padding(.horizontal, GuesliTheme.spacing12)
                        .padding(.vertical, 4)
                        .background(GuesliTheme.accentSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                    }

                    Button {
                        postProcModelToDelete = option
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.6))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Download") {
                        startPostProcDownload(option)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.accent)
                    .padding(.horizontal, GuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(GuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                }
            }
        }
        .padding(GuesliTheme.spacing16)
        .background(GuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium)
                .strokeBorder(isActive ? GuesliTheme.accent.opacity(0.5) : GuesliTheme.surfaceBorder, lineWidth: isActive ? 1.5 : 1)
        )
    }

    private var systemPromptCard: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
            HStack {
                VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                    Text("System Prompt")
                        .font(GuesliTheme.headline())
                        .foregroundStyle(GuesliTheme.textPrimary)
                    Text("Controls how the model cleans up transcriptions. Applies to the active post-processor model.")
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textSecondary)
                }
                Spacer()
                if !isEditingSystemPrompt {
                    Button("Edit") {
                        editedSystemPrompt = appState.config.postProcessorSystemPrompt
                        isEditingSystemPrompt = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.accent)
                    .padding(.horizontal, GuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(GuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                }
            }

            if isEditingSystemPrompt {
                TextEditor(text: $editedSystemPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(GuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                            .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
                    )

                HStack(spacing: GuesliTheme.spacing8) {
                    Button("Save") {
                        controller.updatePostProcessorSystemPrompt(editedSystemPrompt)
                        isEditingSystemPrompt = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.accent)
                    .padding(.horizontal, GuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(GuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))

                    Button("Cancel") {
                        isEditingSystemPrompt = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.textSecondary)
                    .padding(.horizontal, GuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(GuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))

                    Button("Reset to Default") {
                        editedSystemPrompt = PostProcessorOption.defaultSystemPrompt
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.textTertiary)
                    .padding(.horizontal, GuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(GuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                }
            } else {
                Text(appState.config.postProcessorSystemPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(GuesliTheme.textSecondary)
                    .lineLimit(6)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            }
        }
        .padding(GuesliTheme.spacing16)
        .background(GuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium)
                .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func brandLogo(_ name: String?) -> some View {
        if let name,
           let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func actionButtons(for option: BackendOption, isActive: Bool, isDownloaded: Bool, isDownloading: Bool) -> some View {
        HStack(spacing: GuesliTheme.spacing8) {
            if isDownloading {
                Button("Cancel") {
                    cancelDownload(option)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GuesliTheme.textSecondary)
                .padding(.horizontal, GuesliTheme.spacing12)
                .padding(.vertical, 4)
                .background(GuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            } else if isDownloaded {
                if !isActive {
                    Button("Set Active") {
                        controller.selectBackend(option)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.accent)
                    .padding(.horizontal, GuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(GuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                }

                Button {
                    modelToDelete = option
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.6))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            } else {
                Button("Download") {
                    startDownload(option)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GuesliTheme.accent)
                .padding(.horizontal, GuesliTheme.spacing12)
                .padding(.vertical, 4)
                .background(GuesliTheme.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            }
        }
    }

    private func modelCard(option: BackendOption, logo: String? = nil) -> some View {
        let isActive = appState.selectedBackend == option
        let isDownloaded = downloadedModels.contains(option.model)
        let isDownloading = downloadingModels.contains(option.model)
        let progress = downloadProgress[option.model] ?? 0

        return VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
            HStack(alignment: .top, spacing: GuesliTheme.spacing12) {
                brandLogo(logo)
                VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                    HStack(spacing: GuesliTheme.spacing8) {
                        Text(option.label)
                            .font(GuesliTheme.headline())
                            .foregroundStyle(GuesliTheme.textPrimary)

                        if option.recommended {
                            Text("Recommended")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(GuesliTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Text(option.sizeLabel)
                            .font(GuesliTheme.caption())
                            .foregroundStyle(GuesliTheme.textTertiary)
                    }

                    Text(option.description)
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textSecondary)
                }

                Spacer()

                // Status badge
                if isActive {
                    Text("Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GuesliTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(GuesliTheme.success.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if isDownloaded {
                    Text("Downloaded")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(GuesliTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(GuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if option.backend == BackendOption.nemotron35Multilingual.backend {
                HStack(alignment: .center, spacing: GuesliTheme.spacing12) {
                    Text("Language")
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textTertiary)
                        .frame(width: 64, alignment: .leading)

                    Picker("", selection: nemotron35LanguageSelection) {
                        ForEach(Nemotron35Language.allCases, id: \.self) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .leading)
                }

                if isDownloaded && nemotron35UpdateAvailable && !isDownloading {
                    HStack(spacing: GuesliTheme.spacing8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(GuesliTheme.accent)
                        Text("A newer model build is available.")
                            .font(GuesliTheme.caption())
                            .foregroundStyle(GuesliTheme.textSecondary)
                        Button("Update") { updateNemotron35(option) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(GuesliTheme.accent)
                    }
                }
            }

            if option.backend == BackendOption.parakeetMultilingual.backend {
                HStack(alignment: .center, spacing: GuesliTheme.spacing12) {
                    Text("Language")
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textTertiary)
                        .frame(width: 64, alignment: .leading)

                    Picker("", selection: parakeetLanguageSelection) {
                        ForEach(ParakeetLanguage.allCases, id: \.self) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .leading)
                }

                Text("Optional script filter for Parakeet v3; Auto-detect leaves decoding unfiltered.")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textTertiary)
            }

            // Progress bar when downloading
            if isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .tint(GuesliTheme.accent)
                    Text(downloadStatusText(for: option, progress: progress))
                        .font(.system(size: 11))
                        .foregroundStyle(GuesliTheme.textTertiary)
                }
            } else if let message = downloadMessages[option.model] {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(GuesliTheme.textTertiary)
            }

            actionButtons(for: option, isActive: isActive, isDownloaded: isDownloaded, isDownloading: isDownloading)
        }
        .padding(GuesliTheme.spacing16)
        .background(GuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium)
                .strokeBorder(isActive ? GuesliTheme.accent.opacity(0.5) : GuesliTheme.surfaceBorder, lineWidth: isActive ? 1.5 : 1)
        )
    }

    private func comingSoonCard(option: BackendOption) -> some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                    HStack(spacing: GuesliTheme.spacing8) {
                        Text(option.label)
                            .font(GuesliTheme.headline())
                            .foregroundStyle(GuesliTheme.textTertiary)

                        Text("Experimental")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(GuesliTheme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(GuesliTheme.surfacePrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text(option.sizeLabel)
                            .font(GuesliTheme.caption())
                            .foregroundStyle(GuesliTheme.textTertiary.opacity(0.6))
                    }

                    Text(option.description)
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textTertiary.opacity(0.7))
                }
                Spacer()
            }
        }
        .padding(GuesliTheme.spacing16)
        .background(GuesliTheme.backgroundRaised.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium)
                .strokeBorder(GuesliTheme.surfaceBorder.opacity(0.5), lineWidth: 1)
        )
        .opacity(0.6)
    }

    // MARK: - Post-Processor Actions

    private func startPostProcDownload(_ option: PostProcessorOption) {
        withAnimation { _ = downloadingPostProcModels.insert(option.id) }
        downloadProgressPostProc[option.id] = 0.02

        let task = Task {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: option.cacheDirectory, withIntermediateDirectories: true)

                try await downloadPostProcModel(option)

                await MainActor.run {
                    withAnimation {
                        downloadingPostProcModels.remove(option.id)
                        downloadedPostProcModels.insert(option.id)
                        downloadProgressPostProc.removeValue(forKey: option.id)
                        downloadTasksPostProc.removeValue(forKey: option.id)
                    }
                    if appState.config.enablePostProcessor && !appState.activePostProcessor.isDownloaded {
                        controller.selectPostProcessor(option)
                        controller.preloadExperimentalTranscriptionFeatures()
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        downloadingPostProcModels.remove(option.id)
                        downloadProgressPostProc.removeValue(forKey: option.id)
                        downloadTasksPostProc.removeValue(forKey: option.id)
                    }
                }
                let isCancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                if !isCancelled {
                    DiagnosticsLog.write("[guesli-native] Post-processor download failed: \(error.localizedDescription)")
                }
            }
        }
        downloadTasksPostProc[option.id] = task
    }

    private func downloadPostProcModel(_ option: PostProcessorOption, maxRetries: Int = 3) async throws {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            try Task.checkCancellation()
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
                fputs("[download] retry \(attempt)/\(maxRetries) for \(option.filename)\n", stderr)
                await MainActor.run {
                    downloadProgressPostProc[option.id] = 0.02
                }
            }
            do {
                let tmpURL = try await downloadPostProcTempFile(option)
                try installPostProcModel(from: tmpURL, option: option)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        let underlying = lastError ?? NSError(domain: "PostProcDownload", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "No download attempts were made",
        ])
        throw DownloadError.retriesExhausted(option.filename, underlying)
    }

    private func downloadPostProcTempFile(_ option: PostProcessorOption) async throws -> URL {
        let delegate = PostProcDownloadDelegate { progress in
            DispatchQueue.main.async {
                downloadProgressPostProc[option.id] = max(progress, 0.02)
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let invalidator = URLSessionInvalidator()
        do {
            let downloadedURL = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    delegate.setContinuation(continuation)
                    session.downloadTask(with: option.downloadURL).resume()
                }
            } onCancel: {
                invalidator.cancel(session)
            }
            invalidator.finish(session)
            return downloadedURL
        } catch {
            if error is CancellationError {
                invalidator.cancel(session)
            } else {
                invalidator.finish(session)
            }
            throw error
        }
    }

    private func installPostProcModel(from tmpURL: URL, option: PostProcessorOption) throws {
        let fm = FileManager.default
        let stagingURL = option.cacheDirectory.appendingPathComponent(".\(option.filename).download")
        defer {
            try? fm.removeItem(at: tmpURL)
            try? fm.removeItem(at: stagingURL)
        }
        try? fm.removeItem(at: stagingURL)
        try fm.moveItem(at: tmpURL, to: stagingURL)
        if fm.fileExists(atPath: option.modelURL.path) {
            _ = try fm.replaceItemAt(
                option.modelURL,
                withItemAt: stagingURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fm.moveItem(at: stagingURL, to: option.modelURL)
        }
    }

    private func cancelPostProcDownload(_ option: PostProcessorOption) {
        downloadTasksPostProc[option.id]?.cancel()
        withAnimation {
            downloadingPostProcModels.remove(option.id)
            downloadProgressPostProc.removeValue(forKey: option.id)
            downloadTasksPostProc.removeValue(forKey: option.id)
        }
    }

    private func deletePostProcModel(_ option: PostProcessorOption) {
        if appState.activePostProcessor.id == option.id {
            let remainingDownloadedIDs = downloadedPostProcModels.subtracting([option.id])
            if let fallback = PostProcessorOption.firstDownloaded(excluding: option.id, downloadedIDs: remainingDownloadedIDs) {
                controller.selectPostProcessor(fallback)
            } else {
                controller.setPostProcessorEnabled(false)
            }
        }
        try? FileManager.default.removeItem(at: option.cacheDirectory)
        downloadedPostProcModels.remove(option.id)
    }

    private func checkDownloadedPostProcModels() {
        downloadedPostProcModels.removeAll()
        for option in PostProcessorOption.all {
            if option.isDownloaded {
                downloadedPostProcModels.insert(option.id)
            }
        }
    }

    // MARK: - Actions

    private func startDownload(_ option: BackendOption) {
        let generation = UUID()
        downloadGenerations[option.model] = generation
        downloadMessages.removeValue(forKey: option.model)
        downloadSnapshots.removeValue(forKey: option.model)
        withAnimation { _ = downloadingModels.insert(option.model) }
        downloadProgress[option.model] = 0.05  // Show initial progress immediately

        let startTime = Date()
        let task = Task {
            do {
                try await controller.transcriptionCoordinator.preloadRequired(
                    backend: option,
                    includeMeetingHelpers: controller.config.resolvedOnboardingUseCase.includesMeetings
                ) { progress, _ in
                    DispatchQueue.main.async {
                        guard downloadGenerations[option.model] == generation else { return }
                        downloadProgress[option.model] = max(progress, 0.05)
                    }
                } progressSnapshot: { snapshot in
                    DispatchQueue.main.async {
                        guard downloadGenerations[option.model] == generation else { return }
                        downloadSnapshots[option.model] = snapshot
                        if let fraction = snapshot.fractionCompleted {
                            downloadProgress[option.model] = max(fraction, 0.05)
                        }
                        downloadMessages[option.model] = snapshot.message
                    }
                }
                guard isModelDownloaded(option, fm: FileManager.default) else {
                    throw NSError(
                        domain: "GuesliModelDownload",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "\(option.label) was not downloaded successfully."]
                    )
                }
                guard !Task.isCancelled else {
                    await MainActor.run {
                        withAnimation {
                            downloadingModels.remove(option.model)
                            downloadProgress.removeValue(forKey: option.model)
                            downloadTasks.removeValue(forKey: option.model)
                        }
                    }
                    return
                }
                // Ensure the downloading state is visible for at least 1.5s
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed < 1.5 {
                    try? await Task.sleep(nanoseconds: UInt64((1.5 - elapsed) * 1_000_000_000))
                }
                await MainActor.run {
                    guard downloadGenerations[option.model] == generation else { return }
                    withAnimation {
                        downloadingModels.remove(option.model)
                        downloadedModels.insert(option.model)
                        downloadProgress.removeValue(forKey: option.model)
                        downloadTasks.removeValue(forKey: option.model)
                        downloadSnapshots.removeValue(forKey: option.model)
                        downloadMessages.removeValue(forKey: option.model)
                    }
                }
            } catch {
                await MainActor.run {
                    guard downloadGenerations[option.model] == generation else { return }
                    withAnimation {
                        downloadingModels.remove(option.model)
                        downloadProgress.removeValue(forKey: option.model)
                        downloadTasks.removeValue(forKey: option.model)
                    }
                    let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                    downloadMessages[option.model] = cancelled
                        ? "Paused — resume is available"
                        : "Download failed — retry"
                }
                if !(error is CancellationError) {
                    DiagnosticsLog.write("[guesli-native] model download failed for \(option.backend)/\(option.model): \(error.localizedDescription)")
                }
            }
        }
        downloadTasks[option.model] = task
    }

    private func cancelDownload(_ option: BackendOption) {
        let generation = downloadGenerations[option.model]
        downloadTasks[option.model]?.cancel()
        Task {
            if let plan = managedPlan(for: option) {
                await ManagedASRModelDownloader.cancelAndWait(modelID: plan.modelID)
            }
            await MainActor.run {
                guard downloadGenerations[option.model] == generation else { return }
                withAnimation {
                    downloadingModels.remove(option.model)
                    downloadProgress.removeValue(forKey: option.model)
                    downloadTasks.removeValue(forKey: option.model)
                }
                downloadMessages[option.model] = "Paused — resume is available"
            }
        }
    }

    /// Re-download Nemotron 3.5 to pick up a newer upstream build: delete the cached
    /// files (so the download isn't skipped), then start a fresh download.
    private func updateNemotron35(_ option: BackendOption) {
        Task {
            do {
                await controller.transcriptionCoordinator.unloadNemotron35Transcriber()
                try await deleteModelFiles(option)
                await MainActor.run {
                    downloadedModels.remove(option.model)
                    nemotron35UpdateAvailable = false
                    startDownload(option)
                }
            } catch {
                DiagnosticsLog.write("[guesli-native] model update cleanup failed for \(option.backend)/\(option.model): \(error.localizedDescription)")
            }
        }
    }

    private func deleteModel(_ option: BackendOption) {
        let fallback = downloadedModels
            .compactMap { model in BackendOption.all.first(where: { $0.model == model && $0 != option }) }
            .first ?? .parakeetMultilingual
        if appState.selectedBackend == option {
            controller.selectBackend(fallback)
        }
        if appState.selectedMeetingTranscriptionBackend == option {
            if let meetingFallback = BackendOption.all.first(where: {
                $0 != option && $0.supportsMeetingTranscription && downloadedModels.contains($0.model)
            }) {
                controller.selectMeetingTranscriptionBackend(meetingFallback)
            }
        }
        // Remove cached model files
        Task {
            do {
                try await deleteModelFiles(option)
                await MainActor.run {
                    _ = downloadedModels.remove(option.model)
                }
            } catch {
                DiagnosticsLog.write("[guesli-native] model delete failed for \(option.backend)/\(option.model): \(error.localizedDescription)")
            }
        }
    }

    private func deleteModelFiles(_ option: BackendOption) async throws {
        let fm = FileManager.default
        downloadTasks[option.model]?.cancel()
        if let plan = managedPlan(for: option) {
            let deletionToken = await ManagedASRModelDownloader.beginDeletion(modelID: plan.modelID)
            do {
                await unloadModel(option)
                try plan.delete(fileManager: fm)
                await ManagedASRModelDownloader.endDeletion(deletionToken)
                return
            } catch {
                await ManagedASRModelDownloader.endDeletion(deletionToken)
                throw error
            }
        }
        switch option.backend {
        case "nemotron35":
            let path = fm.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/guesli/models/nemotron35-multilingual-2240ms")
            try removeItemIfPresent(at: path, fileManager: fm)
        case "gigaam_v3":
            try ONNXGigaAMModelStore.deleteModelFiles(fileManager: fm)
        default:
            break
        }
    }

    private func managedPlan(for option: BackendOption) -> ManagedASRModelPlan? {
        switch option.backend {
        case "fluidaudio": return ManagedASRModelPlans.parakeetV3()
        default: return nil
        }
    }

    private func unloadModel(_ option: BackendOption) async {
        switch option.backend {
        case "fluidaudio": await controller.transcriptionCoordinator.unloadFluidAudioTranscriber()
        default: break
        }
    }

    private func downloadStatusText(for option: BackendOption, progress: Double) -> String {
        if let snapshot = downloadSnapshots[option.model] {
            if let message = snapshot.message, !message.isEmpty { return message }
            switch snapshot.phase {
            case .preparing: return "Preparing model..."
            case .ready: return "Model ready"
            case .paused: return "Paused — resume is available"
            case .failed: return "Download failed — retry"
            case .downloading: break
            }
        }
        return downloadMessages[option.model] ?? "\(Int(progress * 100))% downloading..."
    }

    private func removeItemIfPresent(at url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    // MARK: - Check Downloaded Status

    private func checkDownloadedModels() {
        let fm = FileManager.default
        for option in BackendOption.all {
            if isModelDownloaded(option, fm: fm) {
                downloadedModels.insert(option.model)
            }
        }
    }

    /// Background check: does FluidInference's repo have a newer commit than what's
    /// installed for Nemotron 3.5? Never auto-downloads — just surfaces a badge.
    private func checkNemotron35Update() {
        guard #available(macOS 15, *),
              isModelDownloaded(.nemotron35Multilingual, fm: FileManager.default) else { return }
        Task {
            let available = await Nemotron35StreamingTranscriber.updateAvailable()
            await MainActor.run { nemotron35UpdateAvailable = available }
        }
    }

    private func isModelDownloaded(_ option: BackendOption, fm: FileManager) -> Bool {
        switch option.backend {
        case "nemotron35":
            let path = fm.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/guesli/models/nemotron35-multilingual-2240ms/encoder.mlmodelc/coremldata.bin")
            return fm.fileExists(atPath: path.path)
        case "fluidaudio":
            return ManagedASRModelPlans.parakeetV3().isAvailableLocally(fileManager: fm)
        case "gigaam_v3":
            return ONNXGigaAMModelStore.isAvailableLocally()
        default:
            return false
        }
    }
}

private final class URLSessionInvalidator: @unchecked Sendable {
    private let lock = NSLock()
    private var didInvalidate = false

    func finish(_ session: URLSession) {
        invalidate(session, action: { $0.finishTasksAndInvalidate() })
    }

    func cancel(_ session: URLSession) {
        invalidate(session, action: { $0.invalidateAndCancel() })
    }

    private func invalidate(_ session: URLSession, action: (URLSession) -> Void) {
        lock.lock()
        guard !didInvalidate else {
            lock.unlock()
            return
        }
        didInvalidate = true
        lock.unlock()
        action(session)
    }
}

/// URLSessionDownloadDelegate bridge for post-processor GGUF downloads.
/// Uses OS-level buffered download task instead of byte-by-byte async iteration.
private final class PostProcDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func setContinuation(_ c: CheckedContinuation<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        continuation = c
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        var dest: URL?
        do {
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                throw NSError(domain: "PostProcDownload", code: response.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Post-processor download failed with HTTP \(response.statusCode)",
                ])
            }

            // URLSession deletes the temp file after this returns — move it first.
            let movedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".gguf.tmp")
            try FileManager.default.moveItem(at: location, to: movedURL)
            dest = movedURL
            try validateGGUFHeader(at: movedURL)
            resumeOnce(.success(movedURL))
        } catch {
            if let dest { try? FileManager.default.removeItem(at: dest) }
            resumeOnce(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        resumeOnce(.failure(error))
    }

    private func resumeOnce(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        switch result {
        case .success(let url):
            continuation?.resume(returning: url)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func validateGGUFHeader(at url: URL) throws {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        let header = try fh.read(upToCount: 4) ?? Data()
        guard header == Data([0x47, 0x47, 0x55, 0x46]) else {
            throw NSError(domain: "PostProcDownload", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Downloaded post-processor file is not a GGUF model",
            ])
        }
    }
}
