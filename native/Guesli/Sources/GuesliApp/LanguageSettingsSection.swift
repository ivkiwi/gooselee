import Foundation
import SwiftUI

/// Per-app interface language, stored as the standard `AppleLanguages` override in the app's own defaults domain.
enum AppLanguageChoice: String, CaseIterable, Identifiable {
    case system
    case english
    case russian

    static let defaultsKey = "AppleLanguages"

    var id: String { rawValue }

    /// Value to write to `AppleLanguages`; nil means remove the override and follow macOS.
    var appleLanguages: [String]? {
        switch self {
        case .system: return nil
        case .english: return ["en"]
        case .russian: return ["ru"]
        }
    }

    init(appleLanguages: [String]?) {
        switch appleLanguages?.first?.lowercased() {
        case let code? where code == "en" || code.hasPrefix("en-"): self = .english
        case let code? where code == "ru" || code.hasPrefix("ru-"): self = .russian
        default: self = .system
        }
    }

    /// Reads only the app domain: `UserDefaults.standard` also sees the global system language list.
    static func current(defaults: UserDefaults = .standard, bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> AppLanguageChoice {
        guard let bundleIdentifier else { return .system }
        let override = defaults.persistentDomain(forName: bundleIdentifier)?[defaultsKey] as? [String]
        return AppLanguageChoice(appleLanguages: override)
    }

    func apply(defaults: UserDefaults = .standard) {
        if let appleLanguages {
            defaults.set(appleLanguages, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }

    /// The language this process launched with; captured on first access, before any change.
    static let atLaunch = AppLanguageChoice.current()
}

struct LanguageSettingsSection: View {
    let appState: AppState
    let controller: GuesliController
    @State private var selection = AppLanguageChoice.current()

    var body: some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
            Text("Language")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GuesliTheme.textTertiary)
                .textCase(.uppercase)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: GuesliTheme.spacing8) {
                HStack(alignment: .center) {
                    Text("Interface")
                        .font(GuesliTheme.body())
                        .foregroundStyle(GuesliTheme.textPrimary)
                    Spacer(minLength: 20)
                    Picker("Interface", selection: $selection) {
                        Text("System").tag(AppLanguageChoice.system)
                        // Language names stay in their own language.
                        Text(verbatim: "English").tag(AppLanguageChoice.english)
                        Text(verbatim: "Русский").tag(AppLanguageChoice.russian)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }

                if selection != AppLanguageChoice.atLaunch {
                    restartRow
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
        .onChange(of: selection) { _, newValue in
            newValue.apply()
        }
    }

    @ViewBuilder
    private var restartRow: some View {
        HStack(spacing: GuesliTheme.spacing8) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GuesliTheme.accent)
            // Restarting would cut the meeting recording, so it waits until recording stops.
            if appState.isMeetingRecording {
                Text("Stop the meeting recording to restart.")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textTertiary)
            } else {
                Text("Restart GooseLee to apply.")
                    .font(GuesliTheme.caption())
                    .foregroundStyle(GuesliTheme.textTertiary)
                Spacer(minLength: GuesliTheme.spacing12)
                Button("Restart") {
                    guard !controller.isMeetingRecording() else { return }
                    controller.relaunchApp()
                }
            }
        }
    }
}
