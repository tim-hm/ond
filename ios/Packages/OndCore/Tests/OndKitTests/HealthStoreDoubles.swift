import Foundation
@testable import OndKit

/// What `SpyHealthStore` remembers. At file scope only because the lint rule
/// caps type nesting one level short of where this naturally lives.
enum HealthCall: Equatable {
    case requestedRead
    case requestedMindfulWrite
    case wroteMindfulSession(start: Date, end: Date)
    case wroteMood(Mood, at: Date)
}

/// Health that answers nothing and remembers every call in order.
///
/// Shared by every suite that needs to prove what did — or did not — reach
/// Health. The members it says nothing about come from `StubbedHealthStore`, so
/// a ninth one costs this file nothing; `ScriptedHealthStore` stays its own
/// thing beside it, because it scripts return values rather than recording
/// calls.
///
/// Recording *every* member is the point: a test asserting an empty call list
/// is asserting Health heard nothing at all, not merely that the one write it
/// had in mind never happened.
actor SpyHealthStore: StubbedHealthStore {
    private(set) var calls: [HealthCall] = []

    func requestReadAuthorization() async {
        calls.append(.requestedRead)
    }

    func requestMindfulWriteAuthorization() async {
        calls.append(.requestedMindfulWrite)
    }

    func writeMindfulSession(from start: Date, to end: Date) async {
        calls.append(.wroteMindfulSession(start: start, end: end))
    }

    func writeMood(_ mood: Mood, at date: Date) async {
        calls.append(.wroteMood(mood, at: date))
    }
}
