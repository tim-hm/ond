import Foundation
import OndAPI

public enum EntitlementRepositoryError: LocalizedError, Equatable {
    /// The RPC itself failed — no network, server down, non-OK gRPC status
    /// short of a refusal. Retryable by waiting: the next launch resubmits.
    case transport(String)

    /// The server verified the transaction and refused it — `INVALID_ARGUMENT`,
    /// carrying the verifier's reason verbatim. Not retryable: the same bytes
    /// will be refused the same way, so the caller's job is to say *why* —
    /// which the reason does, and which is the difference between a dev build
    /// working as designed and a paying customer's purchase not being honoured.
    case rejected(String)

    /// Carries the associated message. Without this conformance
    /// `localizedDescription` bridges to a bare `NSError`, and every log line
    /// and failure banner reading it says "The operation couldn't be completed".
    public var errorDescription: String? {
        switch self {
        case let .transport(message): "the request failed: \(message)"
        case let .rejected(reason): "the server refused the transaction: \(reason)"
        }
    }
}

/// Carries a purchase to the server, and nothing back.
///
/// Deliberately one-way. `StoreKit` is the authority on what this app shows —
/// it answers offline and needs no round trip — so a read here would be a second
/// opinion about a question already settled. What the server holds decides only
/// what the server spends, which is the assistant's allowance, and this app
/// never needs to know that number.
public protocol EntitlementSyncing: Sendable {
    /// Submits a `Transaction.jwsRepresentation` for verification.
    ///
    /// Idempotent on the server, which is what makes the retry policy trivial:
    /// resubmitting the same transaction writes the same entitlement rather than
    /// a second one.
    func submit(_ signedTransaction: String) async throws
}

/// The only type that touches the generated entitlement types, mirroring
/// `ProfileRepository`.
public struct EntitlementRepository: EntitlementSyncing {
    private let client: Ond_V1_EntitlementServiceClient

    public init(baseURL: URL, identity: any UserIdentityStore) {
        client = OndClients.entitlementService(
            baseURL: baseURL,
            userId: identity.userId,
            sessionCredential: identity.sessionCredential
        )
    }

    public func submit(_ signedTransaction: String) async throws {
        var request = Ond_V1_SubmitAppStoreTransactionRequest()
        request.signedTransaction = signedTransaction

        let response = await client.submitAppStoreTransaction(request: request)

        guard response.message != nil else {
            let reason = response.error.responseMessage
            switch response.code {
            case .invalidArgument: throw EntitlementRepositoryError.rejected(reason)
            default: throw EntitlementRepositoryError.transport(reason)
            }
        }
    }
}
