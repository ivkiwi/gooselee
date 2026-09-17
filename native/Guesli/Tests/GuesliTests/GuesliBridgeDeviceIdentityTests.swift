import CloudKit
import Foundation
import Testing
@testable import GuesliApp

@Suite("GuesliBridgeDeviceIdentity", .serialized, .guesliHermeticSupport)
struct GuesliBridgeDeviceIdentityTests {
    private enum DefaultsKey {
        static let localDeviceID = "guesli.sync.bridge.localDeviceID.v1"
        static let remoteDeviceID = "guesli.sync.bridge.remoteDeviceID.v1"
        static let remoteDeviceName = "guesli.sync.bridge.remoteDeviceName.v1"
        static let remoteDevicePlatform = "guesli.sync.bridge.remoteDevicePlatform.v1"
        static let remoteDeviceLastSeenAt = "guesli.sync.bridge.remoteDeviceLastSeenAt.v1"
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "com.guesli.tests.bridge-device-identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func bridgeRecord(
        deviceID: String? = "device-1",
        platform: String? = "iOS",
        deviceName: String? = "iPhone",
        appVersion: String? = "1.0",
        lastSeenAt: Date? = Date(timeIntervalSince1970: 1_770_000_000)
    ) -> CKRecord {
        let record = CKRecord(recordType: "GuesliBridgeDevice")
        if let deviceID {
            record["deviceID"] = deviceID as NSString
        }
        if let platform {
            record["platform"] = platform as NSString
        }
        if let deviceName {
            record["deviceName"] = deviceName as NSString
        }
        if let appVersion {
            record["appVersion"] = appVersion as NSString
        }
        if let lastSeenAt {
            record["lastSeenAt"] = lastSeenAt as NSDate
        }
        return record
    }

    @Test("shouldRefresh returns true with no timestamp")
    func shouldRefreshReturnsTrueWithNoTimestamp() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(GuesliBridgeDeviceIdentity.shouldRefresh(
            defaults: defaults,
            now: Date(timeIntervalSince1970: 1_770_000_000)
        ))
    }

    @Test("shouldRefresh uses a short interval before a remote device is known")
    func shouldRefreshUsesShortIntervalBeforeRemoteDeviceIsKnown() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        GuesliBridgeDeviceIdentity.markRefreshed(defaults: defaults, at: now)

        #expect(!GuesliBridgeDeviceIdentity.shouldRefresh(
            defaults: defaults,
            now: now.addingTimeInterval(59)
        ))
        #expect(GuesliBridgeDeviceIdentity.shouldRefresh(
            defaults: defaults,
            now: now.addingTimeInterval(60)
        ))
    }

    @Test("shouldRefresh can force refresh before the throttle expires")
    func shouldRefreshCanForceRefreshBeforeThrottleExpires() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        GuesliBridgeDeviceIdentity.markRefreshed(defaults: defaults, at: now)

        #expect(GuesliBridgeDeviceIdentity.shouldRefresh(
            defaults: defaults,
            now: now.addingTimeInterval(1),
            forceRefresh: true
        ))
    }

    @Test("failed refresh uses short retry backoff instead of success throttle")
    func failedRefreshUsesShortRetryBackoffInsteadOfSuccessThrottle() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        defaults.set("remote-iphone", forKey: DefaultsKey.remoteDeviceID)
        GuesliBridgeDeviceIdentity.markRefreshed(defaults: defaults, at: now.addingTimeInterval(-10))
        GuesliBridgeDeviceIdentity.markRefreshFailed(defaults: defaults, at: now)

        #expect(!GuesliBridgeDeviceIdentity.shouldRefresh(
            defaults: defaults,
            now: now.addingTimeInterval(14)
        ))
        #expect(GuesliBridgeDeviceIdentity.shouldRefresh(
            defaults: defaults,
            now: now.addingTimeInterval(15)
        ))
    }

    @Test("shouldRefresh returns false within one hour and true after one hour once linked")
    func shouldRefreshUsesOneHourIntervalOnceLinked() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        defaults.set("remote-iphone", forKey: DefaultsKey.remoteDeviceID)
        defaults.set("iOS", forKey: DefaultsKey.remoteDevicePlatform)
        GuesliBridgeDeviceIdentity.markRefreshed(defaults: defaults, at: now)

        #expect(!GuesliBridgeDeviceIdentity.shouldRefresh(
            defaults: defaults,
            now: now.addingTimeInterval(60 * 59)
        ))
        #expect(GuesliBridgeDeviceIdentity.shouldRefresh(
            defaults: defaults,
            now: now.addingTimeInterval(60 * 60)
        ))
    }

    @Test("shouldRefresh treats stale non-companion remote cache as unlinked")
    func shouldRefreshTreatsStaleNonCompanionRemoteCacheAsUnlinked() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        defaults.set("remote-mac", forKey: DefaultsKey.remoteDeviceID)
        defaults.set("macOS", forKey: DefaultsKey.remoteDevicePlatform)
        GuesliBridgeDeviceIdentity.markRefreshed(defaults: defaults, at: now)

        #expect(!GuesliBridgeDeviceIdentity.shouldRefresh(
            defaults: defaults,
            now: now.addingTimeInterval(59)
        ))
        #expect(GuesliBridgeDeviceIdentity.shouldRefresh(
            defaults: defaults,
            now: now.addingTimeInterval(60)
        ))
    }

    @Test("updateRemoteDevices with empty records clears remote keys")
    func updateRemoteDevicesWithEmptyRecordsClearsRemoteKeys() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let previousLastSeenAt = Date(timeIntervalSince1970: 1_770_000_000)
        defaults.set("remote-previous", forKey: DefaultsKey.remoteDeviceID)
        defaults.set("Previous iPhone", forKey: DefaultsKey.remoteDeviceName)
        defaults.set("iOS", forKey: DefaultsKey.remoteDevicePlatform)
        defaults.set(previousLastSeenAt, forKey: DefaultsKey.remoteDeviceLastSeenAt)

        GuesliBridgeDeviceIdentity.updateRemoteDevices(from: [], defaults: defaults)

        #expect(defaults.object(forKey: DefaultsKey.remoteDeviceID) == nil)
        #expect(defaults.object(forKey: DefaultsKey.remoteDeviceName) == nil)
        #expect(defaults.object(forKey: DefaultsKey.remoteDevicePlatform) == nil)
        #expect(defaults.object(forKey: DefaultsKey.remoteDeviceLastSeenAt) == nil)
    }

    @Test("updateRemoteDevices picks the most recent non-local record")
    func updateRemoteDevicesPicksMostRecentNonLocalRecord() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("local-mac", forKey: DefaultsKey.localDeviceID)
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let olderRemote = bridgeRecord(
            deviceID: "remote-old",
            deviceName: "Old iPhone",
            lastSeenAt: now.addingTimeInterval(-60)
        )
        let latestRemote = bridgeRecord(
            deviceID: "remote-new",
            platform: "iPadOS",
            deviceName: "iPad",
            lastSeenAt: now
        )
        let localRecord = bridgeRecord(
            deviceID: "local-mac",
            platform: "macOS",
            deviceName: "This Mac",
            lastSeenAt: now.addingTimeInterval(60)
        )

        GuesliBridgeDeviceIdentity.updateRemoteDevices(
            from: [olderRemote, latestRemote, localRecord],
            defaults: defaults
        )

        #expect(defaults.string(forKey: DefaultsKey.remoteDeviceID) == "remote-new")
        #expect(defaults.string(forKey: DefaultsKey.remoteDeviceName) == "iPad")
        #expect(defaults.string(forKey: DefaultsKey.remoteDevicePlatform) == "iPadOS")
        #expect(defaults.object(forKey: DefaultsKey.remoteDeviceLastSeenAt) as? Date == now)
    }

    @Test("updateRemoteDevices prefers companion devices over newer remote Macs")
    func updateRemoteDevicesPrefersCompanionDevicesOverNewerRemoteMacs() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("local-mac", forKey: DefaultsKey.localDeviceID)
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let iPhone = bridgeRecord(
            deviceID: "remote-iphone",
            platform: "iOS",
            deviceName: "picophone",
            lastSeenAt: now
        )
        let otherMac = bridgeRecord(
            deviceID: "remote-mac",
            platform: "macOS",
            deviceName: "Other MacBook",
            lastSeenAt: now.addingTimeInterval(60)
        )

        GuesliBridgeDeviceIdentity.updateRemoteDevices(
            from: [iPhone, otherMac],
            defaults: defaults
        )

        #expect(defaults.string(forKey: DefaultsKey.remoteDeviceID) == "remote-iphone")
        #expect(defaults.string(forKey: DefaultsKey.remoteDeviceName) == "picophone")
        #expect(defaults.string(forKey: DefaultsKey.remoteDevicePlatform) == "iOS")
    }

    @Test("updateRemoteDevices clears remote bridge when no companion exists")
    func updateRemoteDevicesClearsRemoteBridgeWhenNoCompanionExists() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("local-mac", forKey: DefaultsKey.localDeviceID)
        defaults.set("previous-iphone", forKey: DefaultsKey.remoteDeviceID)
        defaults.set("Previous iPhone", forKey: DefaultsKey.remoteDeviceName)
        defaults.set("iOS", forKey: DefaultsKey.remoteDevicePlatform)
        defaults.set(Date(timeIntervalSince1970: 1_769_999_000), forKey: DefaultsKey.remoteDeviceLastSeenAt)
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let olderMac = bridgeRecord(
            deviceID: "remote-mac-old",
            platform: "macOS",
            deviceName: "Old MacBook",
            lastSeenAt: now
        )
        let newerMac = bridgeRecord(
            deviceID: "remote-mac-new",
            platform: "macOS",
            deviceName: "New MacBook",
            lastSeenAt: now.addingTimeInterval(60)
        )

        GuesliBridgeDeviceIdentity.updateRemoteDevices(
            from: [olderMac, newerMac],
            defaults: defaults
        )

        #expect(defaults.object(forKey: DefaultsKey.remoteDeviceID) == nil)
        #expect(defaults.object(forKey: DefaultsKey.remoteDeviceName) == nil)
        #expect(defaults.object(forKey: DefaultsKey.remoteDevicePlatform) == nil)
        #expect(defaults.object(forKey: DefaultsKey.remoteDeviceLastSeenAt) == nil)
    }

    @Test("snapshot returns nil when required fields are missing")
    func snapshotReturnsNilWhenRequiredFieldsAreMissing() {
        #expect(GuesliBridgeDeviceIdentity.snapshot(from: bridgeRecord(deviceID: nil)) == nil)
        #expect(GuesliBridgeDeviceIdentity.snapshot(from: bridgeRecord(platform: nil)) == nil)
        #expect(GuesliBridgeDeviceIdentity.snapshot(from: bridgeRecord(deviceName: nil)) == nil)
        #expect(GuesliBridgeDeviceIdentity.snapshot(from: bridgeRecord(lastSeenAt: nil)) == nil)
    }

    @Test("local persists UUID across calls for the same defaults suite")
    func localPersistsUUIDAcrossCallsForSameDefaultsSuite() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = GuesliBridgeDeviceIdentity.local(defaults: defaults)
        let second = GuesliBridgeDeviceIdentity.local(defaults: defaults)

        #expect(first.deviceID == second.deviceID)
        #expect(UUID(uuidString: first.deviceID) != nil)
        #expect(defaults.string(forKey: DefaultsKey.localDeviceID) == first.deviceID)
    }
}

@Suite("ICloudBridgeAppState", .guesliHermeticSupport)
struct ICloudBridgeAppStateTests {
    @MainActor
    @Test("companion device name only returns iOS and iPadOS remotes")
    func companionDeviceNameOnlyReturnsCompanionPlatforms() {
        let state = AppState()

        state.iCloudBridgeRemoteDeviceName = "Pranav MacBook"
        state.iCloudBridgeRemoteDevicePlatform = "macOS"
        #expect(state.iCloudBridgeCompanionDeviceName == nil)

        state.iCloudBridgeRemoteDeviceName = "picophone"
        state.iCloudBridgeRemoteDevicePlatform = "iOS"
        #expect(state.iCloudBridgeCompanionDeviceName == "picophone")

        state.iCloudBridgeRemoteDeviceName = "iPad"
        state.iCloudBridgeRemoteDevicePlatform = " iPadOS "
        #expect(state.iCloudBridgeCompanionDeviceName == "iPad")
    }
}

@Suite("GuesliBridgeDeviceRefreshPolicy", .guesliHermeticSupport)
struct GuesliBridgeDeviceRefreshPolicyTests {
    @Test("user initiated sync forces bridge device refresh")
    func userInitiatedSyncForcesBridgeDeviceRefresh() {
        #expect(GuesliBridgeDeviceRefreshPolicy.shouldForceRefresh(
            userInitiated: true,
            bridgeActivationPending: false,
            bridgeDiscoveryTriggered: false,
            hasKnownCompanionDevice: true
        ))
    }

    @Test("pending bridge activation forces bridge device refresh")
    func pendingBridgeActivationForcesBridgeDeviceRefresh() {
        #expect(GuesliBridgeDeviceRefreshPolicy.shouldForceRefresh(
            userInitiated: false,
            bridgeActivationPending: true,
            bridgeDiscoveryTriggered: false,
            hasKnownCompanionDevice: true
        ))
    }

    @Test("app activation forces bridge device refresh until a companion device is known")
    func appActivationForcesRefreshUntilCompanionDeviceIsKnown() {
        #expect(GuesliBridgeDeviceRefreshPolicy.shouldForceRefresh(
            userInitiated: false,
            bridgeActivationPending: false,
            bridgeDiscoveryTriggered: true,
            hasKnownCompanionDevice: false
        ))
    }

    @Test("background sync uses throttle before a companion device is known")
    func backgroundSyncUsesThrottleBeforeCompanionDeviceIsKnown() {
        #expect(!GuesliBridgeDeviceRefreshPolicy.shouldForceRefresh(
            userInitiated: false,
            bridgeActivationPending: false,
            bridgeDiscoveryTriggered: false,
            hasKnownCompanionDevice: false
        ))
    }

    @Test("app activation uses throttle after companion device is known")
    func appActivationUsesThrottleAfterCompanionDeviceIsKnown() {
        #expect(!GuesliBridgeDeviceRefreshPolicy.shouldForceRefresh(
            userInitiated: false,
            bridgeActivationPending: false,
            bridgeDiscoveryTriggered: true,
            hasKnownCompanionDevice: true
        ))
    }

    @Test("app activation refreshes when cached remote is not a companion")
    func appActivationRefreshesWhenCachedRemoteIsNotACompanion() {
        #expect(GuesliBridgeDeviceRefreshPolicy.shouldForceRefresh(
            userInitiated: false,
            bridgeActivationPending: false,
            bridgeDiscoveryTriggered: true,
            hasKnownCompanionDevice: false
        ))
    }
}
