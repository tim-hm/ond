import OndKit
import OndUI
import SwiftUI

/// The first thing anyone sees: what the app stands on, two questions, an offer,
/// and the safety terms.
///
/// This type is the chrome around them — the toolbar, the switch that picks a
/// step, and the one button — while each step is its own `-StepView` beside this
/// file. They are independent screens that share only that switch, and the
/// layout the questions do share is `OnboardingQuestion`.
///
/// The chrome is the platform's rather than this flow's own: Back at the
/// top-leading edge, Skip at the trailing one, the step indicator between them,
/// and a single full-width button at the bottom. It replaced a two-row control
/// cluster that put Back and Skip *under* the primary action, where nothing else
/// on iOS puts them — a flow somebody meets once should spend none of its credit
/// teaching them where its buttons are.
///
/// Drawn in the brand accent rather than a goal's, because nothing here belongs
/// to a technique yet. Every screen but the last can be passed by: the flow
/// exists to make the app better at its job, not to collect a record before
/// somebody is allowed to breathe.
struct OnboardingView: View {
    @State private var model: OnboardingModel

    /// Called when the person leaves the flow. Presentation is the app's
    /// business; by the time this fires the answers are already stored.
    private let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the trial step sells and what the button below it buys. From the
    /// environment rather than through the model: the *prices* are `StoreKit`'s
    /// answer about a storefront, which is chrome rather than an onboarding
    /// answer. Whether this person is already entitled is the model's, because
    /// that decides where the flow goes.
    @Environment(SubscriptionStore.self) private var plus

    /// Read for one question at the very end — whether the wrist pulse was
    /// switched on — so the grant it needs can be asked for over Home.
    @Environment(SessionSettings.self) private var settings

    /// Where that grant is asked. See the finish handler below.
    @Environment(PulseMonitor.self) private var pulse

    /// Holds the forward button's glass across steps, so it morphs between
    /// screens instead of being torn down and rebuilt: `forwardTitle` renames it
    /// at most of them, and without an identity each new word arrives on a new
    /// slab of glass.
    @Namespace private var forwardGlass

    init(model: OnboardingModel, onFinished: @escaping () -> Void) {
        _model = State(wrappedValue: model)
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                step
                    .padding(.horizontal, Theme.Spacing.standard)
                    .padding(.vertical, Theme.Spacing.loose)
                    // One screen blurs into the next, and a plain cross-fade is
                    // what Reduce Motion gets instead. The `id` is what makes
                    // either of them fire: without it the switch below swaps its
                    // branches inside a view whose identity never changes, and a
                    // transition on a view that is never inserted or removed does
                    // nothing at all.
                    //
                    // Both sides spelled as `AnyTransition` because the two do not
                    // otherwise share a type — `blurReplace` is a `Transition` and
                    // `opacity` is not — and a ternary needs one.
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
                    .id(model.step)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.step)
            .scrollDismissesKeyboard(.interactively)
            // An inset rather than a `VStack`: the button then floats over the
            // question, the system fades content under it at the scroll edge,
            // and a raised keyboard lifts it clear of the name field without
            // anything here tracking the focus.
            .safeAreaInset(edge: .bottom) { forward }
            .paletteGround()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { back }
                ToolbarItem(placement: .principal) { progress }
                ToolbarItem(placement: .topBarTrailing) { skip }
            }
        }
        // The ground reaches the status bar and the home indicator, which a
        // background inside the safe area cannot: a cover otherwise keeps the
        // system's own backdrop in both margins, and that is white by day and
        // pure black at night — neither of them this palette.
        .presentationBackground(Theme.Surface.ground)
        // Somebody reinstalling has answered all this before, and the identity
        // that survived in the Keychain can prove it. The flow is drawn first
        // and leaves by itself if the answers arrive.
        .task {
            if await model.restoreIfPossible() {
                onFinished()
            }
        }
        // Started when the flow opens rather than when the offer appears: it is
        // an App Store round trip, and asking for it two screens late means the
        // trial step renders priceless for as long as the network takes. The
        // load is count-guarded, so this is the only call.
        .task { await plus.loadProducts() }
        .onChange(of: model.isFinished) { _, isFinished in
            guard isFinished else { return }

            onFinished()
            // After the cover goes, deliberately. Honouring the wrist-pulse
            // switch needs a Health grant, and requesting one shows a system
            // sheet — the same sheet Settings' own switch asks for on the spot.
            // The opt-ins step promised no sheets, so the debt is paid here,
            // over Home, beside the notification prompt the reminder seeding
            // raises. `prepare` is per-process deduped, so a second call from
            // Settings later costs nothing.
            if settings.showsWristPulse {
                Task { await pulse.prepare() }
            }
        }
        // A purchase made on the trial step moves the tier rather than
        // returning anything, so this is what carries somebody on afterwards —
        // it also covers an Ask to Buy approved while the screen is still up.
        //
        // Triggered on the tier and *decided* by the model: what counts as
        // entitled is a rule the flow already states, for the hop it makes when
        // the step is reached, and this must not be a second copy of it. The
        // trigger stays the store's own property because that is the value
        // observation is unambiguous about.
        .onChange(of: plus.tier) { _, _ in
            if model.step == .trial, model.isEntitled {
                model.advance()
            }
        }
    }

    @ViewBuilder
    private var step: some View {
        switch model.step {
        case .welcome: WelcomeStepView()
        case .you: YouStepView(model: model)
        case .optIns: OptInsStepView(model: model)
        case .trial: TrialStepView()
        case .safety: SafetyConsentStepView(terms: model.safetyTerms)
        }
    }

    /// One dot per counted step, the current one stretched — where you are and
    /// how much is left, read at a glance. Only on the three it counts: the
    /// welcome and the safety terms are not places to be part-way through, and
    /// a row of dots with none of them lit is worse than no row at all.
    @ViewBuilder
    private var progress: some View {
        if model.countedSteps.contains(model.step) {
            HStack(spacing: Theme.Spacing.close) {
                ForEach(model.countedSteps) { counted in
                    Capsule()
                        .fill(counted == model.step ? Theme.Accent.brand : Theme.Surface.line)
                        .frame(width: counted == model.step ? 24 : 8, height: 8)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Setup progress")
            .accessibilityValue(progressDescription)
        }
    }

    private var progressDescription: String {
        let counted = model.countedSteps
        guard let position = counted.firstIndex(of: model.step) else { return "" }
        return "Step \(position + 1) of \(counted.count)"
    }

    /// A chevron rather than the word, which is what every other back control
    /// on the platform is. Hidden rather than dimmed where there is nothing
    /// behind: a permanently grey chevron on the first screen is chrome that
    /// never does anything.
    @ViewBuilder
    private var back: some View {
        if model.canGoBack {
            Button {
                model.back()
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Back")
            .tint(Theme.Ink.secondary)
        }
    }

    /// The way past a screen without engaging with it, worded for what
    /// declining means there — "Not now" on the offer, because "Skip" reads as
    /// leaving something unfinished and nobody owes this app a subscription.
    @ViewBuilder
    private var skip: some View {
        if model.canSkip {
            Button(model.step == .trial ? "Not now" : "Skip") {
                model.skip()
            }
            .tint(Theme.Ink.secondary)
        }
    }

    /// The one primary action, in the same place on every screen.
    private var forward: some View {
        // A container so the button's glass lives in a layer of its own, which
        // is what lets the pill morph between steps rather than being redrawn.
        GlassEffectContainer {
            Button {
                advance()
            } label: {
                // Inside the label, which is the whole point: a `frame` hung on
                // the button itself draws a shape the button does not consider
                // part of itself, and every tap that lands beside the word
                // misses. `primaryActionLabel` is that geometry, shared with
                // every other concluding action.
                Text(forwardTitle)
                    .primaryActionLabel()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Theme.Accent.brand)
            .glassEffectID(Control.forward, in: forwardGlass)
            .disabled(model.step == .trial && plus.isBusy)
        }
        .padding(.horizontal, Theme.Spacing.standard)
        .padding(.top, Theme.Spacing.close)
    }

    /// The control whose glass persists across steps, named so
    /// `glassEffectID` has something stable to hold it by.
    private enum Control {
        case forward
    }

    /// On the trial step the button buys; everywhere else it moves on.
    ///
    /// The purchase does not advance on its own — the tier changing is what
    /// does that, watched above — so a cancelled sheet leaves somebody exactly
    /// where they were, with "Not now" still in the corner.
    private func advance() {
        guard model.step == .trial, plus.offer(for: plus.trialPlan) != .unavailable else {
            model.advance()
            return
        }

        Task { await plus.purchase(plus.trialPlan) }
    }

    private var forwardTitle: String {
        switch model.step {
        case .welcome: "Get started"
        case .you, .optIns: "Next"
        case .trial: trialTitle
        // The agreement's own words rather than "Next": what this button does is
        // record a consent, and it has to say so.
        case .safety: model.safetyTerms.agreement
        }
    }

    /// What the button on the offer says, which depends on what the App Store
    /// answered with.
    ///
    /// "Continue" where it answered with nothing at all — no signal, or a build
    /// with no `StoreKit` configuration — because a Subscribe button over a
    /// product that does not exist is a tap that can only fail. That is the
    /// offline degradation: the screen still says what önd+ is, and moves on.
    private var trialTitle: String {
        guard plus.offer(for: plus.trialPlan) != .unavailable else { return "Continue" }

        return plus.purchaseTitle(for: plus.trialPlan)
    }
}
