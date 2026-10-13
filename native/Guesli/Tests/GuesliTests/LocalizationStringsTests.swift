import Foundation
import Testing

@Suite("Localization strings fragments", .guesliHermeticSupport)
struct LocalizationStringsTests {
    @Test("every ru fragment parses, has unique keys, non-empty values and matching format specifiers")
    func fragmentsAreValid() throws {
        let fragments = try Self.fragmentURLs()
        #expect(!fragments.isEmpty)

        var keyOwners: [String: String] = [:]
        for url in fragments {
            let name = url.lastPathComponent
            let data = try Data(contentsOf: url)
            let text = try #require(String(data: data, encoding: .utf8), "\(name) is not UTF-8")

            // PropertyListSerialization keeps the last duplicate silently, so scan raw lines for keys.
            for key in Self.rawKeys(in: text) {
                if let owner = keyOwners[key] {
                    Issue.record("duplicate key \"\(key)\" in \(name), first seen in \(owner)")
                } else {
                    keyOwners[key] = name
                }
            }

            let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
            let table = try #require(plist as? [String: String], "\(name) is not a strings table")
            for (key, value) in table {
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "empty value for \"\(key)\" in \(name)")
                #expect(
                    Self.formatSpecifiers(in: key) == Self.formatSpecifiers(in: value),
                    "format specifiers differ for \"\(key)\" in \(name)"
                )
            }
        }
    }

    @Test("stringsdict parses, every plural has one/few/many/other, and its keys are not repeated in fragments")
    func pluralsAreValid() throws {
        let data = try Data(contentsOf: Self.directory.appendingPathComponent("Localizable.stringsdict"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entries = try #require(plist as? [String: [String: Any]], "Localizable.stringsdict is not a dictionary of entries")
        #expect(!entries.isEmpty)

        var fragmentKeys: Set<String> = []
        for url in try Self.fragmentURLs() {
            let table = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String]
            fragmentKeys.formUnion((table ?? [:]).keys)
        }

        for (key, entry) in entries {
            #expect(!fragmentKeys.contains(key), "\"\(key)\" is translated in both the stringsdict and a .strings fragment")
            let format = try #require(entry["NSStringLocalizedFormatKey"] as? String, "\"\(key)\" has no NSStringLocalizedFormatKey")
            let variables = entry.filter { $0.key != "NSStringLocalizedFormatKey" }
            #expect(!variables.isEmpty, "\"\(key)\" has no plural variable")
            for (name, value) in variables {
                #expect(format.contains("@\(name)@"), "\"\(key)\" does not use variable \(name)")
                let rule = try #require(value as? [String: String], "\"\(key)\" variable \(name) is not a rule")
                #expect(rule["NSStringFormatSpecTypeKey"] == "NSStringPluralRuleType")
                for form in ["one", "few", "many", "other"] {
                    #expect(
                        !(rule[form] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "\"\(key)\" variable \(name) is missing the \(form) form"
                    )
                }
            }
        }
    }

    @Test("format specifier extraction handles positional and literal percent")
    func formatSpecifierExtraction() {
        #expect(Self.formatSpecifiers(in: "Saved %lld of %@") == [1: "lld", 2: "@"])
        #expect(Self.formatSpecifiers(in: "%2$@ сохранено: %1$lld") == [1: "lld", 2: "@"])
        #expect(Self.formatSpecifiers(in: "100%% done") == [:])
        #expect(Self.formatSpecifiers(in: "%d") != Self.formatSpecifiers(in: "%lld"))
    }

    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Localization/ru", isDirectory: true)

    private static func fragmentURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "strings" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Keys as written on `"key" = ...` lines, still escaped; enough to detect duplicates.
    private static func rawKeys(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"^\s*"((?:[^"\\]|\\.)*)"\s*="#)
        return text.components(separatedBy: .newlines).compactMap { line in
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let keyRange = Range(match.range(at: 1), in: line) else { return nil }
            return String(line[keyRange])
        }
    }

    /// Argument position → length modifier + conversion, e.g. [1: "lld", 2: "@"].
    static func formatSpecifiers(in string: String) -> [Int: String] {
        let regex = try! NSRegularExpression(
            pattern: #"%(?:%|(?:(\d+)\$)?[-+ #0']*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGcCsSpaA]))"#
        )
        var result: [Int: String] = [:]
        var nextPosition = 1
        let range = NSRange(string.startIndex..., in: string)
        for match in regex.matches(in: string, range: range) {
            guard let conversionRange = Range(match.range(at: 3), in: string) else { continue } // "%%"
            let length = Range(match.range(at: 2), in: string).map { String(string[$0]) } ?? ""
            let position: Int
            if let positionRange = Range(match.range(at: 1), in: string), let explicit = Int(string[positionRange]) {
                position = explicit
            } else {
                position = nextPosition
                nextPosition += 1
            }
            result[position] = length + String(string[conversionRange])
        }
        return result
    }
}
