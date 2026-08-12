import Foundation
@testable import OndKit

/// What `SpyHealthStore` remembers. At file scope only because the lint rule
/// caps type nesting one level short of where this naturally lives.
enum HealthCall: Equatable {
    case requestedRead
    case wroteMindfulSession(start: Date, end: Date)
    case wroteMood(Mood, at: Date)
}

/// Health that answers nothing and remembers every call in order.
///
/// Shared by every suite that needs to prove what did — or did not — reach
/// Health: `HealthStore` has six members, and a double per suite meant a
/// seventh member costing four near-identical edits. `ScriptedHealthStore` in
/// `HealthContextModelTests` stays its own thing, because it scripts return
/// values rather than recording calls.
///
/// Recording *every* member is the point: a test asserting an empty call list
/// is asserting Health heard nothing at all, not merely that the one write it
/// had in mind never happened.
actor SpyHealthStore: HealthStore {
    private(set) var calls: [HealthCall] = []

    func requestReadAuthorization() async {
        calls.append(.requestedRead)
    }

    func restingHeartRate(from _: Date, to _: Date) async -> [DailyQuantity] {
        []
    }

    func heartRateVariability(from _: Date, to _: Date) async -> [DailyQuantity] {
        []
    }

    func respiratoryRate(from _: Date, to _: Date) async -> [DailyQuantity] {
        []
    }

    func writeMindfulSession(from start: Date, to end: Date) async {
        calls.append(.wroteMindfulSession(start: start, end: end))
    }

    func writeMood(_ mood: Mood, at date: Date) async {
        calls.append(.wroteMood(mood, at: date))
    }
}
