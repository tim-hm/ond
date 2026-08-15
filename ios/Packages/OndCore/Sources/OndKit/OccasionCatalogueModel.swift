import Foundation
import Observation
import os

/// Loads the occasions and the Start here progression.
///
/// The same shape as `FoundationsModel`, and for the same reason — the states
/// are exclusive, and parallel `isLoading`/`error` properties would admit
/// combinations that mean nothing.
///
/// What differs is that failure is not a screen. Occasions are a layer *over*
/// the catalogue, so a home that could not fetch them still has every exercise
/// to offer: `available` is what surfaces read, and it answers `.none` until
/// there is something better. An error banner here would report a degradation
/// the person cannot act on and would not otherwise notice.
@MainActor
@Observable
public final class OccasionCatalogueModel {
    private static let logger = Logger(category: "reference-cache")

    public enum State {
        case loading
        case loaded(OccasionCatalogue)
        case failed(String)
    }

    public private(set) var state: State = .loading

    /// Whether the load has answered, either way — `TechniqueListModel.hasSettled`
    /// has the reasoning, and the two are asked together everywhere they are
    /// asked at all.
    public var hasSettled: Bool {
        if case .loading = state {
            return false
        }
        return true
    }

    /// The occasions to route by: whatever landed, or none at all. Never throws
    /// and never blocks — a surface reads this on every pass and gets the
    /// honest answer for the moment it is drawing.
    public var available: OccasionCatalogue {
        if case let .loaded(occasions) = state {
            return occasions
        }
        return .none
    }

    private let occasions: any OccasionReading
    private var refreshTask: Task<Void, Never>?
    private var freshness: ReferenceFreshness

    /// - Parameters:
    ///   - occasions: local occasions and their refresh operation.
    ///   - freshFor: how long a loaded set is trusted before the next screen
    ///     that asks quietly checks again. See ``ReferenceFreshness``.
    public init(
        occasions: any OccasionReading,
        freshFor: Duration = ReferenceFreshness.window
    ) {
        self.occasions = occasions
        freshness = ReferenceFreshness(window: freshFor)
    }

    /// Publishes the local occasions and starts a refresh if this model has not
    /// loaded yet, or has been holding what it has for long enough to be worth
    /// asking again. Returns before the request finishes.
    public func loadIfNeeded() async {
        if case .loaded = state {
            if freshness.isStale {
                startRefresh()
            }
            return
        }

        let local = await occasions.localOccasions()
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

    /// Refreshes unconditionally, preserving usable local occasions if the server
    /// cannot be reached.
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
            // Keep drawing the occasions already on screen.
        } else if let local = await occasions.localOccasions() {
            state = .loaded(local)
        } else {
            state = .loading
        }

        do {
            state = try await .loaded(occasions.refreshOccasions())
        } catch {
            Self.logger.notice(
                "occasions refresh failed: \(error.diagnostic, privacy: .public)"
            )
            if case .loaded = state {
                // A failed refresh does not displace usable local data.
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
