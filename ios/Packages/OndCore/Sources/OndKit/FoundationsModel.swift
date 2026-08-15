import Foundation
import Observation
import os

/// Drives the foundations screen from its downloaded copy and server refreshes.
///
/// The same shape as `TechniqueListModel`, and for the same reason — the states
/// are exclusive, and parallel `isLoading`/`error` properties would admit
/// combinations that mean nothing.
@MainActor
@Observable
public final class FoundationsModel {
    private static let logger = Logger(category: "reference-cache")

    public enum State {
        case loading
        case loaded([FoundationTopic])
        case failed(String)
    }

    public private(set) var state: State = .loading

    private let topics: any FoundationReading

    /// Ignored by observation on `TechniqueListModel.refreshTask`'s reasoning:
    /// neither is anything a view draws.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var freshness: ReferenceFreshness

    /// - Parameter topics: local foundations and their refresh operation.
    public init(topics: any FoundationReading) {
        self.topics = topics
        freshness = ReferenceFreshness()
    }

    /// Publishes the local copy and starts a refresh if this model has not
    /// loaded yet, or has been holding what it has for long enough to be worth
    /// asking again. With no copy at all, waits for the first download.
    public func loadIfNeeded() async {
        if case .loaded = state {
            if freshness.isStale {
                startRefresh()
            }
            return
        }

        let local = await topics.localFoundations()
        if case .loaded = state {
            return
        }

        if let local {
            state = .loaded(local)
            startRefresh()
            return
        }

        await refresh()
    }

    /// Refreshes unconditionally, preserving downloaded topics if the request
    /// fails and exposing a failure only when the device has no local copy.
    public func refresh() async {
        await startRefresh().value
    }

    @discardableResult
    private func startRefresh() -> Task<Void, Never> {
        if let refreshTask {
            return refreshTask
        }

        let task = Task { await performRefresh() }
        refreshTask = task
        return task
    }

    private func performRefresh() async {
        defer { refreshTask = nil }
        freshness.markAsked()

        if case .loaded = state {
            // Keep drawing the topics already on screen.
        } else if let local = await topics.localFoundations() {
            state = .loaded(local)
        } else {
            state = .loading
        }

        do {
            state = try await .loaded(topics.refreshFoundations())
        } catch {
            Self.logger.notice(
                "foundations refresh failed: \(error.diagnostic, privacy: .public)"
            )
            if case .loaded = state {
                // A failed refresh does not displace usable local data.
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
