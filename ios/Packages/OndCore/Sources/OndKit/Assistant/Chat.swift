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

    /// The structured proposal riding on a coach reply, at most one of any
    /// kind. Nil on every person turn and on replies that proposed nothing.
    public let proposal: CoachProposal?

    /// Whether this turn stands in for a reply that never landed, rather than
    /// carrying one. Only ever true on a coach turn, and only where nothing at
    /// all arrived: it is what lets the transcript offer the question again.
    public let isFailed: Bool

    /// The exercise offer, where that is what this turn proposed.
    ///
    /// Kept as a name for the one place that asks the question in exactly this
    /// form: history annotation, which rides an earlier reply's offer back to
    /// the server as its slug and has nothing to say about the other kinds.
    public var offer: ExerciseOffer? {
        guard case let .exercise(offer) = proposal else { return nil }
        return offer
    }

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        proposal: CoachProposal? = nil,
        isFailed: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.proposal = proposal
        self.isFailed = isFailed
    }

    /// Hand-written for one key: `isFailed` arrived after conversations were
    /// already persisted, and a synthesized decoder would fail every stored
    /// file that predates it — which `JSONFileStore` would then set aside and
    /// show as no conversations at all.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(ChatRole.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        proposal = try container.decodeIfPresent(CoachProposal.self, forKey: .proposal)
        isFailed = try container.decodeIfPresent(Bool.self, forKey: .isFailed) ?? false
    }

    /// The longest message the server accepts, in Unicode scalars — the
    /// client half of the server's `MAX_CHAT_MESSAGE_CHARS`, enforced by
    /// clamping the composer as it is typed. Scalars because that is the unit
    /// the server counts in: a Character-counted clamp passes emoji-heavy text
    /// it refuses. Only the new message is bounded — history truncates remotely.
    public static let maxMessageLength = 1000

    /// How much history one request carries — the client half of the
    /// server's `MAX_CHAT_TURNS`. The server silently drops anything older,
    /// so sending more would upload bytes it provably throws away.
    public static let maxHistoryDepth = 20
}

/// The one thing a coach reply may propose, drawn as a card the person
/// accepts by tapping. At most one per reply — the server drops a second. An
/// enum rather than a field per kind, so "which one" stays a question the
/// type answers: a struct with two optionals admits a state the wire cannot
/// produce.
public enum CoachProposal: Sendable, Hashable, Codable {
    /// Start this exercise, dialled as the coach suggested.
    case exercise(ExerciseOffer)

    /// Take the breath-hold test, which carries nothing: the proposal is the
    /// whole of it.
    case boltTest

    /// Keep this pattern as one of your own exercises. The same
    /// ``TechniqueDraft`` the composer builds and the create RPC takes; the
    /// server has already run it through that RPC's validator, so the tapped
    /// card cannot be refused on arrival.
    case savedExercise(TechniqueDraft)
}

/// The coach's structured suggestion: which exercise, dialled how. The
/// server has already resolved the slug and clamped every override into its
/// safe range — but this device's catalogue may lag the server's, so the
/// card resolves the slug locally before rendering anything.
public struct ExerciseOffer: Sendable, Hashable, Codable {
    public let techniqueSlug: TechniqueSlug

    /// Nil means "as the catalogue curates it". A shape that no longer fits
    /// the technique is already handled downstream: `Technique.dialled(with:)`
    /// falls back to curated on any mismatch.
    public let overrides: TechniqueOverrides?

    /// Memberwise, made public: offers are decoded at the repository seam and
    /// scripted whole by tests.
    public init(techniqueSlug: TechniqueSlug, overrides: TechniqueOverrides? = nil) {
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

    /// A fresh conversation by default; every parameter exists so the store
    /// can decode one whole and tests can place one in time.
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
        Self.title(of: turns)
    }

    /// [`title`]'s derivation over any transcript — for the live chat screen,
    /// whose turns have usually outrun the stored conversation's.
    static func title(of turns: [ChatTurn]) -> String? {
        guard let first = turns.first(where: { $0.role == .person }) else { return nil }
        let collapsed = first.text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(titleLength))
    }
}
