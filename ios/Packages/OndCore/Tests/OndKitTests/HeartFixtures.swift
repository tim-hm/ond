import Foundation
@testable import OndKit
import Testing

/// What both heart suites need and neither is about — the fold's own rules and
/// the model's reading of them are different subjects sharing one shape of
/// setup, which is `OfferFixtures`' reason for existing too.
enum HeartFixtures {
    /// A reading Health answered for exactly the window a practice asks about.
    /// Built through `heartWindow(around:)` rather than by hand, so a test
    /// cannot accidentally pass by matching a window nobody would request.
    static func reading(for practice: SessionRecord, _ rate: Double) throws -> WindowedQuantity {
        try #require(
            WindowedQuantity(window: PracticeHeartline.heartWindow(around: practice), value: rate)
        )
    }

    /// A calendar pinned to one zone, so "today" is a fact rather than wherever
    /// the machine running the suite happens to be.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .gmt
        return calendar
    }()
}
