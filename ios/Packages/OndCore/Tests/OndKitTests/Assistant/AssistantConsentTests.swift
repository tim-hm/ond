import Foundation
import OndKit
import Testing

@MainActor
@Suite("AI sharing permission")
struct AssistantConsentTests {
    @Test(
        "Neither recommendations nor chat reach the assistant before permission or after withdrawal"
    )
    func gatesEveryRequest() async throws {
        let name = "assistant-consent-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let consent = AssistantConsentStore(defaults: defaults)
        let spy = ConsentSpyAssistant()
        let assistant = ConsentedAssistant(spy, consent: consent)

        await #expect(throws: ConsentedAssistant.Failure.self) {
            try await assistant.recommendations()
        }
        await #expect(throws: ConsentedAssistant.Failure.self) {
            for try await _ in assistant.chat(
                history: [],
                message: "An automatic opening question"
            ) {}
        }
        #expect(await spy.calls == 0)

        let date = Date(timeIntervalSince1970: 1234)
        consent.allow(at: date)
        #expect(AssistantConsentStore(defaults: defaults).agreement?.date == date)
        #expect(consent.agreement?.disclosure == AssistantConsentStore.disclosure)
        _ = try await assistant.recommendations()
        for try await _ in assistant.chat(history: [], message: "Help me choose") {}
        #expect(await spy.calls == 2)

        consent.withdraw()
        await #expect(throws: ConsentedAssistant.Failure.self) {
            try await assistant.recommendations()
        }
        await #expect(throws: ConsentedAssistant.Failure.self) {
            for try await _ in assistant.chat(history: [], message: "Do not send") {}
        }
        #expect(await spy.calls == 2)
        #expect(!AssistantConsentStore(defaults: defaults).isAllowed)
    }
}

private actor ConsentSpyAssistant: AssistantReading {
    private(set) var calls = 0

    func recommendations() async throws -> Guidance {
        calls += 1
        return Guidance(recommendations: [], source: .fallback)
    }

    nonisolated func chat(
        history _: [ChatTurn],
        message _: String
    ) -> AsyncThrowingStream<AssistantChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await countChat()
                continuation.finish()
            }
        }
    }

    private func countChat() {
        calls += 1
    }
}
