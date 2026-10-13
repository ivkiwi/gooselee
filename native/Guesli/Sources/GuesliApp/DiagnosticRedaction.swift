import CryptoKit
import Foundation

/// Opaque log token for meeting identities, so logs never carry room URLs or titles.
enum DiagnosticRedaction {
    /// Per-launch salt: a bare hash of a short Meet code could be brute-forced offline.
    private static let salt = UUID().uuidString

    /// Stable within one app run, so log lines about the same meeting still correlate.
    static func opaqueID(_ value: String) -> String {
        let digest = SHA256.hash(data: Data((salt + value).utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
