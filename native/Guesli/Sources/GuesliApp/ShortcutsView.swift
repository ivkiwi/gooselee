import SwiftUI
import AppKit
import GuesliCore

struct ShortcutsView: View {
    let appState: AppState
    let controller: GuesliController
    @State private var recordingTarget: ShortcutTarget?
    @State private var eventMonitor: Any?
    @State private var pendingModifierKeyCode: UInt16?
    @State private var dictationShortcutMessage: String?
    @State private var meetingRecordingShortcutMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuesliTheme.spacing24) {
                Text("Shortcuts")
                    .font(GuesliTheme.title1())
                    .foregroundStyle(GuesliTheme.textPrimary)

                Text("Choose your preferred shortcuts for dictation and meeting recording.")
                    .font(GuesliTheme.body())
                    .foregroundStyle(GuesliTheme.textSecondary)

                dictationShortcutSection

                meetingRecordingShortcutSection

                doubleTapSection

                resetButton
            }
            .padding(GuesliTheme.spacing32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private enum ShortcutTarget {
        case dictation
        case meetingRecording
    }

    private var dictationShortcutSection: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                    Text("Push to Talk")
                        .font(GuesliTheme.headline())
                        .foregroundStyle(GuesliTheme.textPrimary)
                    Text("Hold to record, release to transcribe")
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textSecondary)
                }
                Spacer()
                hotkeyBadge(appState.config.dictationHotkey)
            }

            Divider()
                .background(GuesliTheme.surfaceBorder)

            shortcutControls(
                target: .dictation,
                threshold: appState.config.hotkeyTriggerThresholdMS
            ) { value in
                controller.updateConfig { $0.hotkeyTriggerThresholdMS = value }
            }

            if let dictationShortcutMessage {
                shortcutMessage(dictationShortcutMessage)
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

    private var meetingRecordingShortcutSection: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                    Text("Meeting Recording")
                        .font(GuesliTheme.headline())
                        .foregroundStyle(GuesliTheme.textPrimary)
                    Text("Toggle meeting recording on/off")
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.config.enableMeetingRecordingHotkey },
                    set: { newValue in
                        let result = controller.updateMeetingRecordingHotkeyEnabled(newValue)
                        meetingRecordingShortcutMessage = result.message
                    }
                ))
                .toggleStyle(.switch)
                .tint(GuesliTheme.accent)
                .labelsHidden()
            }

            Divider()
                .background(GuesliTheme.surfaceBorder)

            shortcutControls(
                target: .meetingRecording,
                threshold: appState.config.meetingRecordingHotkeyTriggerThresholdMS,
                isEnabled: appState.config.enableMeetingRecordingHotkey
            ) { value in
                controller.updateConfig { $0.meetingRecordingHotkeyTriggerThresholdMS = value }
            }

            if let meetingRecordingShortcutMessage {
                shortcutMessage(meetingRecordingShortcutMessage)
            } else if appState.config.enableMeetingRecordingHotkey,
                      let warning = ShortcutHotkeyPolicy.commonGlobalShortcutWarning(for: appState.config.meetingRecordingHotkey) {
                shortcutMessage(warning)
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

    private func hotkeyBadge(_ hotkey: HotkeyConfig) -> some View {
        Text(hotkey.displayLabel)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(GuesliTheme.textPrimary)
            .padding(.horizontal, GuesliTheme.spacing12)
            .padding(.vertical, GuesliTheme.spacing4)
            .background(GuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                    .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .help(hotkey.label)
    }

    private func shortcutControls(
        target: ShortcutTarget,
        threshold: Int,
        isEnabled: Bool = true,
        onThresholdChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: GuesliTheme.spacing12) {
            hotkeyBadge(hotkey(for: target))
            changeButton(for: target)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.55)
            Spacer(minLength: GuesliTheme.spacing16)
            if isEnabled {
                thresholdInput(
                    value: threshold,
                    onChange: onThresholdChange
                )
            }
        }
    }

    private func hotkey(for target: ShortcutTarget) -> HotkeyConfig {
        switch target {
        case .dictation:
            return appState.config.dictationHotkey
        case .meetingRecording:
            return appState.config.meetingRecordingHotkey
        }
    }

    private func thresholdInput(value: Int, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: GuesliTheme.spacing8) {
            Text("Hold")
                .font(GuesliTheme.caption())
                .foregroundStyle(GuesliTheme.textSecondary)

            TextField(
                "",
                value: Binding(
                    get: { HotkeyTriggerTiming.clampedMilliseconds(value) },
                    set: { onChange(HotkeyTriggerTiming.clampedMilliseconds($0)) }
                ),
                format: .number
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(GuesliTheme.textPrimary)
            .multilineTextAlignment(.trailing)
            .frame(width: 64)
            .padding(.horizontal, GuesliTheme.spacing8)
            .padding(.vertical, GuesliTheme.spacing4)
            .background(GuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                    .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
            )

            Text("ms")
                .font(GuesliTheme.caption())
                .foregroundStyle(GuesliTheme.textSecondary)
        }
        .help("Hold threshold: \(HotkeyTriggerTiming.minThresholdMilliseconds)-\(HotkeyTriggerTiming.maxThresholdMilliseconds) ms")
    }

    private func shortcutMessage(_ message: String) -> some View {
        Text(message)
            .font(GuesliTheme.caption())
            .foregroundStyle(GuesliTheme.transcribing)
    }

    private func changeButton(for target: ShortcutTarget) -> some View {
        Button {
            if recordingTarget == target {
                stopRecording()
            } else {
                startRecording(target)
            }
        } label: {
            Text(recordingTarget == target ? recordingPrompt(for: target) : "Change Shortcut")
                .font(GuesliTheme.body())
                .foregroundStyle(recordingTarget == target ? GuesliTheme.accent : GuesliTheme.textPrimary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, GuesliTheme.spacing12)
        .padding(.vertical, GuesliTheme.spacing8)
        .background(recordingTarget == target ? GuesliTheme.accentSubtle : GuesliTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                .strokeBorder(recordingTarget == target ? GuesliTheme.accent.opacity(0.3) : GuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func recordingPrompt(for target: ShortcutTarget) -> String {
        switch target {
        case .meetingRecording:
            return "Press a key or modifier..."
        case .dictation:
            return "Press a modifier key..."
        }
    }

    private var doubleTapSection: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                    Text("Hands-Free Mode")
                        .font(GuesliTheme.headline())
                        .foregroundStyle(GuesliTheme.textPrimary)
                    Text("Double-tap dictation to start, tap again to stop")
                        .font(GuesliTheme.caption())
                        .foregroundStyle(GuesliTheme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.config.enableDoubleTapDictation },
                    set: { newValue in
                        controller.updateConfig { $0.enableDoubleTapDictation = newValue }
                    }
                ))
                .toggleStyle(.switch)
                .tint(GuesliTheme.accent)
                .labelsHidden()
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

    private var resetButton: some View {
        Button {
            controller.resetShortcutDefaults()
            dictationShortcutMessage = nil
            meetingRecordingShortcutMessage = nil
        } label: {
            Text("Reset to Defaults")
                .font(GuesliTheme.body())
                .foregroundStyle(GuesliTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(
            appState.config.dictationHotkey == .default
                && appState.config.meetingRecordingHotkey == .meetingRecordingDefault
                && !appState.config.enableMeetingRecordingHotkey
                && appState.config.hotkeyTriggerThresholdMS == HotkeyTriggerTiming.defaultThresholdMilliseconds
                && appState.config.meetingRecordingHotkeyTriggerThresholdMS == HotkeyTriggerTiming.defaultMeetingThresholdMilliseconds
        )
    }

    private func startRecording(_ target: ShortcutTarget) {
        stopRecording()
        clearShortcutMessage(for: target)
        pendingModifierKeyCode = nil
        recordingTarget = target
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [self] event in
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    stopRecording()
                    return nil
                }
                let mods = HotkeyConfig.supportedCombinationModifiers(from: event.modifierFlags)
                let hasModifiers = mods.contains(.command) || mods.contains(.control)
                    || mods.contains(.option)
                guard target == .meetingRecording,
                      hasModifiers,
                      HotkeyConfig.letterLabel(for: event.keyCode) != nil else {
                    return event
                }
                pendingModifierKeyCode = nil
                let newConfig = HotkeyConfig.combination(modifiers: mods, keyCode: event.keyCode)
                commitShortcut(newConfig, for: target)
                return nil
            }

            let keyCode = event.keyCode
            guard HotkeyConfig.label(for: keyCode) != nil else { return event }
            let flags = event.modifierFlags
            let isDown: Bool
            switch keyCode {
            case 55, 54: isDown = flags.contains(.command)
            case 56, 60: isDown = flags.contains(.shift)
            case 58, 61: isDown = flags.contains(.option)
            case 59, 62: isDown = flags.contains(.control)
            default: isDown = false
            }
            if isDown {
                pendingModifierKeyCode = keyCode
            } else if keyCode == pendingModifierKeyCode {
                let newConfig = HotkeyConfig(keyCode: keyCode, label: HotkeyConfig.label(for: keyCode)!)
                pendingModifierKeyCode = nil
                commitShortcut(newConfig, for: target)
            }
            return event
        }
    }

    private func commitShortcut(_ config: HotkeyConfig, for target: ShortcutTarget) {
        let result: ShortcutHotkeyUpdateResult
        switch target {
        case .dictation:
            result = controller.updateDictationHotkey(config)
        case .meetingRecording:
            result = controller.updateMeetingRecordingHotkey(config)
        }
        setShortcutMessage(result.message, for: target)
        stopRecording()
    }

    private func clearShortcutMessage(for target: ShortcutTarget) {
        setShortcutMessage(nil, for: target)
    }

    private func setShortcutMessage(_ message: String?, for target: ShortcutTarget) {
        switch target {
        case .dictation:
            dictationShortcutMessage = message
            if message == nil { meetingRecordingShortcutMessage = nil }
        case .meetingRecording:
            meetingRecordingShortcutMessage = message
            if message == nil { dictationShortcutMessage = nil }
        }
    }

    private func stopRecording() {
        recordingTarget = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
