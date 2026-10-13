import Foundation
import SwiftUI

/// Renames one speaker in a saved `[HH:mm:ss] <label>: text` meeting transcript.
enum MeetingSpeakerRename {
    /// Matches the speaker-label limit of the transcript chat parser.
    static let maxNameLength = 32

    /// Trimmed name, or nil when it is empty, too long, or would break the `label:` line format.
    static func validatedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maxNameLength,
              !trimmed.contains(":"),
              !trimmed.contains(where: \.isNewline) else {
            return nil
        }
        return trimmed
    }

    /// Replaces the exact label in timestamped lines only; message text is never touched.
    /// Returns nil when the name is invalid or no line changed.
    static func rename(_ oldLabel: String, to newName: String, in transcript: String) -> String? {
        guard let name = validatedName(newName), !oldLabel.isEmpty, name != oldLabel else { return nil }
        let labelPrefix = oldLabel + ":"
        var changed = false
        let lines = transcript.components(separatedBy: "\n").map { line -> String in
            guard let labelStart = line.range(of: #"^\[\d{2}:\d{2}:\d{2}\] "#, options: .regularExpression)?.upperBound,
                  line[labelStart...].hasPrefix(labelPrefix) else {
                return line
            }
            changed = true
            return String(line[..<labelStart]) + name + String(line[labelStart...].dropFirst(oldLabel.count))
        }
        return changed ? lines.joined(separator: "\n") : nil
    }
}

extension View {
    /// Prompts for a new name while `speaker` is set; calls `onRename(old, new)` on confirm.
    func speakerRenameAlert(speaker: Binding<String?>, onRename: @escaping (String, String) -> Void) -> some View {
        modifier(SpeakerRenameAlertModifier(speaker: speaker, onRename: onRename))
    }
}

private struct SpeakerRenameAlertModifier: ViewModifier {
    @Binding var speaker: String?
    let onRename: (String, String) -> Void
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .alert(
                "Переименовать говорящего",
                isPresented: Binding(
                    get: { speaker != nil },
                    set: { if !$0 { speaker = nil } }
                )
            ) {
                TextField("Имя", text: $draft)
                Button("Переименовать") {
                    if let speaker {
                        onRename(speaker, draft)
                    }
                    speaker = nil
                }
                .disabled(MeetingSpeakerRename.validatedName(draft) == nil)
                Button("Отмена", role: .cancel) {
                    speaker = nil
                }
            } message: {
                Text("Имя заменит «\(speaker ?? "")» во всех репликах этой расшифровки. Без двоеточия, до \(MeetingSpeakerRename.maxNameLength) символов.")
            }
            .onChange(of: speaker) { _, newValue in
                draft = newValue ?? ""
            }
    }
}
