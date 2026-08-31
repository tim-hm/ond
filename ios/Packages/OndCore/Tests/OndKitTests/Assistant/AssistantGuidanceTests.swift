import OndAPI
@testable import OndKit
import Testing

@Suite("Assistant guidance")
@MainActor
struct AssistantGuidanceTests {
    /// The boundary rule every enum here follows: a value this app cannot
    /// represent is a decode failure, never a silent default. Guessing
    /// `.fallback` would make the app claim the server never made.
    @Test("An unrepresentable source is refused rather than guessed")
    func rejectsAnUnspecifiedSource() {
        #expect(GuidanceSource(proto: .model) == .model)
        #expect(GuidanceSource(proto: .fallback) == .fallback)
        #expect(GuidanceSource(proto: .unspecified) == nil)
        #expect(GuidanceSource(proto: .UNRECOGNIZED(99)) == nil)
    }

    /// The two rule-based sources need opposite copy: one is a wait that ends,
    /// while one is a subscription that has not been bought.
    @Test("A subscription refusal decodes apart from an outage")
    func keepsTheTwoRuleBasedSourcesApart() {
        #expect(GuidanceSource(proto: .subscriptionRequired) == .subscriptionRequired)
        #expect(GuidanceSource(proto: .subscriptionRequired) != .fallback)
    }

    /// The guidance strip has no failure state: an unreachable server leaves it
    /// absent, and the catalogue underneath is unaffected.
    @Test("Unreachable guidance leaves the strip empty rather than failing")
    func guidanceFailsQuietly() async {
        let model = GuidanceModel(assistant: FailingAssistant())

        await model.loadIfNeeded()

        guard case .unavailable = model.state else {
            Issue.record("an unreachable server leaves nothing to show, not an error")
            return
        }
    }
}

private struct FailingAssistant: AssistantReading {
    func recommendations() async throws -> Guidance {
        throw AssistantRepositoryError.transport(.stub("no network"))
    }

    func chat(
        history _: [ChatTurn],
        message _: String
    ) -> AsyncThrowingStream<AssistantChunk, Error> {
        AsyncThrowingStream {
            $0.finish(throwing: AssistantRepositoryError.transport(.stub("no network")))
        }
    }
}
