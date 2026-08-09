import Foundation

/// Who said one turn of the conversation.
public enum ChatRole: String, Sendable, Equatable, Codable {
    /// The person using the app.
    case person

    /// The coach — the assistant's own earlier reply, kept so it can be read
    /// back to the server as attributed speech.
    case coach
}

/// One turn of the conversation with the coach.
///
/// The transcript is an array of these, oldest first, inside a
/// ``Conversation`` the device persists. The server still keeps no
/// conversation state at all, so what the device holds is the only copy.
public struct ChatTurn: Sendable, Hashable, Identifiable, Codable {
    /// Stable across the reply growing chunk by chunk, so SwiftUI animates one
    /// paragraph filling in rather than replacing a row per chunk.
    public let id: UUID
    public let role: ChatRole
    public let text: String

    /// The structured exercise offer riding on a coach reply, at most one.
    /// Nil on every person turn and on replies that offered nothing.
    public let offer: ExerciseOffer?

    public init(id: UUID = UUID(), role: ChatRole, text: String, offer: ExerciseOffer? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.offer = offer
    }

    /// The longest message the server accepts, in characters — the client
    /// half of the server's `MAX_CHAT_MESSAGE_CHARS`, enforced by clamping
    /// the composer as it is typed (the intent note's pattern), so a long
    /// paste can never turn into an `INVALID_ARGUMENT` that reads as the
    /// network failing. History turns are clamped to it too on the way out:
    /// a coach reply regularly runs past it, and a persisted transcript
    /// replays forever.
    public static let maxMessageLength = 1000

    /// How much history one request carries — the client half of the
    /// server's `MAX_CHAT_TURNS`. The server silently drops anything older,
    /// so sending more would upload bytes it provably throws away.
    public static let maxHistoryDepth = 20
}

/// The coach's structured suggestion: which exercise, dialled how.
///
/// The server has already resolved the slug against the catalogue and clamped
/// every override into its safe range, so a card can be drawn from this
/// without a defensive branch — though the *catalogue on this device* may
/// still lag the server's, which is why the card resolves the slug locally
/// before rendering anything.
public struct ExerciseOffer: Sendable, Hashable, Codable {
    public let techniqueSlug: String

    /// Nil means "as the catalogue curates it". A shape that no longer fits
    /// the technique is already handled downstream: `Technique.dialled(with:)`
    /// falls back to curated on any mismatch.
    public let overrides: TechniqueOverrides?

    public init(techniqueSlug: String, overrides: TechniqueOverrides? = nil) {
        self.techniqueSlug = techniqueSlug
        self.overrides = overrides
    }
}

/// One conversation with the coach, as the device keeps it.
///
/// `Hashable` because the list navigates by value —
/// `navigationDestination(item:)` requires it.
public struct Conversation: Sendable, Hashable, Identifiable, Codable {
    public let id: UUID
    public let createdAt: Date

    /// Bumped on every persisted change; what the list sorts by.
    public var updatedAt: Date

    /// Oldest first. The store refuses to persist a conversation with no
    /// turns, so an opened-and-abandoned chat leaves nothing behind.
    public var turns: [ChatTurn]

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        turns: [ChatTurn] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.turns = turns
    }
}

public extension Conversation {
    /// How many characters of the first question become the list row's title.
    static let titleLength = 60

    /// The first question, whitespace-collapsed and clipped, or nil while no
    /// question has been asked. Derived rather than stored so it can never
    /// drift from the transcript it summarises.
    var title: String? {
        guard let first = turns.first(where: { $0.role == .person }) else { return nil }
        let collapsed = first.text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(Self.titleLength))
    }
}
