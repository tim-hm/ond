import Foundation
import os

/// Serves one person's composed exercises from the last list the server sent,
/// and refreshes them behind it.
///
/// The counterpart to `CachedReferenceRepository`, on the same bargain: a read
/// answers from disk so the section draws immediately, a fetch replaces the
/// snapshot when it lands, and a fetch that fails leaves standing whatever was
/// already there. Before this existed the "Yours" section had no local copy at
/// all — a failed refresh dropped a list it was already drawing and put an
/// error where somebody's own exercises had been.
///
/// What it deliberately has *no* equivalent of is the catalogue's bundled seed.
/// Every install starts from the same curated exercises, so shipping them is
/// possible; nobody else's work can stand in for somebody's own, so the honest
/// answer before a first successful fetch is nothing at all.
///
/// The snapshot records whose it is. An identity changes under a running app —
/// signing in, signing out, deleting — and a list keyed only on "the last answer
/// this device got" would draw the previous person's exercises to the next one.
/// Reading checks the id rather than relying on a caller clearing the file
/// first, which is the ordering dependency that check exists to close.
///
/// A struct rather than an actor, for `CachedReferenceRepository`'s reason: each
/// write atomically replaces one complete file, and the model above serialises
/// its own loads.
public struct CachedUserTechniqueRepository: UserTechniqueStoring, UserTechniqueReading {
    private static let logger = Logger(category: "user-technique")

    /// The list as it goes to disk, stamped with the identity it belongs to.
    private struct StoredList: Codable {
        let userId: UUID
        let list: UserTechniqueList
    }

    private let network: any UserTechniqueStoring
    private let identity: any UserIdentityStore
    private let url: URL

    /// The last decoded snapshot, so repeated local reads do not decode the
    /// same JSON. A reference inside the struct on purpose: copies of this
    /// repository share the memo exactly as they share the file.
    private let decoded = Snapshot<StoredList>()

    /// - Parameters:
    ///   - network: the repository that actually talks to the server — wrapped
    ///     rather than replaced, so this type never learns the wire format.
    ///   - identity: read on every access rather than captured, because the id
    ///     changes under a running app and a captured one would be stale
    ///     exactly when it matters.
    ///   - directory: where the snapshot lives. Application Support for
    ///     `CachedReferenceRepository`'s reason — the system backs it up and
    ///     never purges it, unlike Caches, which would let the OS delete the one
    ///     copy offline depends on. Tests pass a temporary directory.
    public init(
        caching network: any UserTechniqueStoring,
        identity: any UserIdentityStore,
        directory: URL = .applicationSupportDirectory
    ) {
        self.network = network
        self.identity = identity
        url = directory.appending(path: "user-techniques.json")
    }

    public func localUserTechniques() async -> UserTechniqueList? {
        guard let userId = identity.userId() else { return nil }
        guard let stored = decoded.value ?? restored() else { return nil }
        // Somebody else's list is not this person's absence of one: it is
        // ignored here and overwritten by the next fetch that succeeds.
        return stored.userId == userId ? stored.list : nil
    }

    /// Fetches and stores. No deadline of its own beyond the client's, for
    /// `CachedReferenceRepository.refresh`'s reason: a local read has already
    /// kept the screen moving, so a slow answer is still worth having.
    public func listUserTechniques() async throws -> UserTechniqueList {
        let fresh = try await network.listUserTechniques()
        persist(fresh)
        return fresh
    }

    public func createUserTechnique(_ draft: TechniqueDraft) async throws -> Technique {
        let stored = try await network.createUserTechnique(draft)
        patch { $0.appending(stored) }
        return stored
    }

    public func updateUserTechnique(
        id: UserTechniqueId,
        to draft: TechniqueDraft
    ) async throws -> Technique {
        let stored = try await network.updateUserTechnique(id: id, to: draft)
        patch { $0.replacing(id: id.value, with: stored) }
        return stored
    }

    public func deleteUserTechnique(id: UserTechniqueId) async throws {
        try await network.deleteUserTechnique(id: id)
        patch { $0.removing(id: id.value) }
    }

    /// Applies a write to the snapshot so a cached list cannot outlive the edit
    /// that changed it. Silent where there is nothing cached yet: the next
    /// successful fetch is what puts a complete list on disk, and half of one
    /// assembled from writes is worse than none.
    private func patch(_ change: (UserTechniqueList) -> UserTechniqueList) {
        guard let userId = identity.userId(),
              let stored = decoded.value ?? restored(),
              stored.userId == userId
        else { return }

        persist(change(stored.list))
    }

    /// Failure is logged and swallowed — the caller has the list it asked for,
    /// and an unwritable cache is the next launch's problem rather than a reason
    /// to fail this fetch. `CachedReferenceRepository.persist` makes the same
    /// trade for the same reason.
    private func persist(_ list: UserTechniqueList) {
        guard let userId = identity.userId() else { return }

        let stored = StoredList(userId: userId, list: list)
        decoded.value = stored
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Atomic, so a crash mid-write leaves the previous snapshot rather
            // than a truncated file that reads back as no exercises at all.
            try JSONEncoder().encode(stored).write(to: url, options: .atomic)
        } catch {
            Self.logger.notice(
                "failed to cache the composed exercises: \(error.diagnostic, privacy: .public)"
            )
        }
    }

    private func restored() -> StoredList? {
        // No file is the normal state until the first successful fetch, so it is
        // checked rather than caught — an expected condition should not log as
        // a failure.
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }

        do {
            let stored = try JSONDecoder().decode(StoredList.self, from: Data(contentsOf: url))
            decoded.value = stored
            return stored
        } catch {
            Self.logger.notice(
                "failed to read the cached exercises: \(error.diagnostic, privacy: .public)"
            )
            return nil
        }
    }
}

private extension UserTechniqueList {
    func appending(_ technique: Technique) -> UserTechniqueList {
        // At the end, which is where the server's oldest-first order would also
        // put a new one — the same rule `UserTechniqueModel.replace` follows.
        UserTechniqueList(techniques: techniques + [technique], limits: limits)
    }

    func replacing(id: String, with technique: Technique) -> UserTechniqueList {
        UserTechniqueList(
            techniques: techniques.map { $0.id == id ? technique : $0 },
            limits: limits
        )
    }

    func removing(id: String) -> UserTechniqueList {
        UserTechniqueList(techniques: techniques.filter { $0.id != id }, limits: limits)
    }
}
