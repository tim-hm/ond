import Foundation
import Observation

/// Drives the technique list screen: one `State`, mutated only by `load()`.
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

    /// The first load, once somebody has started it. Model-owned rather than
    /// structured so that it survives its starter: a tab switch cancels the
    /// `.task` that called `loadIfNeeded()`, and a cancelled shared fetch
    /// would land every tab in `.failed` over a catalogue that was one second
    /// from arriving.
    private var firstLoad: Task<Void, Never>?

    public init(techniques: any TechniqueReading) {
        self.techniques = techniques
    }

    /// Joins the first load, starting it if nobody has.
    ///
    /// Every tab root calls this from its `.task` — the model is shared, and
    /// without the joining, each tab's arrival would tear a good catalogue
    /// back down to a spinner and a fresh fetch.
    public func loadIfNeeded() async {
        let task = firstLoad ?? Task { await self.load() }
        firstLoad = task
        await task.value
    }

    /// Fetches unconditionally — the explicit Try-again under a failure.
    public func load() async {
        state = .loading
        do {
            state = try await .loaded(techniques.listTechniques())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// What the reminder dial's schedule opens with, chosen by the first of
    /// `goals` — calm where they named none, because the seed is a starting
    /// point to edit rather than a claim about them, and calm is the one aim
    /// that suits an unknown reason for being here.
    ///
    /// The one statement of that rule, shared by the onboarding seed and the
    /// Settings dial. Waits for the catalogue rather than reading whatever it
    /// holds at this instant: onboarding runs on a first launch where the
    /// fetch may still be in the air, and a dial moved in Settings deserves
    /// the same patience. Nil where the catalogue cannot be had, which each
    /// caller answers in its own way.
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
