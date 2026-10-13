import Foundation

enum ICloudCancellableOperation {
    static func run<Value>(
        _ operation: Operation,
        start: @escaping (CheckedContinuation<Value, Error>) -> Void
    ) async throws -> Value {
        try Task.checkCancellation()
        do {
            let value: Value = try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
                    guard !Task.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    start(continuation)
                }
            }, onCancel: {
                operation.cancel()
            })
            try Task.checkCancellation()
            return value
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }
}
