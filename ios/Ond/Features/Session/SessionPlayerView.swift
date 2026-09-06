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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: Theme.Spacing.standard) {
                        header
                        SessionWords(model: model)
                        if !SessionWords.speak(for: model, under: settings.guidance) {
                            breathGuide()
                        }
                        if pulse.expectsReadings {
                            PulseBadge()
                        }
                    }
                    .padding(Theme.Spacing.standard)
                }
                .safeAreaInset(edge: .bottom) { controls }
            } else {
                standardPlayer
            }
        }
        .foregroundStyle(Theme.Ink.primary)
        .sessionGround()
    }

    private var standardPlayer: some View {
        VStack(spacing: Theme.Spacing.standard) {
            header
                .padding(.top, Theme.Spacing.loose)
                .padding(.horizontal, Theme.Spacing.loose)

            GeometryReader { proxy in
                breathGuide(extent: min(proxy.size.width * 0.94, proxy.size.height))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }

            SessionWords(model: model)
                .padding(.horizontal, Theme.Spacing.loose)

            if pulse.expectsReadings {
                PulseBadge()
            }

            controls
                .padding(.horizontal, Theme.Spacing.loose)
        }
        .padding(.vertical, Theme.Spacing.loose)
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

    private func breathGuide(extent: CGFloat = BreathVisual.extent) -> some View {
        let motion = AirOrbMotion(timeline: model.timeline)

        return TimelineView(.animation(
            minimumInterval: Theme.Motion.restfulFrameInterval,
            paused: model.status != .running && model.status != .holding
        )) { _ in
            let elapsed = model.elapsed
            breathVisual(
                beat: model.timeline.beat(at: elapsed),
                elapsed: elapsed,
                motion: motion,
                extent: extent
            )
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
    private func breathVisual(
        beat: SessionTimeline.Beat?,
        elapsed: Duration,
        motion: AirOrbMotion,
        extent: CGFloat
    ) -> some View {
        BreathVisual(
            beat: beat,
            elapsed: elapsed,
            realElapsed: model.realElapsed,
            motion: motion,
            accent: model.accent,
            register: model.timeline.register,
            availableExtent: extent
        )
        .speaksPhase(beat, at: elapsed)
        .accessibilityHidden(SessionWords.speak(for: model, under: settings.guidance))
    }
}
