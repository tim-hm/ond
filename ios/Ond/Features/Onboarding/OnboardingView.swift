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

    /// What the trial step sells. From the environment rather than through the
    /// model: prices are StoreKit's answer about a storefront, while whether
    /// this person is entitled is the model's because that decides where the
    /// flow goes.
    @Environment(SubscriptionStore.self) private var plus

    /// Where the wrist-pulse grant is asked, on the way out of the opt-ins
    /// step. See [`leaveOptInsIfNeeded(_:)`].
    @Environment(PulseMonitor.self) private var pulse

    init(model: OnboardingModel, onFinished: @escaping () -> Void) {
        _model = State(wrappedValue: model)
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                step
                    .padding(.horizontal, Theme.Spacing.standard + Theme.Spacing.tight)
                    .padding(.top, Theme.Spacing.close)
                    .padding(.bottom, Theme.Spacing.loose)
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
                    .centredInScroller(isCentred)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.step)
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
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
            guard OndApp.restoresFirstRun else { return }

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

    /// Whether this step is centred in the screen rather than read from the top
    /// of it.
    ///
    /// The greeting alone. It is the one step with nothing to work down — no
    /// question, no control, no list — and it looks like a page that failed to
    /// load when it hugs the toolbar above an empty half-screen. Everything
    /// after it, the terms included, reads from the top: the terms are five
    /// points to get through, and a list starts where a list starts.
    private var isCentred: Bool {
        model.step == .welcome
    }

    @ViewBuilder
    private var step: some View {
        switch model.step {
        case .welcome: WelcomeStepView()
        case .you: YouStepView(model: model)
        case .optIns: OptInsStepView(model: model)
        case .trial: TrialStepView { model.advance() }
        case .safety: SafetyConsentStepView(terms: model.safetyTerms)
        }
    }

    /// One dot per visible step, the current one stretched — where you are and
    /// how much is left, read at a glance. The trial drops out for a subscriber,
    /// so the visual and spoken totals always describe the journey ahead.
    private var progress: some View {
        HStack(spacing: Theme.Spacing.close) {
            ForEach(model.progressSteps) { progressStep in
                Capsule()
                    .fill(progressStep == model.step ? Theme.Accent.brand : Theme.Surface.line)
                    .frame(width: progressStep == model.step ? 24 : 8, height: 8)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue(progressDescription)
    }

    private var progressDescription: String {
        let steps = model.progressSteps
        guard let position = steps.firstIndex(of: model.step) else { return "" }
        return "Step \(position + 1) of \(steps.count)"
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
                leaveOptInsIfNeeded { model.skip() }
            }
            .tint(Theme.Ink.secondary)
        }
    }

    /// The one primary action, in the same place on every non-offer screen.
    ///
    /// The trial draws its action inside `SubscriptionPitch`, directly beneath
    /// the plan tiles where the reference puts it. Every other step keeps this
    /// pinned action so a keyboard or a long safety term cannot hide the way
    /// forward.
    @ViewBuilder
    private var forward: some View {
        if let forwardTitle {
            Button {
                advance()
            } label: {
                Text(forwardTitle)
                    .primaryActionLabel()
                    .foregroundStyle(Theme.Action.brandLabel)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .tint(Theme.Accent.brand)
            .padding(.horizontal, Theme.Spacing.standard + Theme.Spacing.tight)
            .padding(.top, Theme.Spacing.close)
        }
    }

    /// Moves through the ordinary steps. The trial's embedded action owns its
    /// purchase and advances through the tier change watched above.
    private func advance() {
        leaveOptInsIfNeeded { model.advance() }
    }

    /// Asks for what the opt-ins step's answers imply, then moves.
    ///
    /// Around both buttons on that step rather than one, because Skip applies
    /// the same defaults Next does — a step passed by still leaves Mindful
    /// Minutes on and the dial at Once a day, and a permission implied by a
    /// stored preference should be asked for however the screen was left.
    ///
    /// `move` runs after the sheets are answered, so they are raised over the
    /// switches that explain them rather than over the offer on the next
    /// screen. On any other step this is the move and nothing else.
    ///
    /// The wrist grant sits here rather than in the model: `PulseMonitor` is
    /// the app's, and this is where the flow can reach one. `prepare` is
    /// per-process deduped, so Settings asking again later costs nothing.
    private func leaveOptInsIfNeeded(_ move: @escaping () -> Void) {
        guard model.step == .optIns else {
            move()
            return
        }

        Task {
            await model.requestOptInGrants()
            if model.optIns.showsWristPulse {
                await pulse.prepare()
            }
            move()
        }
    }

    private var forwardTitle: String? {
        switch model.step {
        case .welcome: "Get started"
        case .you, .optIns: "Next"
        case .trial: nil
        // The agreement's own words rather than "Next": what this button does is
        // record a consent, and it has to say so.
        case .safety: model.safetyTerms.agreement
        }
    }
}
