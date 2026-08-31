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

/// Health that answers nothing and remembers every call in order. Members it
/// says nothing about come from `StubbedHealthStore`, so a ninth costs this
/// file nothing; `ScriptedHealthStore` scripts return values instead.
/// Recording *every* member is the point: an empty call list asserts Health
/// heard nothing at all, not merely that one write never happened.
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

/// Health with one settled answer about the mood write's grant, counting how
/// often it was asked — the recorder is meant to stop asking once the answer
/// can no longer change.
actor PromptingHealthStore: StubbedHealthStore {
    private(set) var asks = 0
    private let mayPrompt: Bool

    init(mayPrompt: Bool) {
        self.mayPrompt = mayPrompt
    }

    func writeMoodMayPrompt() async -> Bool {
        asks += 1
        return mayPrompt
    }
}
