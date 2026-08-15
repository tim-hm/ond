import Foundation

/// A full-screen session ready for presentation.
///
/// The identity belongs to the presentation rather than the underlying
/// technique: two taps on the same exercise are two launches, and
/// `fullScreenCover(item:)` needs to be able to tell them apart.
@MainActor
public struct PhoneSessionLaunch: Identifiable {
    public let id: UUID
    public let model: SessionModel

    /// Which vocabulary the session was built with.
    public let register: CopyRegister

    /// The occasion that prescribed the session, if one did.
    public let occasionSlug: String?

    init(model: SessionModel, register: CopyRegister, occasionSlug: String?) {
        id = UUID()
        self.model = model
        self.register = register
        self.occasionSlug = occasionSlug
    }
}

/// The order a discreet stop asks the phone to send to the wrist.
public struct WristSessionHandoff: Sendable, Equatable {
    public let occasionSlug: String?
    public let techniqueSlug: String
}

/// What resolving a request to begin breathing asks the app to present.
@MainActor
public enum SessionLaunchOutcome {
    /// A guided session this phone can present now.
    case phoneSession(PhoneSessionLaunch)

    /// A discreet session whose order belongs on the wrist.
    case wristHandoff(WristSessionHandoff)

    /// The requested technique needs a tier the person does not hold.
    case subscriptionRequired(SubscriptionTier)
}

/// Resolves every launch decision that is independent of SwiftUI.
///
/// The caller supplies the two concrete boundaries a session needs — cues and
/// recording — while this type owns the stable rules: entitlement precedes
/// surface routing, a stop's dose is applied once, and register and occasion
/// provenance travel together into the phone session. Keeping those decisions
/// in OndKit lets the host suite cover every route without importing an app
/// target or presenting a sheet.
@MainActor
public struct SessionLaunchResolver {
    private struct Request {
        let technique: Technique
        let surface: DeliverySurface
        let overrides: TechniqueOverrides?
        let register: CopyRegister
        let occasionSlug: String?
    }

    private let sessions: any SessionRecording
    private let makeCues: @MainActor () -> any SessionCueing

    /// Creates a resolver over the app's session boundaries.
    ///
    /// - Parameters:
    ///   - sessions: where a completed phone session is recorded.
    ///   - cues: creates fresh cue controllers for each phone session. It is not
    ///     called for a locked technique or a wrist handoff.
    public init(
        sessions: any SessionRecording,
        cues: @escaping @MainActor () -> any SessionCueing
    ) {
        self.sessions = sessions
        makeCues = cues
    }

    /// Resolves a dial stop exactly as its row states it.
    ///
    /// The stop already owns its selected surface, dialled dose, register and
    /// occasion. Reading them here keeps the duration printed on the row and
    /// the session that follows one value rather than two reconstructions.
    public func resolve(
        _ stop: DialStop,
        for tier: SubscriptionTier
    ) -> SessionLaunchOutcome {
        resolve(
            Request(
                technique: stop.technique,
                surface: stop.surface,
                overrides: stop.dose,
                register: stop.register,
                occasionSlug: stop.occasionSlug
            ),
            for: tier
        )
    }

    /// Resolves a technique that did not arrive through a dial stop.
    ///
    /// Notifications and coach offers are always full-screen but may supply a
    /// one-session dose. They use this entry point so the entitlement gate and
    /// model construction remain the same ones a dial stop uses.
    ///
    /// - Parameters:
    ///   - technique: the catalogue or personal exercise being requested.
    ///   - overrides: a saved or one-session dose, or `nil` for the curated
    ///     exercise.
    ///   - register: which session vocabulary to stamp onto the timeline.
    ///   - occasionSlug: the prescribing occasion, or `nil` for a direct start.
    ///   - tier: what the person may open now.
    public func resolvePhoneSession(
        _ technique: Technique,
        dialledWith overrides: TechniqueOverrides?,
        register: CopyRegister,
        occasionSlug: String?,
        for tier: SubscriptionTier
    ) -> SessionLaunchOutcome {
        resolve(
            Request(
                technique: technique,
                surface: .fullScreen,
                overrides: overrides,
                register: register,
                occasionSlug: occasionSlug
            ),
            for: tier
        )
    }

    private func resolve(
        _ request: Request,
        for tier: SubscriptionTier
    ) -> SessionLaunchOutcome {
        guard request.technique.isUnlocked(for: tier) else {
            return .subscriptionRequired(request.technique.requires)
        }

        if request.surface == .discreet {
            return .wristHandoff(WristSessionHandoff(
                occasionSlug: request.occasionSlug,
                techniqueSlug: request.technique.slug
            ))
        }

        let dialled = request.technique.dialled(with: request.overrides)
        let model = SessionModel(
            technique: dialled,
            cues: makeCues(),
            recorder: sessions,
            register: request.register,
            occasionSlug: request.occasionSlug
        )
        return .phoneSession(PhoneSessionLaunch(
            model: model,
            register: request.register,
            occasionSlug: request.occasionSlug
        ))
    }
}
