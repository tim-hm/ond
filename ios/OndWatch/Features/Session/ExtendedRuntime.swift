import Foundation
import Observation
import OndKit
import os
import WatchKit

@MainActor
@Observable
final class ExtendedRuntime: NSObject {
    enum State: Equatable {
        case idle, starting, running, unavailable
    }

    private(set) var state = State.idle
    private nonisolated static let logger = Logger(category: "session-runtime")
    @ObservationIgnored private var session: WKExtendedRuntimeSession?

    func start() {
        guard session == nil else { return }
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session
        state = .starting
        session.start()
        let identity = ObjectIdentifier(session)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, state == .starting else { return }
            update(.unavailable, for: identity)
        }
    }

    func invalidate() {
        let previous = session
        session = nil
        state = .idle
        previous?.invalidate()
    }

    private func update(_ state: State, for identity: ObjectIdentifier) {
        guard let session, ObjectIdentifier(session) == identity else { return }
        self.state = state
        if state == .unavailable {
            self.session = nil
            session.invalidate()
        }
    }
}

extension ExtendedRuntime: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
        let identity = ObjectIdentifier(session)
        Task { @MainActor in self.update(.running, for: identity) }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        let identity = ObjectIdentifier(session)
        Task { @MainActor in self.update(.unavailable, for: identity) }
    }

    nonisolated func extendedRuntimeSession(
        _ session: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: (any Error)?
    ) {
        Self.logger.notice("extended runtime ended: reason \(reason.rawValue)")
        if let error {
            Self.logger
                .notice("extended runtime error: \(error.localizedDescription, privacy: .public)")
        }
        let identity = ObjectIdentifier(session)
        Task { @MainActor in self.update(.unavailable, for: identity) }
    }
}
