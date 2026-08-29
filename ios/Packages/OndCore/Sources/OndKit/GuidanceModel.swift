import Foundation
import Observation
import os

/// Drives the "where to start" strip. One `State`, mutated only by `load()`:
/// parallel `isLoading`/data properties admit combinations that mean nothing.
/// Deliberately no `failed` case — the server answers from rules whenever the
/// assistant is unreachable, and a person on a train should see the
/// catalogue, not an error. `unavailable` renders as nothing at all.
@MainActor
@Observable
public final class GuidanceModel {
    public enum State: Sendable {
        case loading
        case loaded(Guidance)
        case unavailable
    }

    private static let logger = Logger(category: "assistant")

    public private(set) var state: State = .loading

    private let assistant: any AssistantReading

    public init(assistant: any AssistantReading) {
        self.assistant = assistant
    }

    /// Loads unless an answer is already here. The screen's `.task` runs on
    /// every arrival, and re-asking per tab switch would spend the daily
    /// allowance on a screen being scrolled past. An `unavailable` answer is
    /// not retried either — the network did not recover because a tab was
    /// tapped.
    public func loadIfNeeded() async {
        guard case .loading = state else { return }
        await load()
    }

    private func load() async {
        do {
            state = try await .loaded(assistant.recommendations())
        } catch {
            // Quiet on the screen, not in the log. Everything this view sits
            // above works without a suggestion, so there is nothing to show
            // anyone — but "the strip is always empty" is otherwise a report
            // with no record behind it anywhere on the device.
            Self.logger
                .notice(
                    "guidance unavailable: \(error.diagnostic, privacy: .public)"
                )
            state = .unavailable
        }
    }
}
