import Foundation
import OndAPI

/// How the items after a reading lead are presented.
public enum ReadingListStyle: String, Sendable, Hashable, Codable {
    case none = "NONE"
    case bullets = "BULLETS"
    case numbered = "NUMBERED"
}

/// A short lead followed, where useful, by a scannable list.
public struct ReadingContent: Sendable, Hashable, Codable {
    public let lead: String
    public let items: [String]
    public let listStyle: ReadingListStyle

    public init(
        lead: String,
        items: [String] = [],
        listStyle: ReadingListStyle = .none
    ) {
        self.lead = lead
        self.items = items
        self.listStyle = listStyle
    }

    /// A legacy plain-text field as paragraph-only content.
    public init?(legacy: String?) {
        guard let legacy, !legacy.isEmpty else { return nil }
        self.init(lead: legacy)
    }

    /// Whether the lead, items and style agree on a renderable shape.
    public var isWellFormed: Bool {
        guard !lead.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard items.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return false
        }

        return items.isEmpty ? listStyle == .none : listStyle != .none
    }

    /// Prefers structured content and falls back to the complete legacy text.
    static func resolved(_ content: Self?, fallback: String?) -> Self? {
        if let content, content.isWellFormed {
            return content
        }
        return Self(legacy: fallback)
    }

    /// The complete plain-text form used in compatibility assertions.
    public var plainText: String {
        guard !items.isEmpty else { return lead }

        let rows = items.enumerated().map { index, item in
            switch listStyle {
            case .none: item
            case .bullets: "• \(item)"
            case .numbered: "\(index + 1). \(item)"
            }
        }
        let list = rows.joined(separator: "\n")
        return lead.isEmpty ? list : lead + "\n\n" + list
    }
}

extension ReadingContent {
    init?(proto: Ond_V1_ReadingContent) {
        let style: ReadingListStyle
        switch proto.listStyle {
        case .unspecified: style = .none
        case .bullets: style = .bullets
        case .numbered: style = .numbered
        case .UNRECOGNIZED: return nil
        }

        self.init(lead: proto.lead, items: proto.items, listStyle: style)
        guard isWellFormed else { return nil }
    }
}
