import Foundation

enum ICloudCancellableOperation {
    static func run<Value>(
        _ operation: Operation,
        start: (CheckedContinuation<Value, Error>) -> Void
    ) async throws -> Value {
        try Task.checkCancellation()
        do {
            let value = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    guard !Task.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    start(continuation)
                }
            } onCancel: {
                operation.cancel()
            }
            try Task.checkCancellation()
            return value
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }
}
