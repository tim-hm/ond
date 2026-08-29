import OndKit
import SwiftUI

/// What this launch is, and what that entitles it to bend. Every flag is a
/// Debug-only launch argument. Kept apart from the composition root: what
/// they encode is which harness is driving, and mixing that into the list of
/// what an install holds is how the root grew past reading as one.
extension OndApp {
    /// Whether a harness launch argument was passed; always false outside
    /// Debug. The one place the `#if DEBUG` guard is written — a flag
    /// spelling its own guard and missing it would ship a test hook to the
    /// store. Read once per flag: argv never changes, and the launch task
    /// these gate reads them on every appearance of the root view.
    static func launched(with flag: String) -> Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains(flag)
        #else
            false
        #endif
    }

    /// Whether this Debug launch belongs to the deterministic UI-test harness.
    static let isUiTesting = launched(with: "--ui-testing")

    /// May this launch invent a heart rate? A simulator lacks the hardware
    /// and the preference showing the result is paywalled — and left
    /// unwritten: it would persist and draw a paid switch as on at free tier.
    /// Debug AND simulator, so nothing leaving this Mac invents health data.
    /// UI tests opt out in their own args; the screenshot run must show önd+.
    static var rehearsesWrist: Bool {
        #if DEBUG && targetEnvironment(simulator)
            !isUiTesting || wantsDemoPractice
        #else
            false
        #endif
    }

    /// Whether this launch should replace the practice history with the
    /// screenshot fixture — see [`DemoPractice`]. Separate from
    /// [`isUiTesting`]: the other UI tests assert against an empty journal.
    static let wantsDemoPractice = launched(with: "--ui-testing-demo")

    /// Which step the screenshot harness wants first run opened on. A route
    /// rather than a walk: tapping there raises the system prompts for
    /// notifications and Health, and answering springboard alerts is the
    /// least reliable thing a capture can depend on.
    private static let onboardingFixtureStep: OnboardingModel.Step? = {
        if launched(with: "--ui-testing-onboarding-trial") {
            return .trial
        }
        if launched(with: "--ui-testing-onboarding-safety") {
            return .safety
        }
        return nil
    }()

    /// Which step first run opens on.
    static var onboardingStartStep: OnboardingModel.Step {
        onboardingFixtureStep ?? .welcome
    }

    /// Whether first run may end itself by restoring answers it recognises.
    ///
    /// `OnboardingView` leaves if `restoreIfPossible()` finds a profile behind
    /// the identity — right for somebody reinstalling, fatal to a capture, which
    /// shares an install with the listing set and so always finds one.
    static var restoresFirstRun: Bool {
        onboardingFixtureStep == nil
    }

    /// Whether the one UI test that exercises first run is driving. Implied by
    /// [`onboardingFixtureStep`], so a harness cannot ask for a step and still
    /// get a launch that shows Home.
    private static let showsFirstRun =
        launched(with: "--ui-testing-first-launch") || onboardingFixtureStep != nil

    /// Chooses the launch gate while allowing that test through it. A fixture
    /// route asserts the gate rather than reading it: the screenshot classes
    /// share an install and the listing set runs first, so `records` answers
    /// "has onboarded" and would otherwise show Home to the capture.
    static func firstRunGate(for records: FirstRunRecords) -> FirstRunGate? {
        if onboardingFixtureStep != nil {
            return .onboarding
        }

        return isUiTesting && !showsFirstRun ? nil : records.gate
    }
}
