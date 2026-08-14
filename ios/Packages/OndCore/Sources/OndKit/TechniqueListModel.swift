import Foundation
import Observation

/// Drives the technique list screen from local data and repeatable refreshes.
///
/// Lives in `OndKit` rather than the app target so the state machine is
/// testable on the host — the app target has no test bundle, and package tests
/// can only reach code inside a package target.
@MainActor
@Observable
public final class TechniqueListModel {
    /// The states the list can be in. An enum rather than parallel
    /// `isLoading`/`error`/`techniques` properties, because those admit
    /// combinations that mean nothing — loading *and* failed, say — and every
    /// view then has to decide which one wins.
    public enum State {
        case loading
        case loaded([Technique])
        case failed(String)
    }

    public private(set) var state: State = .loading

    /// Whether the load has answered, either way.
    ///
    /// The question three screens ask before deciding between a spinner and an
    /// empty state, and each of them had written `if case .loading` by hand. A
    /// failure settles: what a screen does about one is its own decision, and
    /// "is there still something to wait for" is not.
    public var hasSettled: Bool {
        if case .loading = state {
            return false
        }
        return true
    }

    private let techniques: any TechniqueReading

    /// Model-owned so a tab switch cannot cancel a useful server request, and
    /// shared so several screens asking together still produce one refresh.
    private var refreshTask: Task<Void, Never>?

    /// - Parameter techniques: the local catalogue and its refresh operation.
    public init(techniques: any TechniqueReading) {
        self.techniques = techniques
    }

    /// Publishes the local catalogue and starts a refresh if this model has not
    /// loaded yet. Returns as soon as local data is usable.
    public func loadIfNeeded() async {
        if case .loaded = state {
            return
        }

        let local = await techniques.localTechniques()
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

    /// Refreshes unconditionally, preserving a usable local catalogue if the
    /// server cannot be reached.
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
        if case .loaded = state {
            // Keep drawing the catalogue already on screen.
        } else if let local = await techniques.localTechniques() {
            state = .loaded(local)
        } else {
            state = .loading
        }

        do {
            state = try await .loaded(techniques.refreshTechniques())
        } catch {
            if case .loaded = state {
                // A failed refresh does not displace usable local data.
            } else {
                state = .failed(error.localizedDescription)
            }
        }
        refreshTask = nil
    }

    /// What the reminder dial's schedule opens with, chosen by the first of
    /// `goals` — calm where they named none, because the seed is a starting
    /// point to edit rather than a claim about them, and calm is the one aim
    /// that suits an unknown reason for being here.
    ///
    /// The one statement of that rule, shared by the onboarding seed and the
    /// Settings dial. Loads a usable local catalogue before choosing, but does
    /// not wait for the refresh it starts behind that local answer. Nil only
    /// where neither a snapshot nor the bundled catalogue can be read and the
    /// server request also fails.
    public func reminderTechnique(forFirstOf goals: [TechniqueGoal]) async -> Technique? {
        await loadIfNeeded()
        guard case let .loaded(techniques) = state else { return nil }

        return HomeSuggestion.technique(
            for: goals.first ?? .calm,
            techniques: techniques,
            history: []
        )
    }
}
