import Foundation
import Observation
import os

/// Loads the occasions and the Start here progression.
///
/// One exclusive state, like `FoundationsModel`. Failure is not a screen:
/// occasions are a layer over the catalogue, so `available` answers `.none`
/// and every exercise stays on offer.
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

    /// Ignored by observation on `TechniqueListModel.refreshTask`'s reasoning:
    /// neither is anything a view draws.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var freshness: ReferenceFreshness

    /// - Parameter occasions: local occasions and their refresh operation.
    public init(occasions: any OccasionReading) {
        self.occasions = occasions
        freshness = ReferenceFreshness()
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
