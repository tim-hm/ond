import Foundation
import Observation

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

    private let routes: any TechniqueReading

    public init(routes: any TechniqueReading) {
        self.routes = routes
    }

    /// Loads unless the routes are already here.
    ///
    /// The screen's `.task` runs on every arrival; occasions are seeded
    /// reference data that changes with a deployment rather than with a
    /// session, so a second visit has nothing to fetch and reloading would only
    /// tear a good answer down.
    public func loadIfNeeded() async {
        if case .loaded = state {
            return
        }
        await load()
    }

    public func load() async {
        state = .loading
        do {
            state = try await .loaded(routes.listRoutes())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
