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
            // The two flexible bands take an equal share of the slack, which
            // puts the guide between them at the screen's centre whatever the
            // header and the transport controls measure.
            header
                // Capped with the words below, and for their reason: this row
                // sits above three slots of reserved height.
                .dynamicTypeSize(...SessionWords.mostGrowth)
                .padding(.top, Theme.Spacing.loose)
                .frame(maxHeight: .infinity, alignment: .top)

            breathGuide
            SessionWords(model: model)

            // Inside the bands so the slack falls beneath it and the rate
            // joins the exercise, not the transport controls. Its own row so
            // it survives Just the visuals' wordless screen. `expectsReadings`
            // is the only pulse property read here: the rate itself stays
            // inside the badge — see `PulseBadge`.
            if pulse.expectsReadings {
                PulseBadge()
            }

            controls
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(Theme.Spacing.loose)
        // Set once for the screen: everything under here is text on the deep
        // ground, and the buttons carry their own tint over it.
        .foregroundStyle(Theme.Ink.primary)
        .sessionGround(stilled: model.status != .running)
    }

    /// How slowly the guide may redraw, or nil where it is the breath itself
    /// moving and every frame counts.
    private var restfulInterval: Double? {
        BreathVisual.drawsArc(reduceMotion: reduceMotion, settings)
            ? Theme.Motion.restfulFrameInterval
            : nil
    }

    /// The name and the remaining time. The name is fixed for the session;
    /// the remaining time ticks on its own one-second timeline so the rest of
    /// the header is not rebuilt with it.
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
        }
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
