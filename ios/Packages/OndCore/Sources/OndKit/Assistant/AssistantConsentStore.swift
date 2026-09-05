import Foundation
import Observation

@MainActor
@Observable
public final class AssistantConsentStore: PersonalStore {
    public struct Agreement: Codable, Sendable, Equatable {
        public let version: Int
        public let date: Date
        public let disclosure: String
    }

    public static let version = 2
    public static let disclosure = "The coach uses AI through Amazon Bedrock (Anthropic's Claude). "
        + "Your message, recent conversation, optional first name and profile, practice and check-in history, "
        + "and saved exercise names and goals are sent through önd's server for a reply. "
        + "Conversations are saved on your iPhone until you delete them. "
        + "If you enable Heart and sleep data, Health summaries are included too; raw Health readings stay on your device. "
        + "You can withdraw permission in Settings. Breathing exercises remain available without AI."

    public private(set) var agreement: Agreement?
    private let store: DefaultsJSONStore<Agreement>

    public init(defaults: UserDefaults = .standard) {
        store = DefaultsJSONStore(
            key: "assistant.consent",
            what: "AI sharing permission",
            category: "assistant",
            defaults: defaults
        )
        agreement = store.load()
    }

    public var isAllowed: Bool {
        agreement?.version == Self.version
    }

    public func allow(at date: Date = .now) {
        let agreement = Agreement(version: Self.version, date: date, disclosure: Self.disclosure)
        store.save(agreement)
        self.agreement = agreement
    }

    public func withdraw() {
        agreement = nil
        store.erase()
    }

    public func erase() async {
        withdraw()
    }
}
