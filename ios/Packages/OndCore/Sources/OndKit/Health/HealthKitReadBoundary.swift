import Foundation
import os

/// The HealthKit operation that failed without becoming a product error.
enum HealthKitReadOperation: Sendable, Equatable {
    /// Asking the system for a sample type's grant.
    case authorization
    /// Reading samples or statistics after that ask.
    case query
}

/// A safe diagnostic description of one failed HealthKit operation.
///
/// Deliberately has no quantity, date, or sample object fields: logging code
/// cannot disclose a measurement it was never handed.
struct HealthKitReadFailure: Sendable, Equatable {
    let operation: HealthKitReadOperation
    let sampleType: String
    let reason: String
}

/// Turns HealthKit read failures into absence while leaving a log trail.
///
/// The generic operation keeps the behavior host-testable without importing
/// HealthKit. Its diagnostic carries the sample type and framework-authored
/// reason only; no quantity or sample timestamp crosses the logging boundary.
struct HealthKitReadBoundary: Sendable {
    private static let logger = Logger(category: "health")

    private let report: @Sendable (HealthKitReadFailure) -> Void

    init(report: @escaping @Sendable (HealthKitReadFailure) -> Void) {
        self.report = report
    }

    init() {
        self.init { failure in
            switch failure.operation {
            case .authorization:
                // `notice`, so a refused grant reaches the on-disk store a
                // sysdiagnose collects: it is the cause of every empty reading
                // after it. Written once per sample type each time somebody
                // asks, which is a person's tap rather than a loop.
                Self.logger.notice(
                    "health authorization failed; sample_type=\(failure.sampleType, privacy: .public); reason=\(failure.reason, privacy: .public)"
                )
            case .query:
                // `debug`: a query fails once per statistics window, which is too
                // repetitive to keep.
                Self.logger.debug(
                    "health query failed; sample_type=\(failure.sampleType, privacy: .public); reason=\(failure.reason, privacy: .public)"
                )
            }
        }
    }

    /// Runs one optional HealthKit operation and reports failures per type.
    /// `sampleTypes` are stable HealthKit identifiers, never sample contents;
    /// `isolation` inherits the caller so an actor may safely use its store.
    /// Returns the operation's value, or nil after a reported failure.
    func perform<Value>(
        _ operation: HealthKitReadOperation,
        sampleTypes: [String],
        isolation _: isolated (any Actor)? = #isolation,
        body: () async throws -> Value
    ) async -> Value? {
        do {
            return try await body()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return nil }
            for sampleType in sampleTypes {
                report(HealthKitReadFailure(
                    operation: operation,
                    sampleType: sampleType,
                    reason: error.localizedDescription
                ))
            }
            return nil
        }
    }
}
