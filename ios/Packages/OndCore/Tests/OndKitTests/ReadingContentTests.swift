import Foundation
@testable import OndKit
import Testing

@Suite("Scannable reading content")
struct ReadingContentTests {
    @Test("Bullets and numbered steps keep complete plain-text fallbacks")
    func plainTextIncludesEveryItem() {
        let bullets = ReadingContent(
            lead: "What we know.",
            items: ["First finding.", "Second finding."],
            listStyle: .bullets
        )
        let steps = ReadingContent(
            lead: "Before you begin.",
            items: ["Sit down.", "Settle."],
            listStyle: .numbered
        )

        #expect(bullets.plainText == "What we know.\n\n• First finding.\n• Second finding.")
        #expect(steps.plainText == "Before you begin.\n\n1. Sit down.\n2. Settle.")
    }

    @Test("A foundation cache from before structured copy still decodes")
    func oldFoundationCacheFallsBackToItsAnswer() throws {
        let data = Data(#"{"slug":"why","question":"Why?","answer":"A complete answer."}"#.utf8)

        let topic = try JSONDecoder().decode(FoundationTopic.self, from: data)

        #expect(topic.answerContent == ReadingContent(lead: "A complete answer."))
    }

    @Test("Items and styles must agree before structured content is used")
    func structureMustBeWellFormed() {
        #expect(ReadingContent(lead: "A paragraph.").isWellFormed)
        #expect(!ReadingContent(
            lead: "A list.",
            items: ["A point."],
            listStyle: .none
        ).isWellFormed)
        #expect(!ReadingContent(
            lead: "No list.",
            listStyle: .bullets
        ).isWellFormed)
        #expect(!ReadingContent(
            lead: "",
            items: ["A point."],
            listStyle: .bullets
        ).isWellFormed)
    }
}
