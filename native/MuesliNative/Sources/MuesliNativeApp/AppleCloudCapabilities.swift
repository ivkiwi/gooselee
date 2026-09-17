import Foundation
import Security

struct AppleCloudCapabilities: Equatable, Sendable {
    let canUseCloudKit: Bool
    let canReceiveRemoteNotifications: Bool

    init(entitlements: [String: Any]) {
        let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String]
        let services = entitlements["com.apple.developer.icloud-services"] as? [String]
        let pushEnvironment = entitlements["com.apple.developer.aps-environment"] as? String
            ?? entitlements["aps-environment"] as? String

        canUseCloudKit = !(containers ?? []).isEmpty && (services ?? []).contains("CloudKit")
        canReceiveRemoteNotifications = !(pushEnvironment ?? "").isEmpty
    }

    init(canUseCloudKit: Bool, canReceiveRemoteNotifications: Bool) {
        self.canUseCloudKit = canUseCloudKit
        self.canReceiveRemoteNotifications = canReceiveRemoteNotifications
    }

    static var current: AppleCloudCapabilities {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return AppleCloudCapabilities(canUseCloudKit: false, canReceiveRemoteNotifications: false)
        }

        func entitlement(_ key: String) -> Any? {
            SecTaskCopyValueForEntitlement(task, key as CFString, nil)
        }

        return AppleCloudCapabilities(entitlements: [
            "com.apple.developer.icloud-container-identifiers": entitlement("com.apple.developer.icloud-container-identifiers") as Any,
            "com.apple.developer.icloud-services": entitlement("com.apple.developer.icloud-services") as Any,
            "com.apple.developer.aps-environment": entitlement("com.apple.developer.aps-environment") as Any,
            "aps-environment": entitlement("aps-environment") as Any,
        ])
    }
}
