import Testing
@testable import MuesliNativeApp

@Suite("Apple cloud capabilities")
struct AppleCloudCapabilitiesTests {
    @Test("local-only signing exposes no cloud runtime")
    func localOnlySigning() {
        let capabilities = AppleCloudCapabilities(entitlements: [:])

        #expect(!capabilities.canUseCloudKit)
        #expect(!capabilities.canReceiveRemoteNotifications)
    }

    @Test("CloudKit requires both a container and the CloudKit service")
    func cloudKitRequiresCompleteEntitlements() {
        let missingService = AppleCloudCapabilities(entitlements: [
            "com.apple.developer.icloud-container-identifiers": ["iCloud.com.mueslihq.muesli"],
        ])
        let complete = AppleCloudCapabilities(entitlements: [
            "com.apple.developer.icloud-container-identifiers": ["iCloud.com.mueslihq.muesli"],
            "com.apple.developer.icloud-services": ["CloudKit"],
        ])

        #expect(!missingService.canUseCloudKit)
        #expect(complete.canUseCloudKit)
    }

    @Test("APNs is gated independently from CloudKit")
    func pushIsIndependent() {
        let capabilities = AppleCloudCapabilities(entitlements: [
            "com.apple.developer.aps-environment": "production",
        ])

        #expect(!capabilities.canUseCloudKit)
        #expect(capabilities.canReceiveRemoteNotifications)
    }
}
