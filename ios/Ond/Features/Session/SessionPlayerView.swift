import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The running session's face: the breath guide, the two transport controls, the
/// lines of text that name the phase, and the row the wrist's heart rate takes
/// whether or not one is arriving.
///
/// Its own view rather than a member of `SessionView`, along the seam that screen
/// already had: `SessionView` decides which of five things is on screen — a
/// summary, an invitation, a warning, a countdown, or this — and owns the
/// lifecycle around them, where this is the last of the five and owns only its
/// own drawing. It takes the model and reads the rest of what it needs from the
/// environment, so nothing had to become visible to a second file to get here.
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
            // Under the count, because it is the one thing on this screen nobody
            // is being asked to do: the title says what this is, the guide and
            // the count say what to do about it, and the wrist's rate is what the
            // body did in reply. In the top corner it shared a baseline with the
            // title and read as part of it.
            //
            // Inside the spacers rather than below them, which is what decides
            // *which group it joins*: below, it sat a fixed gap above the
            // transport controls with the screen's slack opening up above it, and
            // read as a third control. Here the slack falls beneath it and it
            // belongs to the exercise, which is whose number it is.
            //
            // A plain row and not an overlay, because the badge holds its own
            // height whether or not a rate is arriving — see `PulseCapsule`. Its
            // own row rather than a line in the text block so that it survives
            // the two states the count does not: a hold draws its own view, and
            // Just the visuals draws no words at all.
            //
            // The two questions are different and only one of them moves. Whether
            // a rate is *arriving* changes twice a session, which is what the
            // badge reserves its height against; whether one could arrive at all
            // is settled before the first breath, so a session with no wrist
            // coming keeps no place for one. `expectsReadings` is the only pulse
            // property read from this body — the rate itself stays inside the
            // badge, which is what keeps a reading every eight seconds from
            // invalidating the guide and both of its timelines.
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

    /// Two timelines, because only the orb moves at display refresh.
    ///
    /// It redraws every frame and reads elapsed time back off the session's
    /// clock, so the visual follows the same timeline the cues do rather than an
    /// animation running alongside it — paused when the session is.
    ///
    /// The words tick once a second, which is as often as the count changes. On
    /// the frame timeline their combined accessibility element was rebuilt a
    /// hundred times a second, and an accessibility tree invalidated that often
    /// is what makes VoiceOver stutter over the phase instead of reading it.
    ///
    /// The phase itself comes off `describingBeat` — the same answer the header
    /// above is written from — rather than off the sampled clock, so the word
    /// changes on the boundary rather than at the next tick. At four seconds a
    /// phase that lag was a rounding error; at one it is most of the phase, and
    /// bellows breathing would spend half of every breath telling somebody to do
    /// the opposite of what the orb is doing.
    ///
    /// The frame timeline rests wherever `BreathVisual` is drawing the arc
    /// rather than the scaling sphere — see `Theme.Motion.restfulFrameInterval`.
    /// An arc redrawn at the display's own rate for ten minutes spends battery
    /// on a figure filling once a phase. Asked of `BreathVisual.drawsArc`, so
    /// the cap cannot come to disagree with the drawing it is capping.
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

                // The phase word and count live inside the geometry, on their
                // own one-second timeline: rebuilding this pair at display
                // refresh is what once made VoiceOver stutter over the phase.
                //
                // Under Just the visuals the words leave the screen, not the
                // accessibility tree — the glyph then carries them, so a
                // VoiceOver user can always re-read the phase, not only catch
                // its announcement.
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

            // What the body is doing that the cue above cannot say — the
            // curled tongue, the nostril, which hold this is. Below the
            // geometry rather than inside it: the glyph's core has room for a
            // word and a digit, not a sentence.
            //
            // Kept for the whole session where any beat hints, blank on the
            // beats that do not. 4-7-8 names the mouth on one breath of
            // three, and a line appearing and vanishing with it shifted the
            // geometry on every cycle — a screen read through half-closed
            // eyes cannot also be moving. The space is what holds the line's
            // height; an empty string collapses it and brings the jump back.
            //
            // No timeline of its own: the line changes only at a phase
            // boundary, and the body already rebuilds there through the
            // header's read of the current beat.
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
