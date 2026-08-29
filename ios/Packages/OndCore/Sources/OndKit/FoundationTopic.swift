import Foundation

/// One question a beginner has, and the app's answer to it.
///
/// Reference data on the same footing as the catalogue rather than copy baked
/// into a screen: the same rows appear as in-session hints, and M6's assistant
/// cites them instead of inventing its own version of the same advice.
public struct FoundationTopic: Sendable, Identifiable, Hashable, Codable {
    private enum CodingKeys: String, CodingKey {
        case slug
        case question
        case answer
        case answerContent
    }

    /// The stable key. Identity, because a topic's wording is the thing most
    /// likely to change about it.
    public let slug: String
    public let question: String
    public let answer: String
    /// The answer in its scannable form, with `answer` as the legacy fallback.
    public let answerContent: ReadingContent

    public var id: String {
        slug
    }

    public init(
        slug: String,
        question: String,
        answer: String,
        answerContent: ReadingContent? = nil
    ) {
        self.slug = slug
        self.question = question
        self.answer = answer
        self.answerContent = ReadingContent.resolved(answerContent, fallback: answer)
            ?? ReadingContent(lead: answer)
    }

    /// Decodes caches written before structured reading content existed.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            slug: container.decode(String.self, forKey: .slug),
            question: container.decode(String.self, forKey: .question),
            answer: container.decode(String.self, forKey: .answer),
            answerContent: container.decodeIfPresent(
                ReadingContent.self,
                forKey: .answerContent
            )
        )
    }
}
