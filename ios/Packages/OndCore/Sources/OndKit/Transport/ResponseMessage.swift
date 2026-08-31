import Foundation

/// Connect guarantees a failed response carries an error, so the `nil` arm is
/// unreachable — the fallback exists to keep each repository's failure builder
/// total rather than force-unwrapping a library invariant, and to stop seven
/// copies of the same impossible-state sentence drifting apart.
extension Optional where Wrapped: Error {
    /// The error's message, or the one sentence for the invariant violation.
    var responseMessage: String {
        self?.localizedDescription ?? "the server sent no message"
    }
}
