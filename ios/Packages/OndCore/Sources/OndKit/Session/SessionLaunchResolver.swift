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
    public let occasionSlug: OccasionSlug?

    init(model: SessionModel, register: CopyRegister, occasionSlug: OccasionSlug?) {
        id = UUID()
        self.model = model
        self.register = register
        self.occasionSlug = occasionSlug
    }
}

/// The order a discreet stop asks the phone to send to the wrist.
public struct WristSessionHandoff: Sendable, Equatable {
    public let occasionSlug: OccasionSlug?
    public let techniqueSlug: TechniqueSlug
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

/// Resolves every launch decision that is independent of SwiftUI. The caller
/// supplies the concrete boundaries — cues and recording — while this type
/// owns the stable rules: entitlement precedes surface routing, a stop's
/// resolved session is reused, and register and occasion provenance travel
/// together. Living in OndKit lets the host suite cover every route.
@MainActor
public struct SessionLaunchResolver {
    private struct Request {
        let technique: Technique
        let surface: DeliverySurface
        let register: CopyRegister
        let occasionSlug: OccasionSlug?
        let title: String?
        let warning: SessionWarning?
    }

    private let sessions: any SessionRecording
    private let makeCues: @MainActor () -> any SessionCueing

    /// Creates a resolver over the app's session boundaries: `sessions` is
    /// where a completed phone session is recorded, and `cues` makes fresh cue
    /// controllers per phone session — never called for a locked technique or
    /// a wrist handoff.
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
                technique: stop.dialled,
                surface: stop.surface,
                register: stop.register,
                occasionSlug: stop.occasionSlug,
                title: stop.title,
                warning: stop.warning
            ),
            for: tier
        )
    }

    /// Resolves a technique that did not arrive through a dial stop.
    /// Notifications and coach offers are always full-screen, plain, and
    /// unprescribed, but may supply a dose via `overrides` (`nil` is the
    /// curated exercise). This entry point keeps their entitlement gate and
    /// model construction the same ones a dial stop uses.
    public func resolvePhoneSession(
        _ technique: Technique,
        dialledWith overrides: TechniqueOverrides?,
        for tier: SubscriptionTier
    ) -> SessionLaunchOutcome {
        resolve(
            Request(
                technique: technique.dialled(with: overrides),
                surface: .fullScreen,
                register: .plain,
                occasionSlug: nil,
                title: nil,
                warning: technique.sessionWarning
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

        let model = SessionModel(
            technique: request.technique,
            cues: makeCues(),
            recorder: sessions,
            register: request.register,
            occasionSlug: request.occasionSlug,
            title: request.title,
            warning: request.warning
        )
        return .phoneSession(PhoneSessionLaunch(
            model: model,
            register: request.register,
            occasionSlug: request.occasionSlug
        ))
    }
}
