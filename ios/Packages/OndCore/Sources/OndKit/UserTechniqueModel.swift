import Foundation
import Observation
import os

/// Drives the exercises somebody composed for themselves: one `State`, and the
/// three writes that change it.
///
/// Mirrors `TechniqueListModel` — same states, same local-first load, same rule
/// that a failed refresh never displaces a list already on screen — and then
/// adds what a read-only catalogue has no need of. The writes return the stored
/// exercise and patch the list in place rather than refetching, so saving is one
/// round trip and the list never blinks back to a spinner over an edit somebody
/// just watched succeed.
///
/// Lives in `OndKit` rather than the app target so the state machine is testable
/// on the host.
///
/// It is also where the flow's logging lives, including for the two writes it
/// rethrows. A view catching one renders it beside the field the server named
/// and drops it with the sheet, so a line written there would have to be
/// written again by the next screen that saves. Logged here, one failure is one
/// line however many screens call it — and the views stay silent, so it stays
/// one line.
@MainActor
@Observable
public final class UserTechniqueModel {
    private static let logger = Logger(category: "user-technique")

    /// The catalogue state a composed-exercises screen can present.
    public enum State {
        /// The first load or an explicit retry is in flight.
        case loading
        /// The exercises and the authoring limits that constrain new ones.
        case loaded(UserTechniqueList)
        /// Nothing local to draw and the fetch failed, carrying the sentence a
        /// retry surface presents. Only reachable before a first successful
        /// fetch under this identity: after one, a failure leaves `loaded`
        /// standing.
        case failed(String)
    }

    /// The latest load result; writes patch a loaded value in place.
    public private(set) var state: State = .loading

    private let store: any UserTechniqueStoring & UserTechniqueReading

    /// Model-owned so a tab switch cannot cancel a useful request, and shared so
    /// several screens asking together still produce one fetch — the same
    /// arrangement `TechniqueListModel` keeps, for the same two reasons.
    private var refreshTask: Task<Void, Never>?

    /// Creates the model over the repository used for every read and write.
    ///
    /// - Parameter store: The composed-exercise boundary to load and mutate.
    public init(store: any UserTechniqueStoring & UserTechniqueReading) {
        self.store = store
    }

    /// What has been composed, or nothing while the first load is in flight.
    public var techniques: [Technique] {
        if case let .loaded(list) = state {
            list.techniques
        } else {
            []
        }
    }

    /// What the server allows, or nil until it has said.
    ///
    /// The composer opens on this rather than on defaults of its own: a dial
    /// rendered from a guess is one somebody drags to a number that will not
    /// save.
    public var limits: AuthoringLimits? {
        if case let .loaded(list) = state {
            list.limits
        } else {
            nil
        }
    }

    /// Whether there is room for another, which is what a New button reads.
    ///
    /// False while loading too. Offering New before the limits have arrived
    /// would open a composer with nothing to bound it.
    public var hasRoomForAnother: Bool {
        guard case let .loaded(list) = state else { return false }
        return list.techniques.count < list.limits.maxTechniques
    }

    /// Publishes what this device already holds and fetches behind it, unless
    /// a list is already on screen — the same shape `TechniqueListModel` uses,
    /// and for the same reason: a person who has these exercises should see them
    /// before the network is consulted about them.
    public func loadIfNeeded() async {
        if case .loaded = state {
            return
        }

        let local = await store.localUserTechniques()
        if case .loaded = state {
            return
        }

        if let local {
            state = .loaded(local)
            startRefresh()
            return
        }

        await load()
    }

    /// Fetches unconditionally — the explicit Try-again under a failure, and
    /// the reload an identity change forces.
    public func load() async {
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
            // Keep drawing the exercises already on screen.
        } else if let local = await store.localUserTechniques() {
            state = .loaded(local)
        } else {
            state = .loading
        }

        do {
            state = try await .loaded(store.listUserTechniques())
        } catch {
            Self.logger.notice(
                "failed to load the exercises: \(error.diagnostic, privacy: .public)"
            )
            if case .loaded = state {
                // A failed refresh does not displace a usable local list. This
                // is the whole of the fix: the section used to drop to an error
                // over exercises it was already drawing.
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Stores `draft`, as a new exercise or as a replacement for `edited`.
    ///
    /// Takes the exercise being replaced rather than its id, so that no caller
    /// has to pick between the two strings a `Technique` carries — the slug it
    /// is played and recorded under, and the id this service edits by.
    ///
    /// Throws rather than moving to `.failed`: a refused save is the composer's
    /// to report, beside the field it objected to, and dropping the list to an
    /// error screen would take away the draft somebody is still editing.
    @discardableResult
    public func save(
        _ draft: TechniqueDraft,
        replacing edited: Technique? = nil
    ) async throws -> Technique {
        let stored: Technique
        do {
            stored = if let edited {
                try await store.updateUserTechnique(id: UserTechniqueId(of: edited), to: draft)
            } else {
                try await store.createUserTechnique(draft)
            }
        } catch {
            Self.logger.notice(
                "failed to save the exercise: \(error.diagnostic, privacy: .public)"
            )
            throw error
        }

        replace(stored, at: edited?.id)
        return stored
    }

    /// Deletes an exercise, and stops showing it.
    ///
    /// The removal happens after the server has agreed rather than before it:
    /// the list is small and the call is quick, and an optimistic removal that
    /// had to be undone would put a row back under somebody's finger.
    public func delete(_ technique: Technique) async throws {
        do {
            try await store.deleteUserTechnique(id: UserTechniqueId(of: technique))
        } catch {
            Self.logger.notice(
                "failed to delete the exercise: \(error.diagnostic, privacy: .public)"
            )
            throw error
        }

        guard case let .loaded(list) = state else { return }
        state = .loaded(UserTechniqueList(
            techniques: list.techniques.filter { $0.id != technique.id },
            limits: list.limits
        ))
    }

    /// Puts a stored exercise where it belongs: over the one it replaced, or at
    /// the end, which is where the server's oldest-first order would also put a
    /// new one.
    private func replace(_ stored: Technique, at id: String?) {
        guard case let .loaded(list) = state else { return }

        var techniques = list.techniques
        if let id, let index = techniques.firstIndex(where: { $0.id == id }) {
            techniques[index] = stored
        } else {
            techniques.append(stored)
        }

        state = .loaded(UserTechniqueList(techniques: techniques, limits: list.limits))
    }
}
