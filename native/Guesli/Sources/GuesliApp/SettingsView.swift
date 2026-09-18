import AppKit
import AVFoundation
import SwiftUI
import GuesliCore

private struct MeetingDetectionAppOption: Identifiable {
    let bundleID: String
    let name: String
    let icon: String

    var id: String { bundleID }
}

private struct MeetingBrowserOpenOption: Identifiable {
    let bundleID: String
    let name: String

    var id: String { bundleID.isEmpty ? "__system_default__" : bundleID }
}

private struct DictationMicrophoneOption: Identifiable {
    let uid: String?
    let label: String

    var id: String { uid ?? "__automatic__" }
}

enum SettingsPermissionRefreshReason {
    case initialDisplay, periodicPoll, permissionRequested, settingsSelected, appActivated

    var refreshesLaunchAtLogin: Bool { self == .appActivated }
    var refreshesSystemAudio: Bool {
        switch self {
        case .initialDisplay, .settingsSelected, .appActivated: true
        case .periodicPoll, .permissionRequested: false
        }
    }
}

struct SettingsView: View {
    private enum PendingDataDestruction {
        case dictations
        case meetings

        var title: String {
            switch self {
            case .dictations:
                return "Clear dictation history?"
            case .meetings:
                return "Clear meeting history?"
            }
        }

        var message: String {
            switch self {
            case .dictations:
                return "This will permanently remove all saved dictations. This cannot be undone."
            case .meetings:
                return "This will permanently remove all saved meetings, notes, transcripts, and retained audio recordings. This cannot be undone."
            }
        }

        var confirmLabel: String {
            switch self {
            case .dictations:
                return "Clear Dictations"
            case .meetings:
                return "Clear Meetings"
            }
        }
    }

    private enum SettingsPane: String, CaseIterable, Identifiable {
        case general
        case sync
        case dictation
        case meetings
        case appearance

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .sync: return "Sync"
            case .dictation: return "Dictation"
            case .meetings: return "Meetings"
            case .appearance: return "Appearance"
            }
        }
    }

    let appState: AppState
    let controller: GuesliController

    @State private var chatGPTSignInError: String?
    @State private var isSigningInChatGPT = false
    @State private var googleCalSignInError: String?
    @State private var isSigningInGoogleCal = false
    @State private var pendingDataDestruction: PendingDataDestruction?
    @State private var isShowingDictionaryAccessibilityPrompt = false
    @State private var selectedPane: SettingsPane = .general
    @State private var downloadedBackendOptions: [BackendOption] = []
    @State private var downloadedPostProcOptions: [PostProcessorOption] = []
    @State private var dictationInputDevices: [AudioInputDeviceInfo] = []
    @State private var audioInputDeviceRefreshTask: Task<Void, Never>?
    @State private var permissionPollTimer: Timer?
    @State private var isCleanupPromptManagerPresented = false
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false
    @State private var screenRecordingGranted = false
    @AppStorage("settings.pendingScreenContextEnable") private var pendingScreenContextEnable = false
    @AppStorage("settings.pendingScreenContextRequestedAt") private var pendingScreenContextRequestedAt = 0.0
    @State private var systemAudioGranted = false
    @State private var isCheckingSystemAudioPermission = false
    @State private var openRouterFreeModels: [SummaryModelPreset] = []
    @State private var isLoadingOpenRouterFreeModels = false
    @State private var openRouterFreeModelsError: String?

    // Uniform width for all right-side controls
    private let controlWidth: CGFloat = 220
    private let meetingControlWidth: CGFloat = 275
    private let screenContextGrantIntentTimeout: TimeInterval = 15 * 60
    private var selectedTranscriptCleanupProvider: TranscriptCleanupProviderOption {
        TranscriptCleanupProviderOption.resolved(appState.config.transcriptCleanupProvider)
    }
    private var cleanupPromptPresets: [TranscriptCleanupPromptPreset] {
        TranscriptCleanupPrompts.presets(custom: appState.config.customTranscriptCleanupPrompts)
    }
    private var selectedCleanupPromptName: String {
        appState.config.resolvedTranscriptCleanupPrompt.name
    }
    private var transcriptCleanupCredentialStatus: TranscriptCleanupCredentialStatus? {
        TranscriptCleanupCredentialStatus.dictationCleanup(
            provider: selectedTranscriptCleanupProvider,
            config: appState.config,
            isChatGPTAuthenticated: appState.isChatGPTAuthenticated
        )
    }
    private var transcriptCleanupProviderDescription: String {
        switch selectedTranscriptCleanupProvider {
        case .local:
            return "Runs on the downloaded local cleanup model."
        case .chatGPT:
            return "Uses your ChatGPT subscription."
        case .openAI, .openRouter, .customLLM:
            return "External cleanup uses credentials and models from Meeting Summaries."
        }
    }
    private let meetingDetectionAppOptions: [MeetingDetectionAppOption] = [
        MeetingDetectionAppOption(bundleID: "com.google.Chrome", name: "Chrome", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "company.thebrowser.Browser", name: "Arc", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "com.apple.Safari", name: "Safari", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "com.microsoft.edgemac", name: "Edge", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "com.brave.Browser", name: "Brave", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", icon: "message.fill"),
        MeetingDetectionAppOption(bundleID: "us.zoom.xos", name: "Zoom", icon: "video.fill"),
        MeetingDetectionAppOption(bundleID: "com.microsoft.teams2", name: "Teams", icon: "person.2.fill"),
        MeetingDetectionAppOption(bundleID: "com.apple.FaceTime", name: "FaceTime", icon: "video.fill"),
        MeetingDetectionAppOption(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp", icon: "phone.fill"),
    ]
    private let allMeetingBrowserOpenOptions: [MeetingBrowserOpenOption] = [
        MeetingBrowserOpenOption(bundleID: "", name: "System Default"),
        MeetingBrowserOpenOption(bundleID: "com.brave.Browser", name: "Brave"),
        MeetingBrowserOpenOption(bundleID: "com.google.Chrome", name: "Chrome"),
        MeetingBrowserOpenOption(bundleID: "com.apple.Safari", name: "Safari"),
        MeetingBrowserOpenOption(bundleID: "com.microsoft.edgemac", name: "Edge"),
        MeetingBrowserOpenOption(bundleID: "company.thebrowser.Browser", name: "Arc"),
    ]

    private var dictationBackendOptions: [BackendOption] {
        backendOptions(including: appState.selectedBackend)
    }

    private var meetingBackendOptions: [BackendOption] {
        backendOptions(including: appState.selectedMeetingTranscriptionBackend)
    }

    private var selectedMeetingBackendLabel: String {
        if meetingBackendOptions.contains(appState.selectedMeetingTranscriptionBackend) {
            return appState.selectedMeetingTranscriptionBackend.label
        }
        return meetingBackendOptions.first?.label ?? "No downloaded models"
    }

    private var meetingBrowserOpenOptions: [MeetingBrowserOpenOption] {
        allMeetingBrowserOpenOptions.filter { option in
            option.bundleID.isEmpty || NSWorkspace.shared.urlForApplication(withBundleIdentifier: option.bundleID) != nil
        }
    }

    private var selectedMeetingBrowserLabel: String {
        let bundleID = appState.config.preferredMeetingBrowserBundleID
        return meetingBrowserOpenOptions.first { $0.bundleID == bundleID }?.name ?? "System Default"
    }

    private var selectedUpcomingMeetingsWindow: UpcomingMeetingsWindow {
        UpcomingMeetingsWindow.resolve(dayCount: appState.config.upcomingMeetingsDayCount)
    }

    private var dictationMicrophoneOptions: [DictationMicrophoneOption] {
        var options = [DictationMicrophoneOption(uid: nil, label: "Automatic")]
        options += dictationInputDevices.map { device in
            DictationMicrophoneOption(uid: device.uid, label: device.name)
        }
        if let selectedUID = appState.config.dictationInputDeviceUID,
           !options.contains(where: { $0.uid == selectedUID }) {
            options.append(DictationMicrophoneOption(uid: selectedUID, label: "Selected microphone unavailable"))
        }
        return options
    }

    private var selectedDictationMicrophoneLabel: String {
        let selectedUID = appState.config.dictationInputDeviceUID
        return dictationMicrophoneOptions.first(where: { $0.uid == selectedUID })?.label ?? "Automatic"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuesliTheme.spacing24) {
                Text("Settings")
                    .font(GuesliTheme.title1())
                    .foregroundStyle(GuesliTheme.textPrimary)

                settingsPanePicker
                paneContent
            }
            .padding(GuesliTheme.spacing32)
        }
        .background(GuesliTheme.backgroundBase)
        .onAppear {
            refreshDownloadedModelOptions()
            refreshDictationInputDevices()
            startPermissionPolling()
            if appState.selectedMeetingSummaryBackend == .openRouter {
                loadOpenRouterFreeModelsIfNeeded()
            }
        }
        .onDisappear {
            audioInputDeviceRefreshTask?.cancel()
            audioInputDeviceRefreshTask = nil
            stopPermissionPolling()
        }
        .onChange(of: appState.selectedTab) { _, tab in
            if tab == .settings {
                refreshDownloadedModelOptions()
                refreshDictationInputDevices()
                refreshPermissionStatuses(for: .settingsSelected)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard appState.selectedTab == .settings else { return }
            refreshPermissionStatuses(for: .appActivated)
        }
        .onChange(of: appState.selectedBackend) { _, _ in
            refreshDownloadedModelOptions()
        }
        .onChange(of: appState.selectedMeetingTranscriptionBackend) { _, _ in
            refreshDownloadedModelOptions()
        }
        .onChange(of: appState.selectedMeetingSummaryBackend) { _, backend in
            if backend == .openRouter {
                loadOpenRouterFreeModelsIfNeeded()
            }
        }
        .alert(
            pendingDataDestruction?.title ?? "Confirm Destructive Action",
            isPresented: Binding(
                get: { pendingDataDestruction != nil },
                set: { if !$0 { pendingDataDestruction = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingDataDestruction = nil
            }
            Button(pendingDataDestruction?.confirmLabel ?? "Delete", role: .destructive) {
                switch pendingDataDestruction {
                case .dictations:
                    controller.clearDictationHistory()
                case .meetings:
                    controller.clearMeetingHistory()
                case nil:
                    break
                }
                pendingDataDestruction = nil
            }
        } message: {
            Text(pendingDataDestruction?.message ?? "")
        }
        .alert(
            "Enable Accessibility?",
            isPresented: $isShowingDictionaryAccessibilityPrompt
        ) {
            Button("Cancel", role: .cancel) {
                controller.cancelDictionaryCorrectionAccessibilityEnableRequest()
            }
            Button("Enable") {
                controller.requestDictionaryCorrectionAccessibilityEnable()
            }
        } message: {
            Text("Dictionary suggestions briefly read focused app text via Accessibility after dictation. Grant access, then relaunch Guesli to turn suggestions on.")
        }
        .sheet(isPresented: $isCleanupPromptManagerPresented) {
            TranscriptCleanupPromptsManagerView(
                appState: appState,
                controller: controller,
                onClose: { isCleanupPromptManagerPresented = false }
            )
        }
    }

    private func refreshDownloadedModelOptions() {
        controller.refreshMeetingTranscriptionSelectionForAvailability()
        downloadedBackendOptions = BackendOption.downloadedPrimaryCatalog
        downloadedPostProcOptions = PostProcessorOption.downloaded
    }

    private func refreshDictationInputDevices() {
        dictationInputDevices = controller.cachedDictationInputDevices()
        audioInputDeviceRefreshTask?.cancel()
        audioInputDeviceRefreshTask = Task { @MainActor in
            let devices = await controller.refreshDictationInputDevices()
            guard !Task.isCancelled else { return }
            dictationInputDevices = devices
        }
    }

    private func backendOptions(including selection: BackendOption) -> [BackendOption] {
        var options = downloadedBackendOptions
        if !options.contains(where: { $0 == selection }) {
            options.insert(selection, at: 0)
        }
        return options
    }

    private static let accentPresets: [(hex: String, name: String)] = [
        ("2563eb", "Blue"),
        ("ef4444", "Red"),
        ("f59e0b", "Amber"),
        ("10b981", "Green"),
        ("8b5cf6", "Purple"),
        ("ec4899", "Pink"),
        ("1e1e2e", "Dark"),
    ]

    private var screenContextDescription: String {
        if !accessibilityGranted {
            return "Grant Accessibility, then toggle again if needed."
        }
        return "Adds nearby focused-app text to dictation cleanup through Accessibility. No screenshots."
    }

    @ViewBuilder
    private func screenContextRow(_ title: String, controlWidth rowControlWidth: CGFloat? = nil) -> some View {
        let width = rowControlWidth ?? controlWidth
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(GuesliTheme.body())
                    .foregroundStyle(GuesliTheme.textPrimary)
                Text(screenContextDescription)
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 20)

            ZStack(alignment: .trailing) {
                Color.clear.frame(width: width, height: 1)
                screenContextControl(width: width)
            }
        }
        .frame(minHeight: 52)
    }

    private let customIndicatorPositionLabel = "Custom (drag to reposition)"

    private var availableSettingsPanes: [SettingsPane] {
        SettingsPane.allCases.filter { pane in
            pane != .sync || appState.canUseICloudSync
        }
    }

    private var settingsPanePicker: some View {
        HStack {
            Spacer()
            Picker("", selection: $selectedPane) {
                ForEach(availableSettingsPanes) { pane in
                    Text(pane.title).tag(pane)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 760)
            Spacer()
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .general:
            generalSettingsPane
        case .sync:
            syncSettingsPane
        case .dictation:
            dictationSettingsPane
        case .meetings:
            meetingsSettingsPane
        case .appearance:
            appearanceSettingsPane
        }
    }

    private var generalSettingsPane: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing24) {
            settingsSection("General") {
                VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
                    settingsRow("Launch at login") {
                        settingsSwitch(isOn: appState.config.launchAtLogin) { newValue in
                            controller.setLaunchAtLogin(newValue)
                        }
                    }
                    if appState.launchAtLoginRegistrationState == .requiresApproval {
                        launchAtLoginApprovalPrompt
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Open dashboard on launch") {
                    settingsSwitch(isOn: appState.config.openDashboardOnLaunch) { newValue in
                        controller.updateConfig { $0.openDashboardOnLaunch = newValue }
                    }
                }
            }

            permissionsSection

            settingsSection("Data") {
                HStack(spacing: GuesliTheme.spacing12) {
                    actionButton("Clear dictation history", role: .destructive) {
                        pendingDataDestruction = .dictations
                    }
                    actionButton("Clear meeting history", role: .destructive) {
                        pendingDataDestruction = .meetings
                    }
                    .disabled(controller.isMeetingRecording())
                    .help("Stop the current meeting recording before clearing meeting history.")
                }
            }
        }
    }

    private var launchAtLoginApprovalPrompt: some View {
        HStack(spacing: GuesliTheme.spacing8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GuesliTheme.recording)
            Text("Requires approval in System Settings")
                .font(GuesliTheme.caption())
                .foregroundStyle(GuesliTheme.textTertiary)
            Spacer(minLength: GuesliTheme.spacing12)
            Button {
                controller.openLaunchAtLoginSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Open")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(GuesliTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(GuesliTheme.accentSubtle)
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            .help("Open Login Items in System Settings")
        }
        .padding(.leading, GuesliTheme.spacing16)
        .padding(.trailing, GuesliTheme.spacing16)
        .padding(.bottom, GuesliTheme.spacing8)
    }

    private var syncSettingsPane: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing24) {
            settingsSection("iCloud Text Sync") {
                settingsRow("Private iCloud sync") {
                    settingsSwitch(isOn: appState.config.iCloudSyncEnabled) { newValue in
                        controller.setICloudSyncEnabledFromSettings(newValue)
                    }
                }
                settingsDescription("Sync dictation text, meeting transcripts, notes, summaries, and manual notes through your private iCloud account. Audio recordings are never synced.")

                Divider().background(GuesliTheme.surfaceBorder)

                HStack(spacing: GuesliTheme.spacing12) {
                    VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                        Text(syncStatusText)
                            .font(GuesliTheme.body())
                            .foregroundStyle(GuesliTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let lastSyncedText = syncLastSyncedText {
                            Text("Last synced: \(lastSyncedText)")
                                .font(GuesliTheme.caption())
                                .foregroundStyle(GuesliTheme.textTertiary)
                        }
                        if let linkedDeviceText = syncLinkedDeviceText {
                            Text(linkedDeviceText)
                                .font(GuesliTheme.caption())
                                .foregroundStyle(GuesliTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: GuesliTheme.spacing16)
                    actionButton("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                        controller.performICloudSync()
                    }
                    .frame(width: controlWidth)
                    .disabled(!appState.config.iCloudSyncEnabled)
                }
            }

        }
    }

    private var syncStatusText: String {
        if !appState.config.iCloudSyncEnabled {
            return "Sync is off. Turn it on to keep text records in your private iCloud account."
        }
        return appState.iCloudSyncStatus ?? "Private iCloud text sync is ready."
    }

    private var syncLastSyncedText: String? {
        guard let date = appState.iCloudLastSyncedAt else { return nil }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    private var syncLinkedDeviceText: String? {
        guard appState.config.iCloudSyncEnabled else { return nil }
        if let remoteDeviceName = appState.iCloudBridgeCompanionDeviceName {
            if let platform = appState.iCloudBridgeRemoteDevicePlatform {
                return "Linked \(syncDeviceLabel(for: platform)): \(remoteDeviceName)"
            }
            return "Linked device: \(remoteDeviceName)"
        }
        return "No linked device yet."
    }

    private func syncDeviceLabel(for platform: String) -> String {
        switch platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ios":
            return "iPhone"
        case "ipados":
            return "iPad"
        default:
            return platform
        }
    }

    private var dictationSettingsPane: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing24) {
            settingsSection("Transcription") {
                settingsRow("Dictation model") {
                    settingsMenu(
                        selection: appState.selectedBackend.label,
                        options: dictationBackendOptions.map(\.label)
                    ) { label in
                        if let option = dictationBackendOptions.first(where: { $0.label == label }) {
                            controller.selectBackend(option)
                        }
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow(
                    "Microphone",
                    description: "Automatic uses system input, or Mac mic with AirPods."
                ) {
                    let options = dictationMicrophoneOptions
                    FixedWidthPopUp(
                        selection: selectedDictationMicrophoneLabel,
                        options: options.map(\.label),
                        onSelectIndex: { index in
                            guard index >= 0, index < options.count else { return }
                            controller.selectDictationInputDeviceUID(options[index].uid)
                            refreshDictationInputDevices()
                        }
                    )
                    .frame(height: 24)
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("AI transcript cleanup") {
                    settingsSwitch(isOn: appState.config.enablePostProcessor) { newValue in
                        controller.setPostProcessorEnabled(newValue)
                    }
                }
                if appState.config.enablePostProcessor {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow(
                        "Cleanup provider",
                        description: transcriptCleanupProviderDescription
                    ) {
                        let provider = selectedTranscriptCleanupProvider
                        settingsMenu(
                            selection: provider.label,
                            options: TranscriptCleanupProviderOption.allCases.map(\.label)
                        ) { label in
                            if let option = TranscriptCleanupProviderOption.allCases.first(where: { $0.label == label }) {
                                controller.setTranscriptCleanupProvider(option)
                            }
                        }
                    }
                }
                if appState.config.enablePostProcessor,
                   selectedTranscriptCleanupProvider == .chatGPT {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Cleanup model") {
                        settingsModelMenu(
                            currentModel: appState.config.chatGPTDictationCleanupModel,
                            presets: SummaryModelPreset.chatGPTTranscriptCleanupModels,
                            defaultModel: AppConfig.defaultChatGPTDictationCleanupModel
                        ) { val in controller.setChatGPTDictationCleanupModel(val) }
                    }
                }
                if appState.config.enablePostProcessor,
                   let status = transcriptCleanupCredentialStatus {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Cleanup credentials") {
                        transcriptCleanupStatusView(status)
                    }
                }
                if appState.config.enablePostProcessor,
                   selectedTranscriptCleanupProvider == .chatGPT {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Cleanup account") {
                        chatGPTAccountControl
                    }
                }
                if appState.config.enablePostProcessor,
                   let warning = appState.lastTranscriptCleanupWarning {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Last cleanup warning") {
                        transcriptCleanupWarningView(warning)
                    }
                }
                if appState.config.enablePostProcessor
                    && selectedTranscriptCleanupProvider == .local
                    && !downloadedPostProcOptions.isEmpty {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Cleanup model") {
                        let selection = downloadedPostProcOptions.contains(where: { $0.id == appState.activePostProcessor.id })
                            ? appState.activePostProcessor.label
                            : (downloadedPostProcOptions.first?.label ?? "")
                        settingsMenu(
                            selection: selection,
                            options: downloadedPostProcOptions.map(\.label)
                        ) { label in
                            if let option = downloadedPostProcOptions.first(where: { $0.label == label }) {
                                controller.selectPostProcessor(option)
                            }
                        }
                    }
                } else if appState.config.enablePostProcessor
                    && selectedTranscriptCleanupProvider == .local {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Cleanup model") {
                        Text("Download a cleanup model in Models")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(GuesliTheme.textTertiary)
                            .multilineTextAlignment(.trailing)
                            .frame(width: controlWidth, alignment: .trailing)
                    }
                }
                if appState.config.enablePostProcessor {
                    Divider().background(GuesliTheme.surfaceBorder)
                    cleanupPromptSettings
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow(
                    "Dictionary suggestions",
                    description: "Suggest words after corrections by briefly reading focused app text via Accessibility."
                ) {
                    settingsSwitch(isOn: appState.config.enableDictionaryCorrectionPrompts) { newValue in
                        handleDictionaryCorrectionPromptsToggle(newValue)
                    }
                    .help("Briefly reads focused app text after dictation to detect corrections.")
                }
            }

            settingsSection("Advanced") {
                settingsRow("Pause media during dictation") {
                    settingsSwitch(isOn: appState.config.pauseMediaDuringDictation) { newValue in
                        controller.updateConfig { $0.pauseMediaDuringDictation = newValue }
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Mute system audio during dictation") {
                    settingsSwitch(isOn: appState.config.muteSystemAudioDuringDictation) { newValue in
                        controller.updateConfig { $0.muteSystemAudioDuringDictation = newValue }
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Paste shortcut") {
                    settingsMenu(
                        selection: appState.config.pasteShortcut.label,
                        options: PasteShortcut.allCases.map(\.label)
                    ) { label in
                        guard let shortcut = PasteShortcut.allCases.first(where: { $0.label == label }) else { return }
                        controller.updateConfig { $0.pasteShortcut = shortcut }
                    }
                }
                settingsDescription("Use ⌘⇧V for terminals or apps that remap ⌘V.")
                screenContextRow("App context")
            }
        }
    }

    private var cleanupPromptSettings: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
            settingsRow("Cleanup preset") {
                FixedWidthPopUp(
                    selection: selectedCleanupPromptName,
                    options: cleanupPromptPresets.map(\.name),
                    onSelectIndex: { index in
                        guard index >= 0, index < cleanupPromptPresets.count else { return }
                        controller.selectTranscriptCleanupPrompt(id: cleanupPromptPresets[index].id)
                    }
                )
                .frame(height: 24)
            }

            settingsRow("Prompts") {
                Button {
                    isCleanupPromptManagerPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Text("Edit prompts...")
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var meetingsSettingsPane: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing24) {
            settingsSection("Meeting Transcription") {
                settingsRow("Meeting model", controlWidth: meetingControlWidth) {
                    if meetingBackendOptions.isEmpty {
                        Text("No downloaded models")
                            .font(GuesliTheme.body())
                            .foregroundStyle(GuesliTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        settingsMenu(
                            selection: selectedMeetingBackendLabel,
                            options: meetingBackendOptions.map(\.label)
                        ) { label in
                            if let option = meetingBackendOptions.first(where: { $0.label == label }) {
                                controller.selectMeetingTranscriptionBackend(option)
                            }
                        }
                    }
                }
            }

            settingsSection("Meeting Summaries") {
                settingsRow("AI transcript cleanup (meetings)", controlWidth: meetingControlWidth) {
                    settingsSwitch(isOn: appState.config.enableMeetingTranscriptCleanup) { newValue in
                        controller.updateConfig { config in
                            config.enableMeetingTranscriptCleanup = newValue
                            config.meetingTranscriptCleanupProvider = MeetingTranscriptCleanupProviderOption.chatGPT.rawValue
                        }
                    }
                }
                if appState.config.enableMeetingTranscriptCleanup && appState.selectedMeetingSummaryBackend != .chatGPT {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Cleanup account", controlWidth: meetingControlWidth) {
                        chatGPTAccountControl
                    }
                }
                if appState.config.enableMeetingTranscriptCleanup {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Cleanup model", controlWidth: meetingControlWidth) {
                        settingsModelMenu(
                            currentModel: appState.config.chatGPTMeetingCleanupModel,
                            presets: SummaryModelPreset.chatGPTTranscriptCleanupModels,
                            defaultModel: AppConfig.defaultChatGPTMeetingCleanupModel
                        ) { val in controller.updateConfig { $0.chatGPTMeetingCleanupModel = val } }
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)

                settingsRow("Summary backend", controlWidth: meetingControlWidth) {
                    settingsMenu(
                        selection: appState.selectedMeetingSummaryBackend.label,
                        options: MeetingSummaryBackendOption.all.map(\.label)
                    ) { label in
                        if let option = MeetingSummaryBackendOption.all.first(where: { $0.label == label }) {
                            controller.selectMeetingSummaryBackend(option)
                        }
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)

                if appState.selectedMeetingSummaryBackend == .chatGPT {
                    settingsRow("Account", controlWidth: meetingControlWidth) {
                        chatGPTAccountControl
                    }
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Model", controlWidth: meetingControlWidth) {
                        settingsModelMenu(
                            currentModel: appState.config.chatGPTModel,
                            presets: SummaryModelPreset.chatGPTModels
                        ) { val in controller.updateConfig { $0.chatGPTModel = val } }
                    }
                } else if appState.selectedMeetingSummaryBackend == .openAI {
                    settingsRow("API Key", controlWidth: meetingControlWidth) {
                        PastableSecureField(
                            text: appState.config.openAIAPIKey,
                            placeholder: "sk-...",
                            onChange: { val in controller.updateConfig { $0.openAIAPIKey = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Model", controlWidth: meetingControlWidth) {
                        settingsModelMenu(
                            currentModel: appState.config.openAIModel,
                            presets: SummaryModelPreset.openAIModels
                        ) { val in controller.updateConfig { $0.openAIModel = val } }
                    }
                    keyStatusRow(key: appState.config.openAIAPIKey)
                } else if appState.selectedMeetingSummaryBackend == .ollama {
                    settingsRow("Ollama URL", controlWidth: meetingControlWidth) {
                        PastableTextField(
                            text: appState.config.ollamaURL,
                            placeholder: "http://localhost:11434",
                            onChange: { val in controller.updateConfig { $0.ollamaURL = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Model", controlWidth: meetingControlWidth) {
                        settingsModelTextField(
                            currentModel: appState.config.ollamaModel,
                            placeholder: "qwen3.5"
                        ) { val in controller.updateConfig { $0.ollamaModel = val } }
                    }
                } else if appState.selectedMeetingSummaryBackend == .lmStudio {
                    settingsRow("LM Studio URL", controlWidth: meetingControlWidth) {
                        PastableTextField(
                            text: appState.config.lmStudioURL,
                            placeholder: "http://localhost:1234",
                            onChange: { val in controller.updateConfig { $0.lmStudioURL = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Model", controlWidth: meetingControlWidth) {
                        settingsModelTextField(
                            currentModel: appState.config.lmStudioModel,
                            placeholder: "Select a loaded LM Studio model"
                        ) { val in controller.updateConfig { $0.lmStudioModel = val } }
                    }
                } else if appState.selectedMeetingSummaryBackend == .customLLM {
                    settingsRow("API Format", controlWidth: meetingControlWidth) {
                        settingsMenu(
                            selection: CustomLLMFormat(rawValue: appState.config.customLLMFormat)?.label ?? CustomLLMFormat.openAI.label,
                            options: CustomLLMFormat.allCases.map(\.label)
                        ) { label in
                            guard let format = CustomLLMFormat.allCases.first(where: { $0.label == label }) else { return }
                            controller.updateConfig { $0.customLLMFormat = format.rawValue }
                        }
                    }
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Endpoint", controlWidth: meetingControlWidth) {
                        PastableTextField(
                            text: appState.config.customLLMURL,
                            placeholder: appState.config.customLLMFormat == CustomLLMFormat.anthropic.rawValue
                                ? "https://api.anthropic.com"
                                : "http://localhost:8080/v1",
                            onChange: { val in controller.updateConfig { $0.customLLMURL = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("API Key", controlWidth: meetingControlWidth) {
                        PastableSecureField(
                            text: appState.config.customLLMAPIKey,
                            placeholder: appState.config.customLLMFormat == CustomLLMFormat.anthropic.rawValue
                                ? "Required for Anthropic API"
                                : "Optional for local servers",
                            onChange: { val in controller.updateConfig { $0.customLLMAPIKey = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Model", controlWidth: meetingControlWidth) {
                        settingsModelTextField(
                            currentModel: appState.config.customLLMModel,
                            placeholder: appState.config.customLLMFormat == CustomLLMFormat.anthropic.rawValue
                                ? "claude-3-5-sonnet-20241022"
                                : "custom-model-id"
                        ) { val in controller.updateConfig { $0.customLLMModel = val } }
                    }
                } else {
                    settingsRow("API Key", controlWidth: meetingControlWidth) {
                        PastableSecureField(
                            text: appState.config.openRouterAPIKey,
                            placeholder: "sk-or-...",
                            onChange: { val in controller.updateConfig { $0.openRouterAPIKey = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Free model", controlWidth: meetingControlWidth) {
                        openRouterFreeModelMenu
                    }
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Custom model ID", controlWidth: meetingControlWidth) {
                        settingsModelTextField(
                            currentModel: appState.config.openRouterModel,
                            placeholder: "provider/model or openrouter/free"
                        ) { val in controller.updateConfig { $0.openRouterModel = val } }
                    }
                    keyStatusRow(key: appState.config.openRouterAPIKey)
                }

                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Default template", controlWidth: meetingControlWidth) {
                    meetingTemplateMenu(selectionID: appState.config.defaultMeetingTemplateID) { id in
                        controller.updateDefaultMeetingTemplate(id: id)
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Summary retries", controlWidth: meetingControlWidth) {
                    Stepper(
                        value: Binding(
                            get: {
                                MeetingSummaryRetryPolicy.clampedRetryCount(appState.config.meetingSummaryRetryCount)
                            },
                            set: { newValue in
                                controller.updateConfig {
                                    $0.meetingSummaryRetryCount = MeetingSummaryRetryPolicy.clampedRetryCount(newValue)
                                }
                            }
                        ),
                        in: 0...MeetingSummaryRetryPolicy.maximumRetryCount
                    ) {
                        Text(summaryRetryLabel(appState.config.meetingSummaryRetryCount))
                            .font(GuesliTheme.body())
                            .foregroundStyle(GuesliTheme.textPrimary)
                    }
                }
                settingsDescription("Retry transient AI summary failures before saving failed notes.")
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Templates", controlWidth: meetingControlWidth) {
                    actionButton("Manage Templates…") {
                        controller.showMeetingTemplatesManager()
                    }
                }
            }

            settingsSection("Recording") {
                settingsRow("Save meeting recording") {
                    settingsMenu(
                        selection: recordingSaveLabel(for: appState.config.meetingRecordingSavePolicy),
                        options: MeetingRecordingSavePolicy.allCases.map(recordingSaveLabel(for:))
                    ) { label in
                        guard let policy = recordingSavePolicy(for: label) else { return }
                        controller.updateConfig { $0.meetingRecordingSavePolicy = policy }
                    }
                }
                if appState.config.meetingRecordingSavePolicy != .never {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Recording format") {
                        settingsMenu(
                            selection: appState.config.resolvedMeetingRecordingFileFormat.displayName,
                            options: MeetingRecordingFileFormat.allCases.map(recordingFileFormatLabel(for:))
                        ) { label in
                            guard let format = recordingFileFormat(for: label) else { return }
                            controller.updateConfig { $0.meetingRecordingFileFormat = format.rawValue }
                        }
                    }
                    settingsDescription("M4A is recommended for smaller files. WAV is lossless and uses more storage.")
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Recording folder") {
                    meetingRecordingFolderPicker
                }
                settingsDescription("Retranscription uses a temporary WAV copy and removes it afterward.")
            }

            settingsSection("Meeting Notifications") {
                settingsRow("Open meeting links") {
                    settingsMenu(
                        selection: selectedMeetingBrowserLabel,
                        options: meetingBrowserOpenOptions.map(\.name)
                    ) { label in
                        guard let option = meetingBrowserOpenOptions.first(where: { $0.name == label }) else { return }
                        controller.updateConfig { $0.preferredMeetingBrowserBundleID = option.bundleID }
                    }
                }
                settingsDescription("System Default keeps macOS/OpenIn routing. Choosing a browser opens meeting links directly there.")
                Divider().background(GuesliTheme.surfaceBorder)

                settingsRow("Scheduled meetings") {
                    settingsSwitch(isOn: appState.config.showScheduledMeetingNotifications) { newValue in
                        controller.updateConfig { $0.showScheduledMeetingNotifications = newValue }
                    }
                }
                settingsDescription("Show notifications for calendar meetings with a join link.")

                if appState.config.showScheduledMeetingNotifications {
                    Divider().background(GuesliTheme.surfaceBorder)

                    settingsRow("Reminder timing") {
                        settingsMenu(
                            selection: scheduledMeetingLeadTimeLabel(for: appState.config.scheduledMeetingNotificationLeadTime),
                            options: ScheduledMeetingNotificationLeadTime.allCases.map(scheduledMeetingLeadTimeLabel(for:))
                        ) { label in
                            guard let leadTime = scheduledMeetingLeadTime(for: label) else { return }
                            controller.updateConfig { $0.scheduledMeetingNotificationLeadTime = leadTime }
                        }
                    }
                    settingsDescription("At start time avoids early calendar-only prompts before you join.")
                }

                Divider().background(GuesliTheme.surfaceBorder)

                settingsRow("Default action", controlWidth: meetingControlWidth) {
                    settingsMenu(
                        selection: appState.config.meetingJoinDefaultAction.buttonLabel,
                        options: MeetingJoinDefaultAction.allCases.map(\.buttonLabel)
                    ) { label in
                        guard let action = meetingJoinDefaultAction(for: label) else { return }
                        controller.updateConfig { $0.meetingJoinDefaultAction = action }
                    }
                }
                settingsDescription("Primary button for notifications and Coming Up.")

            }

            settingsSection("Calendars") {
                settingsRow("Upcoming meetings", controlWidth: meetingControlWidth) {
                    settingsMenu(
                        selection: selectedUpcomingMeetingsWindow.label,
                        options: UpcomingMeetingsWindow.allCases.map(\.label)
                    ) { label in
                        guard let window = UpcomingMeetingsWindow.allCases.first(where: { $0.label == label }) else { return }
                        controller.updateUpcomingMeetingsWindow(dayCount: window.dayCount)
                    }
                }
                settingsDescription("Controls how many calendar days appear in Coming Up, the menu bar, and scheduled meeting checks.")
                Divider().background(GuesliTheme.surfaceBorder)
                calendarSourcesControl
                    .padding(.bottom, GuesliTheme.spacing8)
            }

            if appState.isGoogleCalendarAvailable {
                settingsSection("Calendar") {
                    settingsRow("Google Calendar") {
                        googleCalendarControl
                    }
                }
            }

            settingsSection("Advanced") {
                settingsRow("Live meeting transcription", controlWidth: meetingControlWidth) {
                    settingsSwitch(isOn: appState.config.resolvedMeetingProcessingMode == .live) { enabled in
                        controller.updateConfig {
                            $0.meetingProcessingMode = enabled
                                ? MeetingProcessingMode.live.rawValue
                                : MeetingProcessingMode.post.rawValue
                        }
                    }
                }
                settingsDescription("Experimental. The default records first and transcribes after the meeting for lower overhead and more reliable final notes.")
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Auto-record calendar meetings") {
                    settingsSwitch(isOn: appState.config.autoRecordMeetings) { newValue in
                        controller.updateConfig { $0.autoRecordMeetings = newValue }
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Auto-detected meeting prompts") {
                    settingsSwitch(isOn: appState.config.showMeetingDetectionNotification) { newValue in
                        controller.updateConfig { $0.showMeetingDetectionNotification = newValue }
                    }
                }
                settingsDescription("Detect calls from browser, camera, microphone, or app audio activity. Calendar reminders work independently.")
                if appState.config.showMeetingDetectionNotification {
                    Divider().background(GuesliTheme.surfaceBorder)
                    mutedMeetingDetectionAppsControl
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Auto-export meetings") {
                    settingsSwitch(isOn: appState.config.autoExportMarkdownEnabled) { newValue in
                        controller.updateConfig { $0.autoExportMarkdownEnabled = newValue }
                    }
                }
                if appState.config.autoExportMarkdownEnabled {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Export folder") {
                        autoExportFolderPicker
                    }
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Export content") {
                        settingsMenu(
                            selection: appState.config.resolvedAutoExportMarkdownContent.displayName,
                            options: MeetingExportContent.allCases.map(\.displayName)
                        ) { label in
                            guard let content = MeetingExportContent.allCases.first(where: { $0.displayName == label }) else { return }
                            controller.updateConfig { $0.autoExportMarkdownContent = content.rawValue }
                        }
                    }
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Export format") {
                        settingsMenu(
                            selection: appState.config.resolvedAutoExportFileFormat.displayName,
                            options: MeetingAutoExportFileFormat.allCases.map(\.displayName)
                        ) { label in
                            guard let format = MeetingAutoExportFileFormat.allCases.first(where: { $0.displayName == label }) else { return }
                            controller.updateConfig { $0.autoExportFileFormat = format.rawValue }
                        }
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Google Meet speaker bridge", controlWidth: meetingControlWidth) {
                    settingsSwitch(isOn: appState.config.enableMeetSpeakerBridge) { newValue in
                        controller.setMeetSpeakerBridgeEnabled(newValue)
                    }
                }
                settingsDescription("Optional Chrome extension integration for speaker names. The local bridge listens only while Guesli records an active Google Meet.")
                if appState.config.enableMeetSpeakerBridge {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Pairing token", controlWidth: meetingControlWidth) {
                        HStack(spacing: GuesliTheme.spacing8) {
                            Text(String(appState.config.meetSpeakerBridgePairingToken.prefix(8)) + "…")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(GuesliTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    appState.config.meetSpeakerBridgePairingToken,
                                    forType: .string
                                )
                            }
                            .buttonStyle(.bordered)
                            Button {
                                controller.regenerateMeetSpeakerBridgePairingToken()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .help("Generate a new pairing token")
                        }
                    }
                    settingsDescription("Paste this token into the extension options. Regenerating it disconnects the old extension configuration.")
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Enable post-meeting hook", controlWidth: meetingControlWidth) {
                    settingsSwitch(isOn: appState.config.meetingHookEnabled) { newValue in
                        controller.updateConfig { $0.meetingHookEnabled = newValue }
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Hook script", controlWidth: meetingControlWidth) {
                    meetingHookPathPicker
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Timeout", controlWidth: meetingControlWidth) {
                    meetingHookTimeoutControl
                }
                settingsDescription("Runs a user-supplied executable after each completed meeting. The executable receives JSON on stdin and must already be runnable on its own.")
            }
            .padding(.top, GuesliTheme.spacing8)
        }
        .onAppear {
            Task {
                async let eventKitRefresh: Void = controller.refreshAvailableEventKitCalendars()
                async let googleRefresh: Void = controller.refreshGoogleCalendarList()
                _ = await (eventKitRefresh, googleRefresh)
            }
        }
    }

    private var appearanceSettingsPane: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing24) {
            settingsSection("Floating Indicator") {
                settingsRow("Show floating indicator") {
                    settingsSwitch(isOn: appState.config.showFloatingIndicator) { newValue in
                        controller.updateConfig { $0.showFloatingIndicator = newValue }
                        controller.refreshIndicatorVisibility()
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Indicator position") {
                    let isCustom = appState.config.indicatorAnchor == .custom
                    let selection = isCustom ? customIndicatorPositionLabel : appState.config.indicatorAnchor.label
                    let options = (isCustom ? [customIndicatorPositionLabel] : [])
                        + IndicatorAnchor.allCases.filter { $0 != .custom }.map(\.label)
                    settingsMenu(
                        selection: selection,
                        options: options
                    ) { label in
                        if label == customIndicatorPositionLabel { return }
                        guard let anchor = IndicatorAnchor.allCases.first(where: { $0.label == label }) else { return }
                        controller.updateConfig { $0.indicatorAnchor = anchor }
                        controller.refreshIndicatorVisibility()
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Indicator size") {
                    settingsMenu(
                        selection: appState.config.indicatorSize.label,
                        options: IndicatorSize.allCases.map(\.label)
                    ) { label in
                        guard let size = IndicatorSize.allCases.first(where: { $0.label == label }) else { return }
                        controller.updateConfig { $0.indicatorSize = size }
                        controller.refreshIndicatorVisibility()
                    }
                }
                if appState.config.indicatorAnchor.isDockPosition {
                    Divider().background(GuesliTheme.surfaceBorder)
                    settingsRow("Dock gap") {
                        Stepper(
                            value: Binding(
                                get: { min(max(appState.config.indicatorDockGap, 0), 200) },
                                set: { newValue in
                                    controller.updateConfig { $0.indicatorDockGap = newValue }
                                    controller.refreshIndicatorVisibility()
                                }
                            ),
                            in: 0...200
                        ) {
                            Text("\(appState.config.indicatorDockGap) px")
                                .font(GuesliTheme.body())
                                .foregroundStyle(GuesliTheme.textPrimary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            settingsSection("Appearance") {
                settingsRow("Dark mode") {
                    settingsSwitch(isOn: appState.config.darkMode) { newValue in
                        controller.updateConfig { $0.darkMode = newValue }
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Menu bar icon") {
                    menuBarIconPicker
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Accent color") {
                    glassTintPicker
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Play sound effects") {
                    settingsSwitch(isOn: appState.config.soundEnabled) { newValue in
                        controller.updateConfig { $0.soundEnabled = newValue }
                    }
                }
                Divider().background(GuesliTheme.surfaceBorder)
                settingsRow("Show next meeting in menu bar") {
                    settingsSwitch(isOn: appState.config.showNextMeetingInMenuBar) { newValue in
                        controller.updateConfig { $0.showNextMeetingInMenuBar = newValue }
                    }
                }
            }
        }
    }

    private var glassTintPicker: some View {
        HStack(spacing: 6) {
            ForEach(Self.accentPresets, id: \.hex) { preset in
                let isSelected = appState.config.recordingColorHex.lowercased() == preset.hex
                Button {
                    controller.updateConfig { $0.recordingColorHex = preset.hex }
                } label: {
                    Circle()
                        .fill(Color(hex: preset.hex))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                        )
                        .overlay(
                            Circle().strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
        }
    }

    private var menuBarIconPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(MenuBarIconRenderer.options, id: \.id) { option in
                    let isSelected = appState.config.menuBarIcon == option.id
                    Button {
                        controller.updateConfig { $0.menuBarIcon = option.id }
                    } label: {
                        Group {
                            if option.id == "guesli",
                               let img = MenuBarIconRenderer.make(choice: "guesli") {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: option.id)
                                    .font(.system(size: 12))
                            }
                        }
                        .foregroundStyle(isSelected ? GuesliTheme.accent : GuesliTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected ? GuesliTheme.surfaceSelected : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.white.opacity(isSelected ? 0.3 : 0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(option.label)
                }
            }
        }
    }

    @ViewBuilder
    private var chatGPTAccountControl: some View {
        if appState.isChatGPTAuthenticated {
            Button {
                controller.signOutChatGPT()
            } label: {
                HStack(spacing: 5) {
                    OpenAILogoShape()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                    Text("Signed in · Sign Out")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(GuesliTheme.success)
                .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
        } else if isSigningInChatGPT {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Signing in...")
                    .font(.system(size: 11))
                    .foregroundStyle(GuesliTheme.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isSigningInChatGPT = true
                    chatGPTSignInError = nil
                    Task {
                        let error = await controller.signInWithChatGPT()
                        isSigningInChatGPT = false
                        chatGPTSignInError = error
                    }
                } label: {
                    HStack(spacing: 5) {
                        OpenAILogoShape()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                        Text("Sign in with ChatGPT")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(GuesliTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)

                if let chatGPTSignInError {
                    Text(chatGPTSignInError)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var googleCalendarControl: some View {
        if appState.isGoogleCalendarAuthenticated {
            Button {
                controller.signOutGoogleCalendar()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                    Text("Connected · Disconnect")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(GuesliTheme.success)
                .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
        } else if isSigningInGoogleCal {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting...")
                    .font(.system(size: 11))
                    .foregroundStyle(GuesliTheme.textSecondary)
            }
        } else if !appState.isGoogleCalendarVerified {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Connect Google Calendar")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(GuesliTheme.textTertiary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))

                Text("Google OAuth verification pending")
                    .font(.system(size: 10))
                    .foregroundStyle(GuesliTheme.textTertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isSigningInGoogleCal = true
                    googleCalSignInError = nil
                    Task {
                        let error = await controller.signInWithGoogleCalendar()
                        isSigningInGoogleCal = false
                        googleCalSignInError = error
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                        Text("Connect Google Calendar")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(GuesliTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)

                if let googleCalSignInError {
                    Text(googleCalSignInError)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    private func pickMeetingHookFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a hook script"
        panel.prompt = "Choose Script"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = preferredMeetingHookDirectoryURL()

        presentOpenPanel(panel) { url in
            controller.updateConfig { $0.meetingHookPath = url.standardizedFileURL.path }
        }
    }

    private func pickAutoExportFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for exported notes"
        panel.prompt = "Choose Folder"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferredAutoExportDirectoryURL()

        presentOpenPanel(panel) { url in
            controller.updateConfig { $0.autoExportMarkdownFolderPath = url.standardizedFileURL.path }
        }
    }

    private func preferredAutoExportDirectoryURL() -> URL {
        let configuredPath = appState.config.autoExportMarkdownFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath).standardizedFileURL
            if FileManager.default.fileExists(atPath: configuredURL.path) {
                return configuredURL
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
    }

    private func preferredMeetingHookDirectoryURL() -> URL {
        let configuredPath = appState.config.meetingHookPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath).standardizedFileURL
            let parentDirectory = configuredURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parentDirectory.path) {
                return parentDirectory
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    private func presentOpenPanel(_ panel: NSOpenPanel, onPick: @escaping (URL) -> Void) {
        NSApp.activate()
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                onPick(url)
            }
        } else {
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                onPick(url)
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        settingsSection("Permissions") {
            permissionStatusRow(
                "Microphone",
                granted: micGranted,
                action: requestMicrophonePermission,
                pane: "Privacy_Microphone"
            )
            Divider().background(GuesliTheme.surfaceBorder)
            permissionStatusRow(
                "Accessibility",
                granted: accessibilityGranted,
                action: {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                    AXIsProcessTrustedWithOptions(opts)
                },
                pane: "Privacy_Accessibility"
            )
            Divider().background(GuesliTheme.surfaceBorder)
            permissionStatusRow(
                "Input Monitoring",
                granted: inputMonitoringGranted,
                action: {
                    if !CGRequestListenEventAccess() {
                        openPrivacyPane("Privacy_ListenEvent")
                    }
                },
                pane: "Privacy_ListenEvent"
            )
            Divider().background(GuesliTheme.surfaceBorder)
            permissionStatusRow(
                "Screen Recording",
                granted: screenRecordingGranted,
                action: { CGRequestScreenCaptureAccess() },
                pane: "Privacy_ScreenCapture"
            )
            if appState.config.useCoreAudioTap {
                Divider().background(GuesliTheme.surfaceBorder)
                permissionStatusRow(
                    "System Audio",
                    granted: systemAudioGranted,
                    action: {
                        Task { @MainActor in
                            systemAudioGranted = await CoreAudioSystemRecorder.requestSystemAudioAccess()
                        }
                    },
                    pane: "Privacy_ScreenCapture"
                )
            }
        }
    }

    @ViewBuilder
    private func permissionStatusRow(_ name: String, granted: Bool, action: @escaping () -> Void, pane: String) -> some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(granted ? GuesliTheme.success : GuesliTheme.recording)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(GuesliTheme.body())
                    .foregroundStyle(GuesliTheme.textPrimary)
            }
            Spacer()
            if granted {
                Text("Granted")
                    .font(.system(size: 11))
                    .foregroundStyle(GuesliTheme.success)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GuesliTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(GuesliTheme.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            }
            Button {
                openPrivacyPane(pane)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11))
                    .foregroundStyle(GuesliTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Open in System Settings")
        }
        .frame(minHeight: 32)
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in
                    refreshPermissionStatuses(for: .permissionRequested)
                }
            }
        case .authorized:
            refreshPermissionStatuses(for: .permissionRequested)
        case .denied, .restricted:
            openPrivacyPane("Privacy_Microphone")
        @unknown default:
            openPrivacyPane("Privacy_Microphone")
        }
    }

    @ViewBuilder
    private func screenContextControl(width: CGFloat? = nil) -> some View {
        if accessibilityGranted {
            settingsSwitch(isOn: appState.config.enableScreenContext) { newValue in
                handleScreenContextToggle(newValue)
            }
            .frame(width: width, alignment: .trailing)
        } else {
            Button {
                handleScreenContextToggle(true)
            } label: {
                Text("Grant")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GuesliTheme.accent)
                    .frame(width: width)
                    .frame(minHeight: 32)
                    .background(GuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
        }
    }

    @discardableResult
    private func handleScreenContextToggle(_ enabled: Bool) -> Bool {
        guard enabled else {
            clearPendingScreenContextEnable()
            controller.updateConfig { $0.enableScreenContext = false }
            return false
        }

        guard accessibilityGranted else {
            pendingScreenContextEnable = true
            pendingScreenContextRequestedAt = Date().timeIntervalSince1970
            let granted = controller.requestScreenContextEnable()
            accessibilityGranted = AXIsProcessTrusted()
            if granted || accessibilityGranted {
                clearPendingScreenContextEnable()
            }
            return granted || accessibilityGranted
        }

        clearPendingScreenContextEnable()
        return controller.requestScreenContextEnable()
    }

    private func handleDictionaryCorrectionPromptsToggle(_ enabled: Bool) {
        if controller.setDictionaryCorrectionPromptsFromToggle(enabled) == .needsAccessibilityPermission {
            isShowingDictionaryAccessibilityPrompt = true
        }
    }

    private func startPermissionPolling() {
        refreshPermissionStatuses(for: .initialDisplay)
        permissionPollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            refreshPermissionStatuses(for: .periodicPoll)
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func refreshPermissionStatuses(for reason: SettingsPermissionRefreshReason) {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        controller.reconcilePendingDictionaryCorrectionAccessibilityEnable()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        if reason.refreshesLaunchAtLogin {
            controller.refreshLaunchAtLoginState()
        }
        if accessibilityGranted && pendingScreenContextEnable {
            if controller.requestScreenContextEnable() {
                clearPendingScreenContextEnable()
            }
        }
        if !accessibilityGranted && isPendingScreenContextGrantExpired {
            clearPendingScreenContextEnable()
        }
        if !accessibilityGranted && appState.config.enableScreenContext {
            clearPendingScreenContextEnable()
            controller.updateConfig { $0.enableScreenContext = false }
        }
        controller.reclassifyVoiceNotesAsDictationIfReady(
            microphoneGranted: micGranted,
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: inputMonitoringGranted
        )
        if reason.refreshesSystemAudio {
            refreshSystemAudioPermissionIfNeeded()
        }
    }

    private var isPendingScreenContextGrantExpired: Bool {
        guard pendingScreenContextEnable else { return false }
        guard pendingScreenContextRequestedAt > 0 else { return true }
        return Date().timeIntervalSince1970 - pendingScreenContextRequestedAt > screenContextGrantIntentTimeout
    }

    private func clearPendingScreenContextEnable() {
        pendingScreenContextEnable = false
        pendingScreenContextRequestedAt = 0
    }

    private func summaryRetryLabel(_ retryCount: Int) -> String {
        let clamped = MeetingSummaryRetryPolicy.clampedRetryCount(retryCount)
        switch clamped {
        case 0:
            return "No retries"
        case 1:
            return "1 retry"
        default:
            return "\(clamped) retries"
        }
    }

    private func refreshSystemAudioPermissionIfNeeded() {
        guard appState.config.useCoreAudioTap, !isCheckingSystemAudioPermission else { return }
        isCheckingSystemAudioPermission = true

        Task {
            let granted = await Task.detached(priority: .utility) {
                CoreAudioSystemRecorder.checkSystemAudioPermission()
            }.value
            await MainActor.run {
                self.systemAudioGranted = granted
                self.isCheckingSystemAudioPermission = false
            }
        }
    }

    // MARK: - Layout Primitives

    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GuesliTheme.textTertiary)
                .textCase(.uppercase)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(GuesliTheme.spacing16)
            .background(GuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium)
                    .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    /// Standardized row: label on left, control on right.
    /// Controls share a fixed-width column so they all right-align consistently.
    @ViewBuilder
    private func settingsRow(_ label: String, controlWidth rowControlWidth: CGFloat? = nil, @ViewBuilder control: () -> some View) -> some View {
        let width = rowControlWidth ?? controlWidth
        HStack(alignment: .center) {
            Text(label)
                .font(GuesliTheme.body())
                .foregroundStyle(GuesliTheme.textPrimary)
                .layoutPriority(1)
            Spacer(minLength: 20)
            ZStack(alignment: .trailing) {
                // Invisible spacer forces the ZStack to exactly controlWidth
                Color.clear.frame(width: width, height: 1)
                control()
                    .frame(maxWidth: width)
            }
        }
        .frame(minHeight: 32)
    }

    @ViewBuilder
    private func settingsRow(
        _ label: String,
        description: String,
        controlWidth rowControlWidth: CGFloat? = nil,
        @ViewBuilder control: () -> some View
    ) -> some View {
        let width = rowControlWidth ?? controlWidth
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(GuesliTheme.body())
                    .foregroundStyle(GuesliTheme.textPrimary)
                Text(description)
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            control()
                .frame(width: width, alignment: .trailing)
        }
        .frame(minHeight: 44)
    }

    private func settingsDescription(_ text: String) -> some View {
        Text(text)
            .font(GuesliTheme.caption())
            .foregroundStyle(GuesliTheme.textTertiary)
            .padding(.horizontal, GuesliTheme.spacing16)
            .padding(.top, -4)
            .padding(.bottom, GuesliTheme.spacing8)
    }

    // MARK: - Controls

    @ViewBuilder
    private func settingsSwitch(isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { onChange($0) }))
                .toggleStyle(.switch)
                .tint(GuesliTheme.accent)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private func settingsMenu(selection: String, options: [String], onChange: @escaping (String) -> Void) -> some View {
        FixedWidthPopUp(selection: selection, options: options, onChange: onChange)
            .frame(height: 24)
    }

    private var mutedMeetingDetectionAppsControl: some View {
        let muted = Set(appState.config.mutedMeetingDetectionAppBundleIDs)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Don't notify me when a call is detected in these apps:")
                .font(GuesliTheme.body())
                .foregroundStyle(GuesliTheme.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], alignment: .leading, spacing: 8) {
                ForEach(meetingDetectionAppOptions) { app in
                    mutedDetectionAppButton(app, isMuted: muted.contains(app.bundleID))
                }
            }
        }
        .padding(.leading, GuesliTheme.spacing16)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(GuesliTheme.surfaceBorder)
                .frame(width: 2)
        }
    }

    private func mutedDetectionAppButton(_ app: MeetingDetectionAppOption, isMuted: Bool) -> some View {
        Button {
            updateMutedMeetingDetectionApp(app.bundleID, isMuted: !isMuted)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isMuted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isMuted ? GuesliTheme.accent : GuesliTheme.textTertiary)
                    .frame(width: 16)
                Image(systemName: app.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GuesliTheme.textTertiary)
                    .frame(width: 14)
                Text(app.name)
                    .font(.system(size: 12))
                    .foregroundStyle(GuesliTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(isMuted ? GuesliTheme.accentSubtle : GuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                    .strokeBorder(isMuted ? GuesliTheme.accent.opacity(0.35) : GuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func updateMutedMeetingDetectionApp(_ bundleID: String, isMuted: Bool) {
        controller.updateConfig { config in
            var muted = Set(config.mutedMeetingDetectionAppBundleIDs)
            if isMuted {
                muted.insert(bundleID)
            } else {
                muted.remove(bundleID)
            }
            config.mutedMeetingDetectionAppBundleIDs = muted.sorted()
        }
    }

    // MARK: - Calendars

    private struct CalendarToggleItem: Identifiable, Equatable {
        let id: String
        let title: String
        let colorHex: String?
        let isEnabled: Bool
    }

    private struct CalendarSourceGroup: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let iconName: String
        let items: [CalendarToggleItem]
    }

    private var calendarSourceGroups: [CalendarSourceGroup] {
        let disabled = Set(appState.config.disabledCalendarIDs)
        var groups: [CalendarSourceGroup] = []

        let ekBySource = Dictionary(grouping: appState.availableEventKitCalendars) { $0.sourceTitle }
        for sourceTitle in ekBySource.keys.sorted() {
            let items = (ekBySource[sourceTitle] ?? [])
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                .map { cal in
                    CalendarToggleItem(
                        id: cal.id,
                        title: cal.title,
                        colorHex: cal.colorHex,
                        isEnabled: !disabled.contains(cal.id)
                    )
                }
            groups.append(CalendarSourceGroup(
                id: "ek::\(sourceTitle)",
                title: sourceTitle,
                subtitle: calendarSourceSubtitle(for: sourceTitle),
                iconName: calendarSourceIconName(for: sourceTitle),
                items: items
            ))
        }

        if appState.isGoogleCalendarAuthenticated && !appState.availableGoogleCalendars.isEmpty {
            let items = appState.availableGoogleCalendars.map { cal in
                CalendarToggleItem(
                    id: cal.id,
                    title: cal.summary + (cal.isPrimary ? " (Primary)" : ""),
                    colorHex: cal.colorHex,
                    isEnabled: !disabled.contains(cal.id)
                )
            }
            groups.append(CalendarSourceGroup(
                id: "google_oauth",
                title: "Google Calendar",
                subtitle: "Connected directly to Guesli",
                iconName: "calendar.badge.plus",
                items: items
            ))
        }

        return groups
    }

    private var calendarSourcesControl: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing16) {
            Text("Calendar sources are listed first, with their calendars underneath. Disabled calendars are hidden from Guesli — no notifications, no Coming Up, no meeting detection.")
                .font(GuesliTheme.caption())
                .foregroundStyle(GuesliTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if calendarSourceGroups.isEmpty {
                Text("No calendars detected. Make sure Calendar permission is granted in System Settings > Privacy & Security > Calendars.")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    openPrivacyPane("Privacy_Calendars")
                } label: {
                    HStack(spacing: GuesliTheme.spacing8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Open Calendar Privacy")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.textPrimary)
                    .padding(.horizontal, GuesliTheme.spacing12)
                    .padding(.vertical, 6)
                    .background(GuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                            .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                ForEach(calendarSourceGroups) { group in
                    calendarSourceGroupView(group)
                }
            }

            if appState.isGoogleCalendarAuthenticated && !appState.availableEventKitCalendars.isEmpty {
                Text("Google calendars may appear once from macOS Calendar and once from Guesli's Google connection. Turn off both copies to hide that calendar completely.")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.isGoogleCalendarAuthenticated {
                googleCalendarListLoadStateView
            }
        }
    }

    @ViewBuilder
    private func calendarSourceGroupView(_ group: CalendarSourceGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: group.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GuesliTheme.textSecondary)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GuesliTheme.textPrimary)
                        .lineLimit(1)

                    Text("\(group.subtitle) • \(group.items.count) \(group.items.count == 1 ? "calendar" : "calendars")")
                        .font(.system(size: 11))
                        .foregroundStyle(GuesliTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], alignment: .leading, spacing: 8) {
                ForEach(group.items) { item in
                    calendarToggleButton(item)
                }
            }
            .padding(.leading, 28)
        }
        .padding(.vertical, 2)
    }

    private func calendarSourceSubtitle(for sourceTitle: String) -> String {
        let normalized = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "icloud" {
            return "iCloud account in macOS Calendar"
        }
        if normalized == "subscribed calendars" {
            return "Subscribed in macOS Calendar"
        }
        if normalized == "other" {
            return "System calendars from macOS"
        }
        return "Calendar account in macOS"
    }

    private func calendarSourceIconName(for sourceTitle: String) -> String {
        let normalized = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "icloud" {
            return "icloud"
        }
        if normalized == "subscribed calendars" {
            return "calendar.badge.clock"
        }
        if normalized == "other" {
            return "person.crop.circle.badge.clock"
        }
        return "calendar"
    }

    private func calendarToggleButton(_ item: CalendarToggleItem) -> some View {
        Button {
            updateDisabledCalendar(item.id, isDisabled: item.isEnabled)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.isEnabled ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.isEnabled ? GuesliTheme.accent : GuesliTheme.textTertiary)
                    .frame(width: 16)
                Circle()
                    .fill(item.colorHex.map { Color(hex: $0) } ?? GuesliTheme.textTertiary)
                    .frame(width: 8, height: 8)
                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundStyle(item.isEnabled ? GuesliTheme.textPrimary : GuesliTheme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(GuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                    .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var googleCalendarListLoadStateView: some View {
        switch appState.googleCalendarListLoadState {
        case .loading:
            Text("Loading Google calendars…")
                .font(GuesliTheme.caption())
                .foregroundStyle(GuesliTheme.textTertiary)
        case .failed(let message):
            HStack(spacing: 8) {
                Text("Failed to load Google calendars: \(message)")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textTertiary)
                Button("Retry") {
                    Task { await controller.refreshGoogleCalendarList() }
                }
                .buttonStyle(.link)
                .font(GuesliTheme.caption())
            }
        case .idle, .loaded:
            EmptyView()
        }
    }

    private func updateDisabledCalendar(_ calendarID: String, isDisabled: Bool) {
        controller.updateConfig { config in
            var disabled = Set(config.disabledCalendarIDs)
            if isDisabled {
                disabled.insert(calendarID)
            } else {
                disabled.remove(calendarID)
            }
            config.disabledCalendarIDs = disabled.sorted()
        }
        Task { await controller.refreshUpcomingCalendarEvents() }
    }

    @ViewBuilder
    private var autoExportFolderPicker: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GuesliTheme.textTertiary)

                Text(autoExportFolderLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(appState.config.autoExportMarkdownFolderPath.isEmpty ? GuesliTheme.textTertiary : GuesliTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(GuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                    .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            .help(autoExportFolderHelp)

            if !appState.config.autoExportMarkdownFolderPath.isEmpty {
                Button {
                    controller.updateConfig { $0.autoExportMarkdownFolderPath = "" }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GuesliTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(GuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                                .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Clear destination folder")
            }

            Button {
                pickAutoExportFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(GuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                            .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Choose destination folder")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var autoExportFolderLabel: String {
        let path = appState.config.autoExportMarkdownFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "Choose a folder..." }
        return path
    }

    private var autoExportFolderHelp: String {
        let path = appState.config.autoExportMarkdownFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "No destination folder selected" }
        return path
    }

    @ViewBuilder
    private var meetingRecordingFolderPicker: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GuesliTheme.textTertiary)

                Text(meetingRecordingFolderLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(appState.config.meetingRecordingFolderPath.isEmpty ? GuesliTheme.textTertiary : GuesliTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(GuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                    .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            .help(meetingRecordingFolderHelp)

            if !appState.config.meetingRecordingFolderPath.isEmpty {
                Button {
                    controller.updateConfig { $0.meetingRecordingFolderPath = "" }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GuesliTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(GuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                                .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Use default recording folder")
            }

            Button {
                pickMeetingRecordingFolder()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(GuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                            .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Choose recording folder")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var meetingRecordingFolderLabel: String {
        let path = appState.config.meetingRecordingFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "Default folder" }
        return path
    }

    private var meetingRecordingFolderHelp: String {
        let path = appState.config.meetingRecordingFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return MeetingRecordingStorage.defaultDirectory().path
        }
        return path
    }

    private func pickMeetingRecordingFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose recording folder"
        panel.prompt = "Choose Folder"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferredMeetingRecordingDirectoryURL()

        presentOpenPanel(panel) { url in
            controller.updateConfig { $0.meetingRecordingFolderPath = url.standardizedFileURL.path }
        }
    }

    private func preferredMeetingRecordingDirectoryURL() -> URL {
        let configuredPath = appState.config.meetingRecordingFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath, isDirectory: true).standardizedFileURL
            if FileManager.default.fileExists(atPath: configuredURL.path) {
                return configuredURL
            }
        }
        return MeetingRecordingStorage.defaultDirectory()
    }

    @ViewBuilder
    private var meetingHookPathPicker: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GuesliTheme.textTertiary)

                if appState.config.meetingHookPath.isEmpty {
                    Text("Choose a script…")
                        .font(.system(size: 12))
                        .foregroundStyle(GuesliTheme.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(appState.config.meetingHookPath)
                        .font(.system(size: 12))
                        .foregroundStyle(GuesliTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(GuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                    .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            .help(appState.config.meetingHookPath.isEmpty ? "No hook script selected" : appState.config.meetingHookPath)

            if !appState.config.meetingHookPath.isEmpty {
                Button {
                    controller.updateConfig { $0.meetingHookPath = "" }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GuesliTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(GuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                                .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Clear hook script")
            }

            Button {
                pickMeetingHookFile()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(GuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                            .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Choose hook script")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var meetingHookTimeoutControl: some View {
        Stepper(
            value: Binding(
                get: { max(appState.config.meetingHookTimeoutSeconds, 1) },
                set: { newValue in
                    controller.updateConfig { $0.meetingHookTimeoutSeconds = max(newValue, 1) }
                }
            ),
            in: 1...600
        ) {
            Text("\(max(appState.config.meetingHookTimeoutSeconds, 1)) seconds")
                .font(GuesliTheme.body())
                .foregroundStyle(GuesliTheme.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 92, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func meetingTemplateMenu(selectionID: String, onChange: @escaping (String) -> Void) -> some View {
        let allItems: [(id: String, label: String)] = {
            var items: [(String, String)] = [(MeetingTemplates.autoID, MeetingTemplates.auto.title)]
            items += controller.builtInMeetingTemplates().map { ($0.id, $0.title) }
            items += controller.customMeetingTemplates().map { ($0.id, $0.name) }
            return items
        }()
        let selectedLabel = allItems.first(where: { $0.id == selectionID })?.label ?? "Auto"
        FixedWidthPopUp(
            selection: selectedLabel,
            options: allItems.map(\.label),
            onSelectIndex: { index in
                guard index >= 0 && index < allItems.count else { return }
                onChange(allItems[index].id)
            }
        )
        .frame(height: 24)
    }

    @ViewBuilder
    private func settingsModelMenu(
        currentModel: String,
        presets: [SummaryModelPreset],
        defaultModel: String? = nil,
        onChange: @escaping (String) -> Void
    ) -> some View {
        let defaultId = defaultModel ?? presets.first?.id ?? ""
        let menuPresets = relabeledPresets(
            SummaryModelPreset.menuPresets(presets, currentModel: currentModel),
            defaultModel: defaultModel
        )
        let effectiveModel = currentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultId
            : currentModel
        let selectedLabel = menuPresets.first(where: { $0.id == effectiveModel })?.label ?? menuPresets.first?.label ?? ""
        FixedWidthPopUp(
            selection: selectedLabel,
            options: menuPresets.map(\.label),
            onSelectIndex: { index in
                guard index >= 0 && index < menuPresets.count else { return }
                let selectedId = menuPresets[index].id
                onChange(selectedId == defaultId ? "" : selectedId)
            }
        )
        .frame(height: 24)
    }

    private func relabeledPresets(_ presets: [SummaryModelPreset], defaultModel: String?) -> [SummaryModelPreset] {
        guard let defaultModel else { return presets }
        return presets.map { preset in
            var label = preset.label.replacingOccurrences(of: " (default)", with: "")
            if preset.id == defaultModel {
                label += " (default)"
            }
            return SummaryModelPreset(id: preset.id, label: label)
        }
    }

    @ViewBuilder
    private func settingsModelTextField(currentModel: String, placeholder: String, onChange: @escaping (String) -> Void) -> some View {
        PastableTextField(
            text: currentModel,
            placeholder: placeholder,
            onChange: { value in
                onChange(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        )
        .frame(height: 22)
    }

    @ViewBuilder
    private var openRouterFreeModelMenu: some View {
        if isLoadingOpenRouterFreeModels {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading models")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GuesliTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else if !openRouterFreeModels.isEmpty {
            settingsModelMenu(
                currentModel: appState.config.openRouterModel,
                presets: openRouterFreeModels
            ) { val in controller.updateConfig { $0.openRouterModel = val } }
        } else {
            HStack(spacing: 8) {
                if let openRouterFreeModelsError {
                    Text(openRouterFreeModelsError)
                        .font(.system(size: 11))
                        .foregroundStyle(GuesliTheme.textTertiary)
                        .lineLimit(1)
                }
                Button("Load") {
                    loadOpenRouterFreeModels(force: true)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func loadOpenRouterFreeModelsIfNeeded() {
        guard openRouterFreeModels.isEmpty, !isLoadingOpenRouterFreeModels else { return }
        loadOpenRouterFreeModels(force: false)
    }

    private func loadOpenRouterFreeModels(force: Bool) {
        guard force || openRouterFreeModels.isEmpty else { return }
        isLoadingOpenRouterFreeModels = true
        openRouterFreeModelsError = nil

        Task {
            do {
                let url = URL(string: "https://openrouter.ai/api/v1/models?output_modalities=text")!
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200..<300).contains(httpResponse.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let catalog = try JSONDecoder().decode(OpenRouterModelCatalog.self, from: data)
                let presets = OpenRouterModelCatalogFilter.freeTextSummaryPresets(from: catalog.data)

                await MainActor.run {
                    openRouterFreeModels = presets
                    openRouterFreeModelsError = presets.isEmpty ? "No free text models found" : nil
                    isLoadingOpenRouterFreeModels = false
                }
            } catch {
                await MainActor.run {
                    openRouterFreeModels = []
                    openRouterFreeModelsError = "Could not load"
                    isLoadingOpenRouterFreeModels = false
                }
            }
        }
    }

    @ViewBuilder
    private func keyStatusRow(key: String) -> some View {
        HStack(spacing: 6) {
            Spacer()
            Circle()
                .fill(key.isEmpty ? GuesliTheme.textTertiary : GuesliTheme.success)
                .frame(width: 6, height: 6)
            Text(key.isEmpty ? "No API key configured" : "Key configured")
                .font(.system(size: 11))
                .foregroundStyle(key.isEmpty ? GuesliTheme.textTertiary : GuesliTheme.success)
        }
        .frame(minHeight: 20)
    }

    @ViewBuilder
    private func transcriptCleanupStatusView(_ status: TranscriptCleanupCredentialStatus) -> some View {
        let tint = status.isWarning ? GuesliTheme.transcribing : GuesliTheme.success
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Spacer(minLength: 0)
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(status.message)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: controlWidth, alignment: .trailing)
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private func transcriptCleanupWarningView(_ warning: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Spacer(minLength: 0)
            Circle()
                .fill(GuesliTheme.transcribing)
                .frame(width: 6, height: 6)
                .padding(.top, 4)
            Text(warning)
                .font(.system(size: 11))
                .foregroundStyle(GuesliTheme.transcribing)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .help(warning)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(warning, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GuesliTheme.textTertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Copy cleanup warning")
        }
        .frame(width: controlWidth, alignment: .trailing)
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = role == .destructive
        Button(action: action) {
            HStack(spacing: GuesliTheme.spacing8) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
            }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isDestructive ? GuesliTheme.recording : GuesliTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, GuesliTheme.spacing16)
                .padding(.vertical, GuesliTheme.spacing8)
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

    private func recordingSaveLabel(for policy: MeetingRecordingSavePolicy) -> String {
        switch policy {
        case .never:
            return "Never"
        case .prompt:
            return "Ask every time"
        case .always:
            return "Always"
        }
    }

    private func recordingSavePolicy(for label: String) -> MeetingRecordingSavePolicy? {
        let policy = MeetingRecordingSavePolicy.allCases.first { recordingSaveLabel(for: $0) == label }
        if policy == nil {
            assertionFailure("Unexpected recording save label: \(label)")
        }
        return policy
    }

    private func recordingFileFormatLabel(for format: MeetingRecordingFileFormat) -> String {
        format.displayName
    }

    private func recordingFileFormat(for label: String) -> MeetingRecordingFileFormat? {
        let format = MeetingRecordingFileFormat.allCases.first { recordingFileFormatLabel(for: $0) == label }
        if format == nil {
            assertionFailure("Unexpected recording file format label: \(label)")
        }
        return format
    }

    private func scheduledMeetingLeadTimeLabel(for leadTime: ScheduledMeetingNotificationLeadTime) -> String {
        switch leadTime {
        case .atStart:
            return "At start time"
        case .oneMinute:
            return "1 min before"
        case .threeMinutes:
            return "3 min before"
        case .fiveMinutes:
            return "5 min before"
        }
    }

    private func scheduledMeetingLeadTime(for label: String) -> ScheduledMeetingNotificationLeadTime? {
        let leadTime = ScheduledMeetingNotificationLeadTime.allCases.first {
            scheduledMeetingLeadTimeLabel(for: $0) == label
        }
        if leadTime == nil {
            assertionFailure("Unexpected scheduled meeting notification lead time label: \(label)")
        }
        return leadTime
    }

    private func meetingJoinDefaultAction(for label: String) -> MeetingJoinDefaultAction? {
        let action = MeetingJoinDefaultAction.allCases.first { $0.buttonLabel == label }
        if action == nil {
            assertionFailure("Unexpected meeting join default action label: \(label)")
        }
        return action
    }
}

// MARK: - Pastable Secure Field (NSViewRepresentable)

/// NSSecureTextField subclass that handles Cmd+V/C/X/A without needing a standard Edit menu.
/// Required because the app runs as .accessory (no menu bar), so key equivalents
/// don't route to text fields by default.
class EditableNSSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// NSPopUpButton wrapper that respects width constraints (SwiftUI Picker with .menu style ignores them).
struct FixedWidthPopUp: NSViewRepresentable {
    let selection: String
    let options: [String]
    /// Reports the selected index, avoiding label collision issues.
    let onSelectionIndex: (Int) -> Void

    init(selection: String, options: [String], onChange: @escaping (String) -> Void) {
        self.selection = selection
        self.options = options
        self.onSelectionIndex = { index in
            guard index >= 0 && index < options.count else { return }
            onChange(options[index])
        }
    }

    init(selection: String, options: [String], onSelectIndex: @escaping (Int) -> Void) {
        self.selection = selection
        self.options = options
        self.onSelectionIndex = onSelectIndex
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.removeAllItems()
        button.addItems(withTitles: options)
        button.selectItem(withTitle: selection)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let currentTitles = button.itemTitles
        if currentTitles != options {
            button.removeAllItems()
            button.addItems(withTitles: options)
        }
        if button.titleOfSelectedItem != selection {
            button.selectItem(withTitle: selection)
        }
        context.coordinator.onSelectionIndex = onSelectionIndex
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelectionIndex: onSelectionIndex) }

    class Coordinator: NSObject {
        var onSelectionIndex: (Int) -> Void
        init(onSelectionIndex: @escaping (Int) -> Void) { self.onSelectionIndex = onSelectionIndex }
        @objc func selectionChanged(_ sender: NSPopUpButton) {
            onSelectionIndex(sender.indexOfSelectedItem)
        }
    }
}

/// A text field that supports Cmd+V paste and masks the value when not focused.
struct PastableSecureField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> EditableNSSecureTextField {
        let field = EditableNSSecureTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: EditableNSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            onChange(field.stringValue)
        }
    }
}

/// Plain text field with the same accessory-app edit shortcuts as secure fields.
struct PastableTextField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> EditableNSTextField {
        let field = EditableNSTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: EditableNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            onChange(field.stringValue)
        }
    }
}

private extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        h = h.hasPrefix("#") ? String(h.dropFirst()) : h
        guard h.count == 6, let value = UInt64(h, radix: 16) else {
            self = .black; return
        }
        self = Color(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}

private extension NSColor {
    func toHexString() -> String? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent   * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent  * 255).rounded())
        return String(format: "%02x%02x%02x", r, g, b)
    }
}
