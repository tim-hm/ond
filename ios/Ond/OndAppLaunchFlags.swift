import OndKit
import SwiftUI

/// What this launch is, and what that entitles it to bend.
///
/// Every flag here is a Debug-only launch argument and a decision the app makes
/// differently because of one. Together rather than in the composition root:
/// they are read at composition time, but what they encode is which harness is
/// driving, and mixing that into the list of what an install holds is how the
/// root grew past reading as one.
extension OndApp {
    /// Whether a harness launch argument was passed, and always false outside
    /// Debug.
    ///
    /// The one place the `#if DEBUG` guard is written, which is the point of it
    /// being a function: every flag below used to spell the guard itself, and a
    /// fifth written without it would ship a test hook to the store. Read once
    /// per flag rather than per access — argv does not change under a running
    /// process, and the launch task these gate reads them on every appearance of
    /// the root view.
    static func launched(with flag: String) -> Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains(flag)
        #else
            false
        #endif
    }

    /// Whether this Debug launch belongs to the deterministic UI-test harness.
    static let isUiTesting = launched(with: "--ui-testing")

    /// Whether this launch may invent a heart rate rather than ask a wrist for
    /// one, and follow a session without being asked.
    ///
    /// A simulator has neither of the two pieces of hardware this feature needs,
    /// so the badge and the line the summary draws off the trace are otherwise
    /// unreachable on the machine the layout is worked on — and the preference
    /// that would show them is paywalled, so reaching them means buying önd+ off
    /// the StoreKit configuration first. The preference itself is left alone:
    /// writing it would persist into later launches, pre-check the onboarding
    /// opt-in, and draw a paid switch as on for somebody at the free tier.
    ///
    /// Debug *and* simulator, so nothing that leaves this Mac can invent a health
    /// figure: a Release build compiles the `false` arm and has no branch to
    /// take, and a Debug build on a real phone still reports only what a real
    /// watch sent. Not under `--ui-testing`, which runs in a simulator too and
    /// says what it wants — `-session.wristPulse NO` — in its own launch
    /// arguments; the screenshot run is the exception, because a live heart rate
    /// is one of the four things önd+ sells and the session shot is where the
    /// listing shows it.
    static var rehearsesWrist: Bool {
        #if DEBUG && targetEnvironment(simulator)
            !isUiTesting || wantsDemoPractice
        #else
            false
        #endif
    }

    /// Whether this launch should replace the practice history with the
    /// screenshot fixture. See [`DemoPractice`].
    ///
    /// Separate from [`isUiTesting`] rather than folded into it: the other UI
    /// tests assert against an install with no history, and seeding one under
    /// them would fail every assertion about an empty journal.
    static let wantsDemoPractice = launched(with: "--ui-testing-demo")

    /// Whether the screenshot harness wants first run opened on the trial step.
    ///
    /// A route rather than a walk, for `AppChrome.presentPaywallForUiTesting`'s
    /// reason: reaching that step is three taps, and leaving the opt-ins raises
    /// the system prompts for notifications and Health. Answering springboard
    /// alerts is the least reliable thing a capture can depend on.
    private static let startsOnTrialStep = launched(with: "--ui-testing-onboarding-trial")

    /// Which step first run opens on.
    static var onboardingStartStep: OnboardingModel.Step {
        startsOnTrialStep ? .trial : .welcome
    }

    /// Whether first run may end itself by restoring answers it recognises.
    ///
    /// `OnboardingView` leaves if `restoreIfPossible()` finds a profile behind
    /// the identity — right for somebody reinstalling, fatal to a capture, which
    /// shares an install with the listing set and so always finds one.
    static var restoresFirstRun: Bool {
        !startsOnTrialStep
    }

    /// Whether the one UI test that exercises first run is driving. Implied by
    /// [`startsOnTrialStep`], so a harness cannot ask for the step and still get
    /// a launch that shows Home.
    private static let showsFirstRun =
        launched(with: "--ui-testing-first-launch") || startsOnTrialStep

    /// Chooses the launch gate while allowing that test through it.
    ///
    /// The trial route asserts the gate rather than reading it: the screenshot
    /// classes share an install and the listing set runs first, so `records`
    /// answers "has onboarded" — correctly — and shows Home to a capture that
    /// asked for the offer.
    static func firstRunGate(for records: FirstRunRecords) -> FirstRunGate? {
        if startsOnTrialStep {
            return .onboarding
        }

        return isUiTesting && !showsFirstRun ? nil : records.gate
    }
}
