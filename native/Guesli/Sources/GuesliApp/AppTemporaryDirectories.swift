import Foundation

enum AppTemporaryDirectories {
    static let systemAudio = "guesli-system-audio"
    static let meetingRecordings = "guesli-meeting-recordings"
    static let nativeRecordings = "guesli-native"
    static let audioImports = "guesli-import"
    static let wavTemp = "guesli-wav-temp"
    static let meetingMic = "guesli-meeting-mic"
    static let meetingMicAudioQueue = "guesli-meeting-mic-audioqueue"
    static let meetingMicAppScopedFallback = "guesli-meeting-mic-app-scoped-fallback"
    static let meetingMicChunks = "guesli-meeting-mic-chunks"
    static let meetingSystemChunks = "guesli-meeting-system-chunks"
    static let meetingMicRepair = "guesli-meeting-mic-repair"
    static let meetingRetranscription = "guesli-meeting-retranscription"
    static let nativeDictation = "guesli-native-dictation"
    static let nativeDictationStreaming = "guesli-native-dictation-streaming"
    static let legacyImportPrefix = "legacy-guesli-import-"
    static let launchSweepMinimumAge: TimeInterval = 60 * 60
    static let meetingRecordingLaunchSweepMinimumAge: TimeInterval = 24 * 60 * 60

    static let launchSweepDirectoryNames = [
        systemAudio,
        meetingRecordings,
        nativeRecordings,
        audioImports,
        wavTemp,
        meetingMic,
        meetingMicAudioQueue,
        meetingMicAppScopedFallback,
        meetingMicChunks,
        meetingSystemChunks,
        meetingMicRepair,
        meetingRetranscription,
        nativeDictation,
        nativeDictationStreaming,
    ]

    private static let launchSweepDirectoryPrefixes = [
        legacyImportPrefix,
    ]

    struct SweepResult: Equatable {
        let removedEntryCount: Int
    }

    static func url(
        named directoryName: String,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> URL {
        temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func legacyImportDirectoryName(id: UUID = UUID()) -> String {
        "\(legacyImportPrefix)\(id.uuidString)"
    }

    @discardableResult
    static func sweepAtLaunch(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        now: Date = Date(),
        minimumAge: TimeInterval = launchSweepMinimumAge,
        logger: ((String) -> Void)? = { fputs("\($0)\n", stderr) }
    ) -> SweepResult {
        var removedEntryCount = 0

        for directoryName in launchSweepDirectoryNames {
            let directoryMinimumAge = directoryName == meetingRecordings
                ? max(minimumAge, meetingRecordingLaunchSweepMinimumAge)
                : minimumAge
            let cutoff = now.addingTimeInterval(-max(0, directoryMinimumAge))
            let directoryURL = url(named: directoryName, temporaryDirectory: temporaryDirectory)
            removedEntryCount += removeOldContents(
                in: directoryURL,
                olderThan: cutoff,
                fileManager: fileManager
            )
        }

        let prefixedCutoff = now.addingTimeInterval(-max(0, minimumAge))
        removedEntryCount += removeOldPrefixedDirectories(
            in: temporaryDirectory,
            olderThan: prefixedCutoff,
            fileManager: fileManager
        )

        if removedEntryCount > 0 {
            logger?(
                "[guesli-native] cleaned up \(removedEntryCount) stale temp item\(removedEntryCount == 1 ? "" : "s")"
            )
        }
        return SweepResult(removedEntryCount: removedEntryCount)
    }

    private static func removeOldContents(
        in directoryURL: URL,
        olderThan cutoff: Date,
        fileManager: FileManager
    ) -> Int {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]
        ) else {
            return 0
        }

        var removed = 0
        for entry in entries where isOlder(entry, than: cutoff) {
            do {
                try fileManager.removeItem(at: entry)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
    }

    private static func removeOldPrefixedDirectories(
        in temporaryDirectory: URL,
        olderThan cutoff: Date,
        fileManager: FileManager
    ) -> Int {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isDirectoryKey]
        ) else {
            return 0
        }

        var removed = 0
        for entry in entries {
            guard launchSweepDirectoryPrefixes.contains(where: { entry.lastPathComponent.hasPrefix($0) }),
                  isDirectory(entry),
                  isOlder(entry, than: cutoff) else {
                continue
            }
            do {
                try fileManager.removeItem(at: entry)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func isOlder(_ url: URL, than cutoff: Date) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]),
              let date = values.contentModificationDate ?? values.creationDate else {
            return false
        }
        return date < cutoff
    }
}
