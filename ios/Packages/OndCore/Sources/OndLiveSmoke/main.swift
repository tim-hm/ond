import Darwin
import Foundation
import OndKit

/// An identity-free caller for the public catalogue smoke test.
private struct AnonymousIdentity: UserIdentityStore {
    func userId() -> UUID? {
        nil
    }

    func adopt(_: UUID) -> Bool {
        false
    }

    func sessionCredential() -> String? {
        nil
    }

    func adopt(sessionCredential _: String?) {}
}

@main
private enum OndLiveSmoke {
    static func main() async {
        guard CommandLine.arguments.count == 2,
              let baseURL = URL(string: CommandLine.arguments[1])
        else {
            fputs("usage: OndLiveSmoke <base-url>\n", stderr)
            exit(2)
        }

        do {
            let techniques = try await TechniqueRepository(
                baseURL: baseURL,
                identity: AnonymousIdentity()
            ).listTechniques()

            guard !techniques.isEmpty else {
                throw SmokeFailure("the live catalogue was empty")
            }
            guard techniques.contains(where: { $0.slug == "coherent-breathing" }) else {
                throw SmokeFailure("the live catalogue omitted coherent-breathing")
            }

            print("Swift/backend smoke passed: \(techniques.count) exercises")
        } catch {
            fputs("Swift/backend smoke failed: \(String(reflecting: error))\n", stderr)
            exit(1)
        }
    }
}

private struct SmokeFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
