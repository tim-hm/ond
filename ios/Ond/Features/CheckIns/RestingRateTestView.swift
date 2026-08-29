import OndKit
import OndUI
import SwiftUI

/// The resting-rate check-in: count your breaths for a minute, sitting still.
/// The measurement's whole difficulty is that watching your breathing changes
/// it, so the copy works at that rather than around it. A full minute rather
/// than fifteen seconds multiplied: the short version turns one miscounted
/// breath into four, and people compare this number against a clinical range.
struct RestingRateTestView: View {
    let model: JourneyModel

    /// How long the count runs. A minute, so the tally *is* the rate and there
    /// is no arithmetic between what somebody counted and what gets recorded.
    private static let window: TimeInterval = 60

    /// What the recorded rate is allowed to be, matching the server's own
    /// `CHECK` on `resting_rates.breaths_per_minute`. Outside it the person
    /// stopped tapping or was not at rest, and either way it is not the
    /// measurement — so nothing is stored and the screen says which.
    private static let plausible = 4 ... 60

    /// Which part of the check-in is on screen. An enum rather than a pile of
    /// booleans, for `BoltTestView`'s reason: exactly one is true at a time.
    private enum Stage: Equatable {
        case explain
        case counting(until: Date)
        case result(breathsPerMinute: Int, isLowest: Bool)
        /// A tally outside [`plausible`], carried so the copy can name it.
        case implausible(breaths: Int)
    }

    @State private var stage: Stage = .explain

    /// The running tally, held outside `stage` so a tap redraws a number rather
    /// than replacing the stage the countdown's `task` is keyed on.
    @State private var breaths = 0

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.loose) {
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            action
        }
        .padding(Theme.Spacing.loose)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Surface.ground)
        .navigationTitle("Resting breathing rate")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .explain:
            instructions
        case let .counting(until):
            counting(until: until)
        case let .result(rate, isLowest):
            result(breathsPerMinute: rate, isLowest: isLowest)
        case let .implausible(breaths):
            implausible(breaths: breaths)
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Text("This counts the breathing you were doing anyway.")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                bullet("Sit down and settle for a minute before you start.")
                bullet("Breathe through your nose, however you were already breathing.")
                bullet("Tap once for each breath out. A minute, then it stops itself.")
                bullet(
                    "Noticing your breath changes it. That's normal — let it be whatever it is "
                        + "and count that."
                )
                bullet("Best taken at the same time of day, before you practise rather than after.")
            }
            .font(.callout)
            .foregroundStyle(Theme.Ink.secondary)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.close) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(Theme.Accent.attend)
                // Typography, not information — see `BoltTestView.bullet`.
                .accessibilityHidden(true)
            Text(text)
        }
    }

    /// The tally and the seconds left, above the button that counts.
    /// `TimelineView` rather than a `Timer`, for `BoltTestView`'s reason. The
    /// `task` beside it is what ends the count — keyed on the deadline so it
    /// is armed once, and cancelled with the view if somebody leaves mid-count.
    private func counting(until deadline: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: Theme.Spacing.standard) {
                Text("\(breaths)")
                    .displayNumeral(size: 72)
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.Accent.attend)

                Text("\(remaining(until: deadline, at: context.date))s left")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Theme.Ink.secondary)

                Text("Tap the button for each breath out.")
                    .font(.callout)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(breaths) breaths, \(remaining(until: deadline, at: context.date)) seconds left"
            )
        }
    }

    private func result(breathsPerMinute rate: Int, isLowest: Bool) -> some View {
        VStack(spacing: Theme.Spacing.standard) {
            Text("\(rate)")
                .displayNumeral(size: 72)
                .foregroundStyle(Theme.Accent.attend)

            Text("breaths per minute")
                .font(.callout)
                .foregroundStyle(Theme.Ink.secondary)

            Text(isLowest ? "Your slowest yet." : "Recorded.")
                .font(.title3.weight(.semibold))

            Text(
                "Twelve to twenty is the usual range at rest, and slow breathing practice "
                    + "tends to bring it down over weeks rather than days. One reading says "
                    + "less than the shape of a few over a month."
            )
            .font(.callout)
            .foregroundStyle(Theme.Ink.secondary)
            .multilineTextAlignment(.center)
        }
    }

    /// Nothing recorded, and the reason named rather than a silent discard: the
    /// person spent a minute on this and is owed an account of where it went.
    private func implausible(breaths: Int) -> some View {
        VStack(spacing: Theme.Spacing.standard) {
            Text(breaths < Self.plausible.lowerBound ? "Too few to read" : "Too many to read")
                .font(.title3.weight(.semibold))

            Text(
                breaths < Self.plausible.lowerBound
                    ? "\(breaths) in a minute is slower than resting breathing goes, so this "
                    + "one isn't recorded. If you were practising rather than resting, "
                    + "that's the reason — take it before you practise instead."
                    : "\(breaths) in a minute is faster than resting breathing goes. Settle "
                    + "for a few minutes and take it again."
            )
            .font(.callout)
            .foregroundStyle(Theme.Ink.secondary)
            .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var action: some View {
        switch stage {
        case .explain:
            button("I'm settled — start counting") {
                breaths = 0
                stage = .counting(until: .now + Self.window)
            }
        case let .counting(deadline):
            countingButton(until: deadline)
        case .result:
            button("Done") { dismiss() }
        case .implausible:
            button("Try again") { stage = .explain }
        }
    }

    /// The tap target and the end of the count in one place, because both are
    /// only live while the count is.
    private func countingButton(until deadline: Date) -> some View {
        Button("I breathed out") { breaths += 1 }
            .buttonStyle(.inkAction)
            .sensoryFeedback(.impact(weight: .light), trigger: breaths)
            .task(id: deadline) {
                // Slept to the deadline rather than counted down, so a screen
                // that was off or a redraw that was skipped does not lose time
                // from the minute. Cancellation — leaving mid-count — throws and
                // records nothing, which is the right answer for an abandoned
                // measurement.
                let left = deadline.timeIntervalSinceNow
                guard left > 0, await (try? Task.sleep(for: .seconds(left))) != nil else { return }
                await finish()
            }
    }

    private func finish() async {
        let counted = breaths
        guard Self.plausible.contains(counted) else {
            stage = .implausible(breaths: counted)
            return
        }

        let isLowest = await model.record(restingBreaths: counted)
        stage = .result(breathsPerMinute: counted, isLowest: isLowest)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.inkAction)
    }

    /// Whole seconds left, floored at zero — the last tick before the deadline
    /// should read "0s left" rather than a negative number.
    private func remaining(until deadline: Date, at now: Date) -> Int {
        max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }
}
