import Foundation

private final class GuesliTestProcessFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false

    func enable() {
        lock.lock()
        enabled = true
        lock.unlock()
    }

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }
}

public enum GuesliPaths {
    @TaskLocal public static var testSupportDirectoryRoot: URL?
    private static let testProcessFlag = GuesliTestProcessFlag()

    public static func markRunningTestsForCurrentProcess() {
        testProcessFlag.enable()
    }

    public static func defaultSupportDirectoryURL(appName: String = "Guesli", fileManager: FileManager = .default) -> URL {
        if let testSupportDirectoryRoot {
            return testSupportDirectoryRoot
                .appendingPathComponent(appName, isDirectory: true)
                .standardizedFileURL
        }
        if isRunningTests {
            let root = ProcessInfo.processInfo.environment["GUESLI_TEST_SUPPORT_ROOT"]
                .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
                ?? fileManager.temporaryDirectory
                    .appendingPathComponent("guesli-test-support-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            return root
                .appendingPathComponent(appName, isDirectory: true)
                .standardizedFileURL
        }
        return userSupportDirectoryURL(appName: appName, fileManager: fileManager)
    }

    public static func userSupportDirectoryURL(appName: String = "Guesli", fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
            .standardizedFileURL
    }

    public static func defaultDatabaseURL(appName: String = "Guesli") -> URL {
        databaseURL(supportDirectory: defaultSupportDirectoryURL(appName: appName))
    }

    public static func databaseURL(supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent("guesli.db")
    }

    public static func migrateHistoricalCacheDirectoryIfNeeded(
        homeDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let cacheRoot = (homeDirectory ?? fileManager.homeDirectoryForCurrentUser)
            .appendingPathComponent(".cache", isDirectory: true)
        let currentURL = cacheRoot.appendingPathComponent("guesli", isDirectory: true)
        let historicalURL = cacheRoot.appendingPathComponent("muesli", isDirectory: true)
        guard fileManager.fileExists(atPath: historicalURL.path) else { return }
        guard !fileManager.fileExists(atPath: currentURL.path) else { return }
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try fileManager.moveItem(at: historicalURL, to: currentURL)
    }

    @discardableResult
    public static func migrateHistoricalDatabaseNameIfNeeded(
        supportDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let currentURL = databaseURL(supportDirectory: supportDirectory)
        guard !fileManager.fileExists(atPath: currentURL.path) else {
            return currentURL
        }

        let historicalURL = supportDirectory.appendingPathComponent("muesli.db")
        guard fileManager.fileExists(atPath: historicalURL.path) else {
            return currentURL
        }

        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        var movedPairs: [(source: URL, destination: URL)] = []
        do {
            for suffix in ["-wal", "-shm", ""] {
                let source = URL(fileURLWithPath: historicalURL.path + suffix)
                let destination = URL(fileURLWithPath: currentURL.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.moveItem(at: source, to: destination)
                movedPairs.append((source, destination))
            }
        } catch {
            for pair in movedPairs.reversed() {
                try? fileManager.moveItem(at: pair.destination, to: pair.source)
            }
            throw error
        }
        return currentURL
    }

    public static func preconditionSafeForTestWrite(
        _ url: URL,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        guard isRunningTests else { return }
        let path = url.standardizedFileURL.path
        let supportPath = userSupportDirectoryURL(appName: "Guesli").path
        if path == supportPath || path.hasPrefix(supportPath + "/") {
            preconditionFailure(
                "Test attempted to write real user support directory: \(path)",
                file: file,
                line: line
            )
        }
    }

    public static var isRunningTests: Bool {
        if testProcessFlag.isEnabled {
            return true
        }
        let environment = ProcessInfo.processInfo.environment
        if environment["GUESLI_TEST_SUPPORT_ROOT"]?.isEmpty == false {
            return true
        }
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestSessionIdentifier"] != nil {
            return true
        }
        if Bundle.main.bundlePath.hasSuffix(".xctest") {
            return true
        }
        return false
    }
}

public enum GuesliNotifications {
    public static let dataDidChange = Notification.Name("com.guesli.dataChanged")

    public static func postDataDidChange() {
        DistributedNotificationCenter.default().post(name: dataDidChange, object: nil)
    }
}
