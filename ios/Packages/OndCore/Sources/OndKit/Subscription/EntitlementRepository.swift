import Foundation
import OndAPI

public enum EntitlementRepositoryError: LocalizedError, DiagnosticCarrying, Equatable {
    /// The RPC itself failed — no network, server down, non-OK gRPC status
    /// short of a refusal. Retryable by waiting: the next launch resubmits.
    ///
    /// Carries the classified outcome for the person and the transport's own
    /// words for the log — see [`TransportFault`].
    case transport(TransportFault)

    /// The server verified the transaction and refused it — `INVALID_ARGUMENT`,
    /// carrying the verifier's reason verbatim. Not retryable: the same bytes
    /// will be refused the same way, so the caller's job is to say *why* —
    /// which the reason does, and which is the difference between a dev build
    /// working as designed and a paying customer's purchase not being honoured.
    case rejected(String)

    /// The transaction is real but bound to another installation, inside the
    /// server's transfer cooldown (`PERMISSION_DENIED`). The honest case is a
    /// reinstall: the purchase is held, not broken, and moves over within a
    /// day. Distinct from `.transport` because retrying now cannot help, and
    /// from `.rejected` because time will — the screen must say "wait".
    case held(String)

    /// Carries the associated message; without this conformance
    /// `localizedDescription` bridges to a bare `NSError` saying "The
    /// operation couldn't be completed". The two refusals keep the server's
    /// own reason — the verifier's words are the only ones that say why a
    /// purchase was not honoured.
    public var errorDescription: String? {
        switch self {
        case let .transport(fault): fault.outcome.message
        case let .rejected(reason): reason
        case let .held(reason): reason
        }
    }

    /// What a log records — the transport's own words, kept off the screen.
    public var diagnostic: String {
        switch self {
        case let .transport(fault): fault.diagnostic
        case let .rejected(reason): "the server refused the transaction: \(reason)"
        case let .held(reason): "the transaction is held by the transfer cooldown: \(reason)"
        }
    }
}

/// Carries a purchase to the server, and nothing back. Deliberately one-way:
/// `StoreKit` is the authority on what this app shows and answers offline, so
/// a read here would be a second opinion on a settled question. What the
/// server holds decides only what the server spends — the assistant's
/// allowance — and this app never needs to know that number.
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
            userId: identity.wireUserId,
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
            case .permissionDenied: throw EntitlementRepositoryError.held(reason)
            default: throw EntitlementRepositoryError.transport(
                    TransportFault(outcome: response.transportOutcome, diagnostic: reason)
                )
            }
        }
    }
}
