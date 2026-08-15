import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The running session's face: the breath guide, the two transport controls, the
/// lines of text that name the phase, and the wrist's heart rate if one is
/// arriving.
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
            Spacer()

            controls
        }
        .padding(Theme.Spacing.loose)
        // Set once for the screen: everything under here is text on the accent
        // ground, where primary is the only ink that clears AA, and the buttons
        // carry their own tint over it.
        .foregroundStyle(Theme.Ink.primary)
        // An overlay rather than a row in the header, and that is the whole
        // reason: a rate arrives a few seconds into the session and stops
        // arriving whenever a wrist comes off, so anything holding it in the
        // layout would move the breath guide underneath it. A screen read through
        // half-closed eyes cannot also be moving.
        //
        // The badge reads the rate itself rather than being handed one, which is
        // what keeps a reading every few seconds from invalidating this whole
        // screen — the header, both timelines and the two transport controls —
        // for a number in its corner.
        .overlay(alignment: .topTrailing) {
            PulseBadge()
                .padding(Theme.Spacing.loose)
        }
    }

    /// How slowly the guide may redraw, or nil where it is the breath itself
    /// moving and every frame counts.
    private var restfulInterval: Double? {
        BreathVisual.drawsArc(reduceMotion: reduceMotion, settings)
            ? Theme.Motion.restfulFrameInterval
            : nil
    }

    /// Everything that changes at a phase boundary rather than at display
    /// refresh, so it sits outside the animation timeline below and is rebuilt
    /// when `currentBeat` or `status` changes instead of sixty times a second.
    private var header: some View {
        VStack(spacing: Theme.Spacing.tight) {
            Text(model.title)
                .font(.headline)
            // Primary ink, quieter only by size: on the accent ground the
            // secondary step measures 3.26:1 and this line is `.subheadline`,
            // so there is no tone left to spend on hierarchy here.
            Text(position)
                .font(.subheadline)
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
            TimelineView(.animation(
                minimumInterval: restfulInterval,
                paused: model.status != .running
            )) { _ in
                let elapsed = model.elapsed
                breathVisual(beat: model.timeline.beat(at: elapsed), elapsed: elapsed)
            }

            // Under Just the visuals the words leave the screen, not the
            // accessibility tree — the orb above then carries them, so a
            // VoiceOver user can always re-read the phase, not only catch
            // its announcement.
            if settings.guidance == .full {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let elapsed = model.elapsed
                    let beat = model.describingBeat

                    VStack(spacing: Theme.Spacing.close) {
                        Text(beat?.instruction ?? "")
                            .font(.title2.weight(.medium))
                        // What the body is doing that the cue above cannot say —
                        // the curled tongue, the nostril, which hold this is. It
                        // takes the one ink the accent ground leaves readable;
                        // drawn in the accent it sits on it measured 2.93:1, so
                        // the weight is what marks it out now that the colour
                        // cannot.
                        //
                        // Kept for the whole session where any beat hints,
                        // blank on the beats that do not. 4-7-8 names the mouth
                        // on one breath of three, and a line appearing and
                        // vanishing with it shifted the countdown and the orb
                        // below on every cycle — a screen read through
                        // half-closed eyes cannot also be moving. The space is
                        // what holds the line's height; an empty string
                        // collapses it and brings the jump back.
                        if model.timeline.hintsAnyBeat {
                            Text(beat?.hint.line ?? " ")
                                .font(.subheadline.weight(.semibold))
                                // Reserved rather than capped, which is what
                                // makes the height constant at every text size:
                                // at an accessibility size "Through a curled
                                // tongue" wraps while the blank beat beside it
                                // stays one line, and the orb above would move
                                // on every cycle — the jump this whole line is
                                // reserved to prevent. Truncating instead would
                                // fix the layout by losing the words, on the
                                // setting somebody chose because they need them.
                                .lineLimit(2, reservesSpace: true)
                                .multilineTextAlignment(.center)
                        }
                        if let beat, !beat.isFastRhythm {
                            Text("\(beat.secondsRemaining(at: elapsed))")
                                .font(.system(.largeTitle, design: .rounded).weight(.light))
                                .monospacedDigit()
                                .foregroundStyle(Theme.Ink.primary)
                        }
                    }
                    .speaksPhase(beat, at: elapsed)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.loose) {
            Button {
                if model.status == .paused {
                    model.resume()
                } else {
                    model.pause()
                }
            } label: {
                transportLabel(
                    model.status == .paused ? "Resume" : "Pause",
                    systemImage: model.status == .paused ? "play.fill" : "pause.fill"
                )
            }
            .accessibilityLabel(model.status == .paused ? "Resume" : "Pause")

            // The pause control's twin, told apart by glyph alone. Stop rather
            // than an X: the pair reads as transport controls, and an X beside
            // them says "close this screen", which is not what ending a
            // session does — it hands over a summary.
            Button {
                model.end()
            } label: {
                transportLabel("End", systemImage: "stop.fill")
            }
            .accessibilityLabel("End")
            .accessibilityHint("Ends the session")
        }
        .padding(.bottom, Theme.Spacing.standard)
    }

    /// One transport control's face. The pair are twins told apart by glyph
    /// alone, so the chrome that makes them twins is written once.
    private func transportLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.title2)
            .frame(width: 64, height: 64)
            .background(.thinMaterial, in: Circle())
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
            progress: model.progress(at: elapsed),
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
