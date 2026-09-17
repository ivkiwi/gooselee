import AudioToolbox

/// Plays subtle system sounds for dictation lifecycle events.
/// Sounds are skipped when `soundEnabled` is false.
@MainActor
enum SoundController {
    static func prewarmLifecycleSounds() {
        SystemSoundPlayer.prewarm(names: ["Tink", "Purr", "Glass"])
    }

    static func playDictationStart(enabled: Bool) {
        guard enabled else { return }
        SystemSoundPlayer.play(named: "Tink")
    }

    static func playDictationInsert(enabled: Bool) {
        guard enabled else { return }
        SystemSoundPlayer.play(named: "Purr")
    }

    static func playModelReady(enabled: Bool) {
        guard enabled else { return }
        SystemSoundPlayer.play(named: "Glass")
    }

}

private enum SystemSoundPlayer {
    private static let queue = DispatchQueue(label: "com.guesli.system-sound-player", qos: .userInitiated)
    private static var soundIDs: [String: SystemSoundID] = [:]
    private static var cleanupRegistered = false

    static func prewarm(names: [String]) {
        queue.async {
            registerCleanupIfNeeded()
            for name in names {
                _ = loadSoundID(named: name)
            }
        }
    }

    static func play(named name: String) {
        queue.async {
            registerCleanupIfNeeded()
            guard let soundID = loadSoundID(named: name) else { return }
            AudioServicesPlaySystemSound(soundID)
        }
    }

    private static func registerCleanupIfNeeded() {
        guard !cleanupRegistered else { return }
        cleanupRegistered = true
        atexit {
            SystemSoundPlayer.disposeCachedSoundsBestEffort()
        }
    }

    private static func disposeCachedSoundsBestEffort() {
        queue.sync {
            for soundID in soundIDs.values {
                AudioServicesDisposeSystemSoundID(soundID)
            }
            soundIDs.removeAll()
        }
    }

    private static func loadSoundID(named name: String) -> SystemSoundID? {
        if let soundID = soundIDs[name] {
            return soundID
        }
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var soundID: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        guard status == kAudioServicesNoError else {
            fputs("[guesli-native] failed to load system sound \(name): \(status)\n", stderr)
            return nil
        }
        soundIDs[name] = soundID
        return soundID
    }
}
