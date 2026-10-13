import Foundation

enum RecordingWAVFileIO {
    static let maximumDataSize = Int(UInt32.max) - 36

    enum Failure: LocalizedError {
        case sizeLimit
        case incompleteHeader

        var errorDescription: String? {
            switch self {
            case .sizeLimit: return String(localized: "Recording reached the WAV size limit")
            case .incompleteHeader: return String(localized: "Recording file header is incomplete")
            }
        }
    }

    static func validateDataSize(_ count: Int) throws {
        guard count >= 0, count <= maximumDataSize else { throw Failure.sizeLimit }
    }

    static func append(_ data: Data, to handle: FileHandle, bytesWritten: Int) throws {
        try validateDataSize(bytesWritten)
        guard data.count <= maximumDataSize - bytesWritten else { throw Failure.sizeLimit }
        try handle.write(contentsOf: data)
    }

    @discardableResult
    static func finalize(_ handle: FileHandle) throws -> Int {
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        guard length >= 44 else { throw Failure.incompleteHeader }
        guard length - 44 <= UInt64(maximumDataSize) else { throw Failure.sizeLimit }
        // A failed write may leave a partial sample; preserve only complete PCM16 samples.
        let dataSize = Int(length - 44) / 2 * 2
        try handle.truncate(atOffset: UInt64(44 + dataSize))
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: WavWriter.header(dataSize: dataSize))
        return dataSize
    }

    @discardableResult
    static func finalizePreservingFile(_ handle: FileHandle) -> Int? {
        let length = try? handle.seekToEnd()
        do {
            return try finalize(handle)
        } catch {
            fputs("[recording-file] finalization failed: \(error)\n", stderr)
            if let length, length >= 44, length - 44 <= UInt64(maximumDataSize) {
                return Int(length - 44) / 2 * 2
            }
            return nil
        }
    }
}
