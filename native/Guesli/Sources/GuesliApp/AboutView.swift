import SwiftUI
import GuesliCore

struct AboutView: View {
    let appState: AppState

    private let githubURL = "https://github.com/ivkiwi/gooselee"

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        return "v\(v)"
    }

    private var appDataPath: String {
        AppIdentity.supportDirectoryURL.path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuesliTheme.spacing32) {
                Text("About")
                    .font(GuesliTheme.title1())
                    .foregroundStyle(GuesliTheme.textPrimary)

                if let banner = updateBanner {
                    updateBannerView(banner)
                }

                // MARK: - App Info
                sectionHeader("App Info")
                aboutCard {
                    aboutRow("Version") {
                        Text(version)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(GuesliTheme.textPrimary)
                    }

                    Divider().background(GuesliTheme.surfaceBorder)

                    aboutRow("Updates") {
                        Text(updateRowGuidance)
                            .font(GuesliTheme.callout())
                            .foregroundStyle(GuesliTheme.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // MARK: - Support
                sectionHeader("Support")
                aboutCard {
                    aboutRow("Source Code") {
                        actionButton("View on GitHub", icon: "arrow.up.right.square") {
                            if let url = URL(string: githubURL) { NSWorkspace.shared.open(url) }
                        }
                    }
                }

                // MARK: - Data
                sectionHeader("Data")
                aboutCard {
                    VStack(alignment: .leading, spacing: GuesliTheme.spacing12) {
                        Text("App Data Directory")
                            .font(GuesliTheme.body())
                            .foregroundStyle(GuesliTheme.textPrimary)

                        HStack {
                            Text(appDataPath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(GuesliTheme.textTertiary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            actionButton("Open", icon: "folder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appDataPath)
                            }
                        }
                    }
                }

                // MARK: - Acknowledgements
                sectionHeader("Acknowledgements")
                aboutCard {
                    acknowledgement(
                        name: "FluidAudio by FluidInference",
                        description: "CoreML speech stack powering Parakeet, Nemotron, Silero VAD, and speaker diarization on Apple Silicon."
                    )
                    Divider().background(GuesliTheme.surfaceBorder)
                    acknowledgement(
                        name: "LocalVQE by localai-org",
                        description: "On-device acoustic echo cancellation powering cleaner meeting transcription."
                    )
                }

                Spacer(minLength: GuesliTheme.spacing32)
            }
            .padding(GuesliTheme.spacing32)
        }
        .background(GuesliTheme.backgroundBase)
    }

    // MARK: - Components

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(GuesliTheme.textTertiary)
            .textCase(.uppercase)
            .padding(.leading, 2)
    }

    @ViewBuilder
    private func aboutCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(GuesliTheme.spacing20)
        .background(GuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium)
                .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private struct UpdateBanner {
        let icon: String
        let title: String
        let message: String
        let tint: Color
    }

    private var updateRowGuidance: String {
        switch appState.sparkleUpdateStatus {
        case .available:
            return "Use the menu bar icon > Check for Updates..."
        case .downloaded:
            return "Use the menu bar updater to finish installation."
        case .checking, .busy, .installing:
            return "Checking..."
        case .failed:
            return "Use the menu bar icon > Check for Updates..."
        case .idle, .upToDate, .disabled:
            return "Use the menu bar icon > Check for Updates..."
        }
    }

    private var updateBanner: UpdateBanner? {
        switch appState.sparkleUpdateStatus {
        case .idle:
            return nil
        case .checking:
            return UpdateBanner(
                icon: "arrow.triangle.2.circlepath",
                title: "Checking for updates",
                message: "GooseLee is checking the appcast for the latest version.",
                tint: GuesliTheme.transcribing
            )
        case .busy(let message):
            return UpdateBanner(
                icon: "clock.arrow.circlepath",
                title: "Updater is busy",
                message: message,
                tint: GuesliTheme.transcribing
            )
        case .available(let version):
            return UpdateBanner(
                icon: "exclamationmark.triangle.fill",
                title: "GooseLee \(version) is available",
                message: "An update is available. Use the menu bar icon > Check for Updates... to open the updater.",
                tint: GuesliTheme.transcribing
            )
        case .downloaded(let version):
            return UpdateBanner(
                icon: "exclamationmark.triangle.fill",
                title: "GooseLee \(version) is ready to install",
                message: "The update is downloaded. Use the menu bar updater to finish installation.",
                tint: GuesliTheme.transcribing
            )
        case .installing(let version):
            return UpdateBanner(
                icon: "arrow.down.circle.fill",
                title: "Installing GooseLee \(version)",
                message: "Sparkle is preparing the update. GooseLee may relaunch when installation finishes.",
                tint: GuesliTheme.transcribing
            )
        case .upToDate:
            return UpdateBanner(
                icon: "checkmark.circle.fill",
                title: "GooseLee is up to date",
                message: "No newer version was found in the appcast.",
                tint: GuesliTheme.success
            )
        case .disabled(let message):
            return UpdateBanner(
                icon: "minus.circle.fill",
                title: "Updates are disabled",
                message: message,
                tint: GuesliTheme.textTertiary
            )
        case .failed(let message):
            return UpdateBanner(
                icon: "xmark.octagon.fill",
                title: "Update check failed",
                message: "\(message) Use the menu bar icon > Check for Updates... to try again.",
                tint: GuesliTheme.recording
            )
        }
    }

    @ViewBuilder
    private func updateBannerView(_ banner: UpdateBanner) -> some View {
        HStack(alignment: .top, spacing: GuesliTheme.spacing12) {
            Image(systemName: banner.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(banner.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
                Text(banner.title)
                    .font(GuesliTheme.headline())
                    .foregroundStyle(GuesliTheme.textPrimary)
                Text(banner.message)
                    .font(GuesliTheme.callout())
                    .foregroundStyle(GuesliTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: GuesliTheme.spacing16)
        }
        .padding(GuesliTheme.spacing16)
        .background(banner.tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: GuesliTheme.cornerMedium)
                .strokeBorder(banner.tint.opacity(0.45), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func aboutRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(GuesliTheme.body())
                .foregroundStyle(GuesliTheme.textPrimary)
            Spacer()
            control()
        }
        .padding(.vertical, GuesliTheme.spacing8)
    }

    @ViewBuilder
    private func acknowledgement(name: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: GuesliTheme.spacing4) {
            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GuesliTheme.textPrimary)
            Text(description)
                .font(GuesliTheme.callout())
                .foregroundStyle(GuesliTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, GuesliTheme.spacing8)
    }

    @ViewBuilder
    private func actionButton(_ title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(GuesliTheme.textPrimary)
            .padding(.horizontal, GuesliTheme.spacing16)
            .padding(.vertical, GuesliTheme.spacing8)
            .background(GuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: GuesliTheme.cornerSmall)
                    .strokeBorder(GuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
