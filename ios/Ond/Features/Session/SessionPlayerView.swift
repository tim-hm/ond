import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The running session's face: the breath guide, the transport controls, the
/// phase text, and the heart-rate row. Split from `SessionView` along its
/// existing seam: that screen decides which of five things is on screen and
/// owns the lifecycle; this is the fifth and owns only its own drawing. It
/// takes the model and reads the rest from the environment.
struct SessionPlayerView: View {
    let model: SessionModel

    @Environment(SessionSettings.self) private var settings
    @Environment(PulseMonitor.self) private var pulse
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.loose) {
            header

            Spacer()
            if model.isInHold {
                HoldView(model: model)
            } else {
                breathGuide
            }
            // Inside the spacers so the slack falls beneath it and the rate
            // joins the exercise, not the transport controls. Its own row so
            // it survives a hold's own view and Just the visuals' wordless
            // screen. `expectsReadings` is the only pulse property read here:
            // the rate itself stays inside the badge — see `PulseBadge`.
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

    /// Two timelines: the orb redraws every frame off the session's own clock,
    /// paused with it; the words tick once a second — rebuilt per frame, their
    /// accessibility element made VoiceOver stutter. The phase word comes off
    /// `describingBeat`, changing on the boundary — at one-second phases the
    /// sampling lag was most of the phase. `drawsArc` decides the restful cap.
    private var breathGuide: some View {
        VStack(spacing: Theme.Spacing.loose) {
            ZStack {
                TimelineView(.animation(
                    minimumInterval: restfulInterval,
                    paused: model.status != .running
                )) { _ in
                    let elapsed = model.elapsed
                    breathVisual(beat: model.timeline.beat(at: elapsed), elapsed: elapsed)
                }

                // The phase word and count sit on their own one-second
                // timeline: rebuilding them at display refresh once made
                // VoiceOver stutter. Under Just the visuals the words leave
                // the screen, not the accessibility tree — the glyph then
                // carries them, so the phase can always be re-read.
                if settings.guidance == .full {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let elapsed = model.elapsed
                        let beat = model.describingBeat

                        let words = VStack(spacing: Theme.Spacing.tight) {
                            Text(model.status == .paused ? "Paused" : beat?.instruction ?? "")
                                .displaySerif(size: 44)
                            if model.status == .paused {
                                Text("held")
                                    .font(.subheadline)
                            } else if let beat, !beat.isFastRhythm {
                                Text("\(beat.secondsRemaining(at: elapsed))")
                                    .font(.body)
                                    .monospacedDigit()
                            }
                        }
                        // The words sit on the lit core, which is
                        // mid-luminance whatever the appearance — the shadow
                        // is what holds them over it.
                        .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 2)

                        // `speaksPhase` ignores its children, so a paused
                        // session must swap the whole element: left in place
                        // it would go on reading the frozen cue as an
                        // instruction, on a screen whose visible words say
                        // the opposite.
                        if model.status == .paused {
                            words
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Paused")
                                .accessibilityValue("held")
                        } else {
                            words.speaksPhase(beat, at: elapsed)
                        }
                    }
                }
            }

            // What the body is doing that the cue cannot say. Kept for the
            // whole session where any beat hints, blank on beats that do not:
            // 4-7-8 hints one breath of three, and a line appearing and
            // vanishing shifted the geometry every cycle. The space holds the
            // line's height — an empty string collapses it.
            if settings.guidance == .full, model.timeline.hintsAnyBeat {
                Text(model.describingBeat?.hint.line ?? " ")
                    .font(.subheadline.weight(.semibold))
                    // Reserved rather than capped, which is what makes
                    // the height constant at every text size — see the
                    // history on this line before shortening it.
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
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

            HStack(spacing: Theme.Spacing.loose) {
                Button {
                    if model.status == .paused {
                        model.resume()
                    } else {
                        model.pause()
                    }
                } label: {
                    transportLabel(model.status == .paused ? "Resume" : "Pause")
                }
                .accessibilityLabel(model.status == .paused ? "Resume" : "Pause")

                // Stop rather than an X: an X beside a transport pair says
                // "close this screen", which is not what ending a session
                // does — it hands over a summary.
                Button {
                    model.end()
                } label: {
                    transportLabel("End")
                }
                .accessibilityLabel("End")
                .accessibilityHint("Ends the session")
            }

            Text("Ending early is recorded as ending early. Nothing else.")
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .padding(.bottom, Theme.Spacing.standard)
    }

    /// One transport control's face — a worded glass pill; the pair are twins
    /// told apart by title alone, so the chrome that makes them twins is
    /// written once.
    private func transportLabel(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.medium))
            .frame(minWidth: 108)
            .frame(height: 56)
            .background(.thinMaterial, in: Capsule())
    }

    /// The session's one moving picture, with its accessibility role decided
    /// by guidance: under full the text block beside it speaks for the phase
    /// and the guide stays decorative; under Just the visuals the guide is the
    /// only phase display there is, so it carries the label itself.
    @ViewBuilder
    private func breathVisual(beat: SessionTimeline.Beat?, elapsed: Duration) -> some View {
        let visual = BreathVisual(
            beat: beat,
            elapsed: elapsed,
            timeline: model.timeline,
            accent: model.accent,
            register: model.timeline.register
        )

        if settings.guidance == .full {
            visual.accessibilityHidden(true)
        } else {
            visual.speaksPhase(beat, at: elapsed)
        }
    }
}
