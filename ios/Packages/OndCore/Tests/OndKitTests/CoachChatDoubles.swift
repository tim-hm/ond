import Foundation
@testable import OndKit
import Testing

/// The chat suites' constructor, defaulting everything a test does not care
/// about. Shared between `CoachChatTests` and `CoachChatPersistenceTests`,
/// which split one behaviour surface across two files for length alone.
@MainActor
func chatModel(
    _ script: ChatScript,
    store: any ConversationStoring = InMemoryConversationStore(),
    conversation: Conversation = Conversation()
) -> CoachChatModel {
    CoachChatModel(
        conversation: conversation,
        store: store,
        assistant: script.assistant
    )
}

/// A [`ConversationStoring`] in memory, with the store's own rules — empty
/// conversations refused, saves upserting by id — so what the model tests
/// observe is what the real store would keep. `@MainActor` rather than an
/// actor so `settle`'s synchronous predicate can read it.
@MainActor
final class InMemoryConversationStore: ConversationStoring {
    private(set) var all: [Conversation] = []
    private(set) var saves = 0

    func conversations() async -> [Conversation] {
        all.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ conversation: Conversation) async {
        guard !conversation.turns.isEmpty else { return }
        saves += 1
        if let index = all.firstIndex(where: { $0.id == conversation.id }) {
            all[index] = conversation
        } else {
            all.append(conversation)
        }
    }

    func remove(_ ids: Set<Conversation.ID>) async {
        all.removeAll { ids.contains($0.id) }
    }
}

/// A chat stream the test drives chunk by chunk, recording what each call
/// carried — `Script`'s pattern from the guidance tests, plus capture.
@MainActor
final class ChatScript {
    struct Call {
        let history: [ChatTurn]
        let message: String
    }

    private(set) var calls: [Call] = []
    private var continuation: AsyncThrowingStream<AssistantChunk, Error>.Continuation?

    var assistant: any AssistantReading {
        ScriptedChatAssistant(script: self)
    }

    func yield(_ chunk: AssistantChunk) {
        continuation?.yield(chunk)
    }

    func finish(throwing error: (any Error)? = nil) {
        continuation?.finish(throwing: error)
    }

    fileprivate func begin(
        history: [ChatTurn],
        message: String
    ) -> AsyncThrowingStream<AssistantChunk, Error> {
        calls.append(Call(history: history, message: message))
        let (stream, continuation) = AsyncThrowingStream<AssistantChunk, Error>.makeStream()
        self.continuation = continuation
        return stream
    }
}

private struct ScriptedChatAssistant: AssistantReading, @unchecked Sendable {
    let script: ChatScript

    func recommendations() async throws -> Guidance {
        Guidance(recommendations: [], source: .fallback)
    }

    func chat(history: [ChatTurn], message: String) -> AsyncThrowingStream<AssistantChunk, Error> {
        MainActor.assumeIsolated {
            script.begin(history: history, message: message)
        }
    }
}
