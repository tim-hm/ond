import Foundation
import Observation
import os

/// Loads the occasions and the Start here progression.
///
/// The same shape as `FoundationsModel`, and for the same reason — the states
/// are exclusive, and parallel `isLoading`/`error` properties would admit
/// combinations that mean nothing.
///
/// What differs is that failure is not a screen. Routes are a layer *over* the
/// catalogue, so a home that could not fetch them still has every exercise to
/// offer: `available` is what surfaces read, and it answers `.none` until there
/// is something better. An error banner here would report a degradation the
/// person cannot act on and would not otherwise notice.
@MainActor
@Observable
public final class RoutesModel {
    private static let logger = Logger(category: "reference-cache")

    public enum State {
        case loading
        case loaded(Routes)
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

    /// The routes to route by: whatever landed, or none at all. Never throws
    /// and never blocks — a surface reads this on every pass and gets the
    /// honest answer for the moment it is drawing.
    public var available: Routes {
        if case let .loaded(routes) = state {
            return routes
        }
        return .none
    }

    private let routes: any RouteReading
    private var refreshTask: Task<Void, Never>?

    /// - Parameter routes: local routes and their refresh operation.
    public init(routes: any RouteReading) {
        self.routes = routes
    }

    /// Publishes the local routes and starts a refresh if this model has not
    /// loaded yet. Returns before the request finishes.
    public func loadIfNeeded() async {
        if case .loaded = state {
            return
        }

        let local = await routes.localRoutes()
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

    /// Refreshes unconditionally, preserving usable local routes if the server
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

        if case .loaded = state {
            // Keep drawing the routes already on screen.
        } else if let local = await routes.localRoutes() {
            state = .loaded(local)
        } else {
            state = .loading
        }

        do {
            state = try await .loaded(routes.refreshRoutes())
        } catch {
            Self.logger.notice(
                "routes refresh failed: \(error.localizedDescription, privacy: .public)"
            )
            if case .loaded = state {
                // A failed refresh does not displace usable local data.
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
