import Foundation

/// Where a piece of guidance came from. The app says "chosen for you" only
/// for `.model`. Neither other case is a failure: both carry a real answer
/// derived from this person's goals, and presenting the three identically
/// would make a claim the app cannot back.
public enum GuidanceSource: Sendable, Equatable {
    /// A language model wrote it, for this person.
    case model

    /// The server's rules wrote it because the model could not be reached, had
    /// failed repeatedly, or this person's daily allowance was spent. Every one
    /// of those passes, so copy drawn for it may invite a retry.
    case fallback

    /// The server's rules wrote it because this person's subscription does not
    /// buy model answers; copy must not invite a retry — offer the
    /// subscription instead. Distinct from ``fallback`` on the wire rather
    /// than inferred from the local tier: the device's tier comes from
    /// `StoreKit`, and an unsynced receipt leaves a paying subscriber here.
    case subscriptionRequired
}

/// One technique the assistant suggests, and the sentence that justifies it.
///
/// `techniqueSlug` always resolves in the catalogue: the server validates every
/// slug against it before answering, so a view can look this up without a
/// branch for a technique the app has never heard of.
public struct Recommendation: Sendable, Equatable, Identifiable {
    public let techniqueSlug: String
    public let reason: String

    public var id: String {
        techniqueSlug
    }

    public init(techniqueSlug: String, reason: String) {
        self.techniqueSlug = techniqueSlug
        self.reason = reason
    }
}

/// What the assistant suggests, and whether a model wrote it.
public struct Guidance: Sendable, Equatable {
    /// Best first. Never empty when the call succeeded.
    public let recommendations: [Recommendation]
    public let source: GuidanceSource

    public init(recommendations: [Recommendation], source: GuidanceSource) {
        self.recommendations = recommendations
        self.source = source
    }
}

/// A piece of a streamed chat reply as it arrives.
///
/// The source rides on every chunk so a view knows how to frame the text from
/// the first one, rather than waiting for the stream to finish to find out.
public struct AssistantChunk: Sendable, Equatable {
    public let text: String
    public let source: GuidanceSource

    /// The proposal a chat reply may end on — at most one per reply, after its
    /// prose. A field rather than an enum case because a chunk's text and
    /// proposal are not exclusive on the wire.
    public let proposal: CoachProposal?

    public init(text: String, source: GuidanceSource, proposal: CoachProposal? = nil) {
        self.text = text
        self.source = source
        self.proposal = proposal
    }
}
