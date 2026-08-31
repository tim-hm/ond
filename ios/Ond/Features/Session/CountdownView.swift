import OndKit
import OndUI
import SwiftUI

/// The breath before the breathing: a beat to settle before the plan's clock
/// starts. Three seconds, not a preference — long enough to put the phone
/// down. The optional check-in is drawn under the count, not behind a button;
/// answering holds the count for the write, then counts again from three.
/// Cancel exists for whoever tapped Begin and then thought better of it.
struct CountdownView: View {
    /// Seconds left. The screen presenting this owns the count, because the same
    /// value decides whether this view or the player is on screen at all.
    let count: Int
    /// Which words to settle somebody in.
    let register: CopyRegister
    /// What to do with your body before the first breath, or nil where the
    /// exercise asks for nothing. It lives here because this is the one beat
    /// of a session with attention to spare and nothing counting: the line
    /// beside each breath is read at a glance and cannot hold a sentence.
    let preparation: String?
    /// Whether this countdown still offers its optional reflection.
    let showsCheckIn: Bool
    /// The point already tapped on that reflection, or nil while it stands
    /// unanswered — which is also how it is skipped.
    let mood: Mood?
    /// Whether VoiceOver is holding the automatic count for an explicit start.
    let waitsForStart: Bool
    let onMood: (Mood) -> Void
    let onStart: () -> Void
    let onCancel: () -> Void

    @Environment(SessionSettings.self) private var settings

    var body: some View {
        // Scrolls rather than clips: at an accessibility size the settling
        // lines, a preparation sentence, the numeral and a stacked scale are
        // taller than the screen. Where they fit, the plain layout is taken
        // instead — a scroll view centres on fractions of a point, and a
        // control laid out across one measures under the minimum tap target.
        ViewThatFits(in: .vertical) {
            content

            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(Theme.Ink.primary)
    }

    private var content: some View {
        VStack(spacing: Theme.Spacing.loose) {
            VStack(spacing: Theme.Spacing.loose) {
                VStack(spacing: Theme.Spacing.close) {
                    Text(register.settlingLine)
                        .font(.title2.weight(.medium))
                    // No step down in tone: this is drawn over
                    // `accentGround(_:)`, where secondary ink measures 3.26:1
                    // at `.subheadline`.
                    Text(register.countdownLine)
                        .font(.subheadline)
                }
                // `SessionView.runCountdown` announces each second for
                // VoiceOver, on the same beat the sighted see, so there is
                // nothing in the lead or the numeral to read.
                .accessibilityHidden(true)

                // Left navigable rather than announced: three seconds cannot
                // carry a spoken sentence, and each second's count interrupts
                // the one before it — a listener reaches it at their own pace.
                if let preparation {
                    Text(preparation)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }

                Text("\(count)")
                    .displayNumeral(size: 96, design: .rounded)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeInOut(duration: 0.3), value: count)
                    .accessibilityHidden(true)
            }
            // On the count alone — the controls below must stay reachable.
            .sensoryFeedback(.impact(weight: .light), trigger: count) { _, _ in
                settings.cueMode.playsHaptics
            }

            if showsCheckIn {
                checkIn
            }

            VStack(spacing: Theme.Spacing.close) {
                if waitsForStart {
                    Button("Start countdown", action: onStart)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                Button("Cancel", action: onCancel)
                    .font(.subheadline)
                    .tapTarget()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.loose)
    }

    /// The way in to the mood check, drawn rather than offered behind a button:
    /// one tap is the whole of it, and a tap is cheaper than a screen. Ignoring
    /// it is how it is skipped, which is why there is nothing here to decline.
    private var checkIn: some View {
        VStack(spacing: Theme.Spacing.standard) {
            Text(MoodCheckModel.questionBefore)
                .font(.subheadline)
                .multilineTextAlignment(.center)

            MoodScale(selection: mood, onSelect: onMood)
                .disabled(mood != nil)
        }
        .frame(maxWidth: 320)
    }
}
