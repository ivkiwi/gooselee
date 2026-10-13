import Foundation

struct DictationLogMetadata: Encodable {
    let characterCount: Int

    init(text: String) {
        characterCount = text.count
    }

    var summary: String { "chars=\(characterCount)" }
}
