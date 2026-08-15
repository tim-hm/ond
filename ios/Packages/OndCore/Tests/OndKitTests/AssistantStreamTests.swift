import Connect
import Foundation
import OndAPI
@testable import OndKit
import Testing

/// A Connect server stream that yields `outputs` and then ends however the test
/// asks it to — including the way the library is not supposed to: running dry
/// with no terminal status at all.
private struct ScriptedStream: ServerOnlyAsyncStreamInterface {
    typealias Input = Ond_V1_ChatRequest
    typealias Output = Ond_V1_ChatResponse

    let texts: [String]
    /// The status to end on, or nil to stop without one.
    let ending: Code?

    func send(_: Input) throws {}

    func results() -> AsyncStream<StreamResult<Output>> {
        AsyncStream { continuation in
            for text in texts {
                var message = Ond_V1_ChatResponse()
                message.payload = .text(text)
                message.source = .model
                continuation.yield(.message(message))
            }
            if let ending {
                continuation.yield(.complete(code: ending, error: nil, trailers: nil))
            }
            continuation.finish()
        }
    }

    func cancel() {}
}

/// Reads a bridged stream to its end, keeping whatever arrived before it stopped
/// and whatever stopped it.
private func drain(
    _ stream: AsyncThrowingStream<AssistantChunk, Error>
) async -> (texts: [String], failure: (any Error)?) {
    var texts: [String] = []
    do {
        for try await chunk in stream {
            texts.append(chunk.text)
        }
        return (texts, nil)
    } catch {
        return (texts, error)
    }
}

private func bridged(_ stream: ScriptedStream) -> AsyncThrowingStream<AssistantChunk, Error> {
    AssistantRepository.bridged(
        stream,
        request: { Ond_V1_ChatRequest() },
        chunk: { .success(AssistantChunk(text: $0.text, source: .model)) }
    )
}

/// The chat wrapper tested where the model cannot be: the terminal status is
/// Connect's to send, and the model above only sees what this bridge made of it.
@Suite("Bridging a Connect stream")
struct AssistantStreamTests {
    /// docs/transport.md's own hazard: a stream that simply stops is
    /// indistinguishable from a short answer, so the coach would caption a
    /// truncated reply as the whole of it. The clean finish is reserved
    /// for a stream that said it was done.
    @Test("A stream that stops without a status fails rather than looking finished")
    func aStreamWithNoStatusFails() async throws {
        let (texts, failure) = await drain(bridged(ScriptedStream(
            texts: ["half an "],
            ending: nil
        )))

        let error = try #require(failure as? AssistantRepositoryError)

        #expect(texts == ["half an "], "what did arrive is still delivered")
        // `serverFault` and not `unreachable`: the socket was fine, the
        // library simply ended a stream without saying how.
        #expect(error == .transport(TransportFault(
            outcome: .serverFault,
            diagnostic: "the stream ended without a status"
        )))
    }

    @Test("A stream that ends OK finishes cleanly")
    func aCompletedStreamFinishes() async {
        let (texts, failure) = await drain(bridged(ScriptedStream(
            texts: ["the whole ", "answer"],
            ending: .ok
        )))

        #expect(texts == ["the whole ", "answer"])
        #expect(failure == nil)
    }

    /// The case that already worked, kept beside the new one so the two endings
    /// cannot drift apart: a non-OK status is the server refusing, not finishing.
    ///
    /// It also pins the split the two halves are for. The throttle's status
    /// classifies as `busy`, so a person is told to wait; the word the library
    /// used survives in the diagnostic, where a log can still name the status
    /// that caused it.
    @Test("A stream that ends with a non-OK status throws")
    func aRefusedStreamThrows() async throws {
        let (_, failure) = await drain(bridged(ScriptedStream(
            texts: [],
            ending: .resourceExhausted
        )))

        let error = try #require(failure as? AssistantRepositoryError)
        #expect(error == .transport(TransportFault(
            outcome: .busy,
            diagnostic: "the stream ended with resourceExhausted"
        )))
        #expect(error.errorDescription == TransportOutcome.busy.message)
        #expect(error.diagnostic.contains("resource"))
    }
}
