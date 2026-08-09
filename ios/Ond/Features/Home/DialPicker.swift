import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The mechanism: a vertical aperture holding one stop in focus and ticking as
/// it passes each of the others.
///
/// A snapping scroll view rather than a gesture and an offset, so the spin
/// carries momentum, rubber-banding at either end, and the scroll-to-item
/// VoiceOver and Full Keyboard Access already know how to drive. Vertical rather
/// than the sideways spin home used to open on: a wheel you push up and down is
/// the crown's gesture, and one interaction language across the wrist and the
/// hand is most of the argument for a dial at all.
///
/// One take rather than the three the first round offered. Of a column that
/// snaps, a drum that turns and a slot you read one thing through, the slot won
/// on a real phone: middling detents, neighbours reduced to a hint, a small
/// growth on focus, a rigid tick. It is the one that most nearly hides that
/// there is a list at all, which is the whole reason home is a dial.
///
/// The content margins are what centre the focus. `scrollPosition(id:)` reports
/// the stop at the leading edge of the scrollable region, so insetting that
/// region by the slot above the focused one makes "leading" mean "middle" — and
/// lets the first and last stops reach it.
///
/// Focus is stated rather than implied. The ink and the weight come from the
/// binding, so they are correct with every motion effect switched off; the
/// scroll transition only adds the depth on top, which is what Reduce Motion
/// takes away.
struct DialPicker: View {
    let stops: [DialStop]

    /// Which stop is in focus. A binding because the screen around the dial
    /// reads it too — the begin control's technique, and the length it will
    /// play, are the focused stop's.
    @Binding var focused: DialStop.ID?

    /// What this person has bought, so a stop whose exercise it does not open
    /// can be marked. Marked rather than hidden or disabled: an exercise you
    /// cannot reach yet is still worth knowing the app has.
    ///
    /// The tier rather than a precomputed set of locked slugs: `isUnlocked` is
    /// one comparison per row, where a set has to be rebuilt from the whole
    /// catalogue on every layout pass — and would go stale the moment a
    /// subscription landed.
    let tier: SubscriptionTier

    /// Whether a detent may tap. False under a cue mode that asked for silence
    /// — somebody who turned the session's haptics off did not ask a menu to
    /// tap them, and a picker that ignored that would be the one place in the
    /// app the setting does not reach.
    let ticks: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How many detents the window shows, focused one included. Odd, so the
    /// focused stop has the same number of neighbours above and below — which is
    /// also what puts it in the middle of the window.
    private static let slots = 3

    /// How much of a neighbour is left by the time it reaches the edge of the
    /// window, and how much larger the focused stop is drawn than one. Both are
    /// what make this a slot rather than a list.
    private static let peek = 0.10
    private static let focusScale = 1.08

    /// How much of the window's top and bottom the fade eats, as a fraction of
    /// its height.
    ///
    /// Drawn rather than left to the scroll transition because the transition is
    /// motion and Reduce Motion drops it: without a mask, a dial with the
    /// effects off shows three equally solid rows and stops reading as a window
    /// onto one. This is the part of "how much of a neighbour shows" that
    /// survives that setting.
    private static let maskEdge = 0.34

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                // Half a window of nothing at each end, so the first and last
                // stops can reach the middle — without it the dial stops with
                // the recommendation still at the top. Drawn as content rather
                // than asked for as `contentMargins`, because the anchor below
                // measures the scroll view's own bounds: stated as margins the
                // same offset is counted twice and the dial opens a couple of
                // detents below the stop it was told to show.
                Color.clear.frame(height: margin)

                LazyVStack(spacing: 0) {
                    ForEach(stops) { stop in
                        row(stop)
                            .frame(height: slot)
                            .scrollTransition(
                                reduceMotion ? .identity : .interactive,
                                axis: .vertical,
                                transition: depth
                            )
                    }
                }
                // On the rows alone, so the two spacers are travel rather than
                // detents the dial could come to rest on.
                .scrollTargetLayout()

                Color.clear.frame(height: margin)
            }
        }
        .frame(height: slot * CGFloat(Self.slots))
        .scrollTargetBehavior(.viewAligned)
        // Anchored at the centre rather than left to the leading edge the
        // margins were shifting: without it the reported stop is the one at the
        // top of the window, so the dial arrives a row or two below the
        // recommendation. Stated, it is the same stop at every slot height.
        .scrollPosition(id: $focused, anchor: .center)
        .scrollIndicators(.hidden)
        .mask(window)
        // One tap per detent the dial passes, not merely where it lands — which
        // is what makes this a dial rather than a list that reports a result.
        //
        // `old != nil` suppresses the settle onto the lead: arriving is the app
        // recommending something rather than the person choosing it. It covers
        // every such settle rather than only the first, because the caller
        // re-identifies this view whenever the stop list changes, and a rebuild
        // that moves the focus is a rebuild that changed the list — so the
        // trigger starts over with no previous value each time.
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.5), trigger: focused) { old, _ in
            ticks && old != nil
        }
        // Step without having to land on each neighbour and swipe again, which
        // is what a scroll view alone leaves a VoiceOver user doing. Attached
        // to the scroll view rather than to an explicit container element: a
        // container is not itself focusable, and an adjust rotor offered on
        // nothing is worse than the swiping it was meant to replace.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(by: 1)
            case .decrement: step(by: -1)
            @unknown default: break
            }
        }
    }

    /// How far the scroll content is inset so the first and last stops can reach
    /// the middle. Exactly the slots above the focused one.
    private var margin: CGFloat {
        slot * CGFloat(Self.slots - 1) / 2
    }

    /// The window the dial is read through: solid in the middle, gone at the
    /// edges. Static, so it survives Reduce Motion — see `maskEdge`.
    private var window: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: Self.maskEdge),
                .init(color: .black, location: 1 - Self.maskEdge),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// What a stop looks like on its way past: fading, and shrinking towards its
    /// neighbour size.
    ///
    /// All of it is pure motion, so all of it is what Reduce Motion drops.
    ///
    /// `nonisolated` because `scrollTransition` takes a plain `@Sendable`
    /// closure: a method of a view is inferred onto the main actor, and handing
    /// one over would be dropping the isolation on the way.
    private nonisolated func depth(
        _ face: EmptyVisualEffect,
        _ phase: ScrollTransitionPhase
    ) -> some VisualEffect {
        let distance = abs(phase.value)

        return face
            .scaleEffect(1 + (Self.focusScale - 1) * (1 - distance))
            .opacity(1 - distance * (1 - Self.peek))
    }

    /// One stop. Tapping a neighbour spins to it; tapping the focused one does
    /// nothing, because the screen has exactly one committing control and it is
    /// the begin button below.
    private func row(_ stop: DialStop) -> some View {
        let isFocused = stop.id == focused

        return Button {
            focused = stop.id
        } label: {
            VStack(spacing: 2) {
                Text(stop.title)
                    .font(.system(size: titleSize, weight: isFocused ? .semibold : .regular))
                    .foregroundStyle(isFocused ? tint(for: stop) : Theme.Ink.tertiary)
                    .lineLimit(1)

                meta(stop, isFocused: isFocused)
                    .lineLimit(1)

                // Laid out on every row and drawn on one, so the slots stay the
                // same height and the titles do not shift as the focus moves
                // between them. Under the dial instead, it rendered beneath the
                // next unfocused stop and read as that one's; part of the row,
                // there is no arrangement of the screen in which it can belong
                // to another.
                Text(stop.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .opacity(isFocused ? 1 : 0)
                    .padding(.top, Theme.Spacing.tight)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(for: stop))
        .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
    }

    /// The line under the name: what it is for, how long it takes, and the two
    /// marks that change what pressing begin will do.
    private func meta(_ stop: DialStop, isFocused: Bool) -> some View {
        HStack(spacing: Theme.Spacing.tight) {
            if stop.surface == .discreet {
                // The one word that says this session will not take the screen.
                // Spelled out rather than given a glyph: every other mark on
                // this row is a state, and this is a promise.
                Text("quietly")
                    .foregroundStyle(Theme.Ink.secondary)
                Text("·")
            }

            Text(stop.goal.intentObject)
            Text("·")
            Text(length(stop, width: .abbreviated))

            if !stop.technique.isUnlocked(for: tier) {
                // The brand accent and the glyph the catalogue's lock already
                // uses, so one mark does not mean two things in two places.
                Image(systemName: "lock.fill")
                    .font(.system(size: metaSize * 0.9))
                    .foregroundStyle(Theme.Accent.brand)
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: metaSize))
        .foregroundStyle(isFocused ? Theme.Ink.secondary : Theme.Ink.tertiary)
    }

    /// How long this stop takes, abbreviated for the row and spelled out for
    /// VoiceOver.
    ///
    /// One unit, so a dose fitted to whole cycles reads "3 min" rather than
    /// "2 min, 56 secs": the dial is browsed at a glance, and the exact length
    /// is the session's to keep rather than this row's to promise to the second.
    ///
    /// One function for both widths because the two must agree. `spokenLength`,
    /// which the rest of the app uses, is built for a phase — it says "176
    /// seconds" where this row says "3 min", and a screen reader contradicting
    /// the screen is worse than either wording alone.
    private func length(_ stop: DialStop, width: Duration.UnitsFormatStyle.UnitWidth) -> String {
        stop.duration.formatted(.units(
            allowed: [.minutes, .seconds],
            width: width,
            maximumUnitCount: 1
        ))
    }

    /// What a focused stop is drawn in.
    ///
    /// A discreet occasion keeps the ink rather than taking its goal's accent,
    /// which is the whole of how the dial says the two "meeting" entries differ:
    /// they name the same technique at the same dose, and the one that promises
    /// to stay out of the way is the one that does not light the screen up. The
    /// restraint *is* the signal.
    private func tint(for stop: DialStop) -> Color {
        stop.surface == .discreet ? Theme.Ink.primary : stop.goal.accent
    }

    /// What VoiceOver reads. Everything the row draws has to be spoken —
    /// "quietly" and the lock are both promises about what begin will do — and
    /// in the same words the row itself draws them in — the goal as `relax`
    /// rather than `Calm`, the length as the row's one unit, the sentence
    /// included because a reader who cannot glance at the dial has no other way
    /// to tell which stop it belongs to. A screen reader contradicting the
    /// screen is worse than either wording alone.
    private func label(for stop: DialStop) -> String {
        var spoken = "\(stop.title), \(stop.goal.intentObject), \(length(stop, width: .wide))"
        if stop.surface == .discreet {
            spoken += ", runs quietly"
        }
        if !stop.technique.isUnlocked(for: tier) {
            spoken += ", included with önd Plus"
        }
        if !stop.detail.isEmpty {
            spoken += ". \(stop.detail)"
        }
        return spoken
    }

    /// Moves the focus by `offset` stops, stopping at either end.
    ///
    /// Clamped rather than wrapping. The dial has an order and the whole of it
    /// is that the recommendation sits at the top, so a step that carried from
    /// the last stop back to the first would throw that away — and leave nothing
    /// on screen saying where the beginning is.
    private func step(by offset: Int) {
        guard let focused, let index = stops.firstIndex(where: { $0.id == focused }) else {
            return
        }
        let next = min(max(index + offset, 0), stops.count - 1)
        self.focused = stops[next].id
    }

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var metaSize: CGFloat = 12
    /// One detent's share of the dial, and so the travel between two ticks. Tall
    /// enough to hold a title, its line of meta and two lines of sentence, which
    /// is what a stop is.
    @ScaledMetric(relativeTo: .body) private var slot: CGFloat = 108
}
