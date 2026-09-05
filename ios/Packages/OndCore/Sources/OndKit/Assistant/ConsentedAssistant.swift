import Foundation

public struct ConsentedAssistant: AssistantReading {
    public enum Failure: LocalizedError {
        case permissionRequired
        public var errorDescription: String? {
            "Review AI sharing before asking the coach."
        }
    }

    private let assistant: any AssistantReading
    private let consent: AssistantConsentStore

    public init(_ assistant: any AssistantReading, consent: AssistantConsentStore) {
        self.assistant = assistant
        self.consent = consent
    }

    public func recommendations() async throws -> Guidance {
        guard await consent.isAllowed else { throw Failure.permissionRequired }
        return try await assistant.recommendations()
    }

    public func chat(
        history: [ChatTurn],
        message: String
    ) -> AsyncThrowingStream<AssistantChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard await consent.isAllowed else { throw Failure.permissionRequired }
                    try Task.checkCancellation()
                    for try await chunk in assistant.chat(history: history, message: message) {
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
