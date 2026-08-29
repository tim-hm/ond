import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The running session's face: the breath guide, the three word slots under
/// it, the transport controls, and the heart-rate row. Split from
/// `SessionView` along its existing seam: that screen decides which of five
/// things is on screen and owns the lifecycle; this is the fifth and owns only
/// its own drawing. It takes the model and reads the rest from the environment.
struct SessionPlayerView: View {
    let model: SessionModel

    @Environment(SessionSettings.self) private var settings
    @Environment(PulseMonitor.self) private var pulse
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.loose) {
            header
                // Capped with the words below, and for their reason: this row
                // sits above three slots of reserved height.
                .dynamicTypeSize(...SessionWords.mostGrowth)

            Spacer()

            breathGuide
            SessionWords(model: model)

            // Inside the spacers so the slack falls beneath it and the rate
            // joins the exercise, not the transport controls. Its own row so
            // it survives Just the visuals' wordless screen. `expectsReadings`
            // is the only pulse property read here: the rate itself stays
            // inside the badge — see `PulseBadge`.
            if pulse.expectsReadings {
                PulseBadge()
            }

            Spacer()

            controls
        }
        .padding(Theme.Spacing.loose)
        // Set once for the screen: everything under here is text on the deep
        // ground, and the buttons carry their own tint over it.
        .foregroundStyle(Theme.Ink.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Self.deepGround.ignoresSafeArea()
                ambience.ignoresSafeArea()
            }
        }
        // The ground above is this colour in both appearances, but every ink
        // and material on it still adapts — in the light appearance that is
        // near-black words on near-black air, a screen with no visible text.
        // Forcing the subtree dark keeps the tokens on the variants the deep
        // ground was measured against.
        .environment(\.colorScheme, .dark)
    }

    /// The session's ground — the one screen that goes darker than the app,
    /// so the field and the glyph have black air to sit in. A local constant
    /// rather than a catalogue token: the spec defines no light variant,
    /// because a live session is this colour in both appearances, and a token
    /// would oblige the integrity tests to invent one.
    private static let deepGround = Color(red: 0x05 / 255, green: 0x09 / 255, blue: 0x0B / 255)

    /// The drifting light behind the whole screen. On the restful cap — the
    /// ambience is not the breath — frozen with the session, and handed one
    /// unmoving instant under Reduce Motion.
    @ViewBuilder
    private var ambience: some View {
        if reduceMotion {
            // The reference instant, not `.distantPast`: the phase comes off
            // a truncating remainder, which keeps a negative dividend's sign
            // and would hold the field at an arbitrary pose outside its own
            // swell band. Zero is the pose the field was tuned at.
            AmbientField(date: Date(timeIntervalSinceReferenceDate: 0))
        } else {
            TimelineView(.animation(
                minimumInterval: AmbientField.frameInterval,
                paused: model.status != .running
            )) { context in
                AmbientField(date: context.date)
            }
        }
    }

    /// How slowly the guide may redraw, or nil where it is the breath itself
    /// moving and every frame counts.
    private var restfulInterval: Double? {
        BreathVisual.drawsArc(reduceMotion: reduceMotion, settings)
            ? Theme.Motion.restfulFrameInterval
            : nil
    }

    /// The name, the remaining time, and the position. The name and position
    /// change at phase boundaries; the remaining time ticks on its own
    /// one-second timeline so the rest of the header is not rebuilt with it.
    private var header: some View {
        VStack(spacing: Theme.Spacing.tight) {
            Text(model.title)
                // A text style, not a fixed size: 13 points at the default
                // setting, but the one name on the screen must grow with the
                // reader's text like everything around it.
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.3)

            // Only where the plan knows its own end — an open-ended stage
            // makes "left" a number nobody stands behind.
            if !model.technique.hasOpenEndedStage {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("\(model.remaining.formatted(.time(pattern: .minuteSecond))) left")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Ink.secondary)
                }
            }

            Text(position)
                .font(.footnote)
                .foregroundStyle(Theme.Ink.secondary)
        }
    }

    /// "Cycle 3 of 8", or "Round 2 of 3 · cycle 12 of 30" once there are rounds
    /// to keep track of. The round is the number that matters in a staged
    /// protocol, and the cycle is meaningless without it.
    private var position: String {
        let cycle = "Cycle \(model.currentCycle) of \(model.cyclesInCurrentStage)"
        guard model.timeline.rounds > 1 else { return cycle }
        return "Round \(model.currentRound) of \(model.timeline.rounds) · \(cycle.lowercased())"
    }

    /// The orb, on the session's own clock and paused with it. `drawsArc`
    /// decides the restful cap; a scaling core is followed breath for breath,
    /// so it redraws as often as the display can.
    private var breathGuide: some View {
        TimelineView(.animation(
            minimumInterval: restfulInterval,
            paused: model.status != .running
        )) { _ in
            let elapsed = model.elapsed
            breathVisual(beat: model.timeline.beat(at: elapsed), elapsed: elapsed)
        }
    }

    private var controls: some View {
        VStack(spacing: Theme.Spacing.standard) {
            // Honest only when a channel actually follows the screen out:
            // iOS withholds haptics from a locked device, so sound is the
            // only carrier and a haptics-only session pauses instead —
            // `SessionCueMode.screenOffNote` carries the device finding.
            if settings.cueMode.playsAudio {
                HStack(spacing: Theme.Spacing.close) {
                    Circle()
                        .fill(Theme.Breath.inhale)
                        .frame(width: 6, height: 6)
                    Text("Screen off is fine — the sound carries it")
                        .font(.footnote)
                        .foregroundStyle(Theme.Ink.secondary)
                }
            }

            // An icon, and the one round control on the screen: pausing is the
            // thing a hand reaches for without reading, and a word beside
            // "End session" made the pair read as a choice between two exits.
            Button {
                if model.status == .paused {
                    model.resume()
                } else {
                    model.pause()
                }
            } label: {
                Image(systemName: model.status == .paused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.Ink.primary)
                    .frame(width: Self.pauseDiameter, height: Self.pauseDiameter)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel(model.status == .paused ? "Resume" : "Pause")

            Button("End session") {
                model.end()
            }
            .font(.subheadline)
            .foregroundStyle(Theme.Ink.secondary)
            .tapTarget()
            .accessibilityHint("Ends the session and shows what it recorded")

            Text("Ending early is recorded as ending early. Nothing else.")
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .padding(.bottom, Theme.Spacing.standard)
    }

    /// The pause control's own size — the spec's, and larger than a tap target
    /// because it is the control a closed pair of eyes goes looking for.
    private static let pauseDiameter: CGFloat = 64

    /// The session's one moving picture. It carries the phase wherever the
    /// words do not — the wordless screen, while the session runs — and goes
    /// silent rather than swapping identity, so a pause cannot restart the
    /// drawing it is meant to freeze.
    private func breathVisual(beat: SessionTimeline.Beat?, elapsed: Duration) -> some View {
        BreathVisual(
            beat: beat,
            elapsed: elapsed,
            timeline: model.timeline,
            accent: model.accent,
            register: model.timeline.register
        )
        .speaksPhase(beat, at: elapsed)
        .accessibilityHidden(SessionWords.speak(for: model, under: settings.guidance))
    }
}
