import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The mechanism: a vertical aperture holding one stop in focus and ticking as
/// it passes each of the others.
///
/// A drag and an offset rather than the snapping `ScrollView` this was first
/// built as. That scroll view was the better mechanism read on its own — it came
/// with momentum, rubber-banding and scroll-to-item for nothing — and it cost
/// the screen its title. A large `navigationTitle` tracks the nearest scroll
/// view, so while the dial was one, Breathe's title shrank on every detent and
/// was missing altogether whenever the routing layer's lead was not the first
/// stop, because the picker then opened already scrolled. There is no public way
/// to tell a navigation bar to stop watching, and the only tab root without a
/// title is worse than a wheel whose physics are stated here rather than
/// inherited. What that costs is spelled out on the three pieces that had to be
/// rebuilt by hand: `settle` for the momentum, `given` for the rubber-banding,
/// and `keyboardFocus` for what Full Keyboard Access got from scroll-to-item.
///
/// Vertical rather than the sideways spin home used to open on: a wheel you push
/// up and down is the crown's gesture, and one interaction language across the
/// wrist and the hand is most of the argument for a dial at all.
///
/// One take rather than the three the first round offered. Of a column that
/// snaps, a drum that turns and a slot you read one thing through, the slot won
/// on a real phone: middling detents, neighbours reduced to a hint, a small
/// growth on focus, a rigid tick. It is the one that most nearly hides that
/// there is a list at all, which is the whole reason home is a dial.
///
/// `travel` is what centres the focus: the whole column is offset so the focused
/// stop's centre lands on the window's, which needs no spacers at either end and
/// lets the first and last stops reach the middle by construction.
///
/// Focus is stated rather than implied. The ink and the weight come from the
/// binding, in `DialRow`, so they are correct with every motion effect switched
/// off; the scale and the fade only add the depth on top, which is what Reduce
/// Motion takes away.
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
    ///
    /// `peek` is what is left once a stop is wholly clear of the window — see
    /// `travelled`, which is where the two ends of that ramp are argued. By then
    /// `window`'s gradient has taken most of it anyway, which is why this is a
    /// small number doing a small job rather than the thing that shapes the
    /// dial.
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

    /// How much of a drag past either end is let through, so the dial gives a
    /// little and then refuses rather than stopping dead against the first and
    /// last stops. What `ScrollView` called rubber-banding and did for free.
    private static let resistance = 0.25

    /// How the dial comes to rest, and the whole of what replaces a scroll view's
    /// deceleration. `snappy` rather than a longer spring because the gesture it
    /// ends is a flick between detents, not a throw down a list.
    private static let spin = Animation.snappy(duration: 0.28)

    /// The live drag in points, zero whenever nothing is being dragged. Positive
    /// is downwards, which spins the dial towards earlier stops.
    @State private var drag: CGFloat = 0

    /// Which stop the keyboard is on — see `keyboardFocus` on the modifier below
    /// for why the dial follows it.
    @FocusState private var keyboardFocus: DialStop.ID?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                // Fading and shrinking towards the neighbour size is pure
                // motion, so all of it is what Reduce Motion drops: a distance
                // of zero is exactly a row in focus. The ink and the weight come
                // from `DialRow`'s own `isFocused` instead, which is what keeps
                // the focus stated with every effect switched off.
                let out = travelled(reduceMotion ? 0 : distance(to: index))

                DialRow(stop: stop, isFocused: stop.id == focused, tier: tier) {
                    withAnimation(Self.spin) { focused = stop.id }
                }
                .frame(height: slot)
                .scaleEffect(1 + (Self.focusScale - 1) * (1 - out))
                .opacity(1 - out * (1 - Self.peek))
                .focused($keyboardFocus, equals: stop.id)
            }
        }
        // Layout stays the full column and only the drawing moves, which is what
        // keeps every row the same height as the focus travels past it.
        .offset(y: travel)
        .frame(height: slot * CGFloat(Self.slots))
        .mask(window)
        // Clipped as well as masked. The mask ends the fade at the window's
        // edge, but a column of nine stops is taller than the window and the
        // rows beyond it would otherwise take hits meant for the screen around
        // the dial.
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation.height }
                .onEnded(settle)
        )
        // One tap per detent the dial passes, not merely where it lands — which
        // is what makes this a dial rather than a list that reports a result.
        // Triggered on `nearest` rather than on `focused`, because `focused` only
        // moves once the finger is lifted: the taps have to be paid out during
        // the drag, and the settle onto the stop the drag ended nearest is then
        // already accounted for.
        //
        // `old != nil` suppresses the settle onto the lead: arriving is the app
        // recommending something rather than the person choosing it. It covers
        // every such settle rather than only the first, because the caller
        // re-identifies this view whenever the stop list changes, and a rebuild
        // that moves the focus is a rebuild that changed the list — so the
        // trigger starts over with no previous value each time.
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.5), trigger: nearest) { old, _ in
            ticks && old != nil
        }
        // Step without having to land on each neighbour and swipe again, which
        // is what a bare gesture leaves a VoiceOver user doing. On the container
        // rather than an inner element, and the container carries a drag gesture,
        // which is what makes it focusable enough to offer an adjust rotor on.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(by: 1)
            case .decrement: step(by: -1)
            @unknown default: break
            }
        }
        // Arrow keys, because nothing here scrolls any more and a dial that only
        // answers a finger is a dial a keyboard cannot turn.
        .onKeyPress(.upArrow) { step(by: -1); return .handled }
        .onKeyPress(.downArrow) { step(by: 1); return .handled }
        // Full Keyboard Access tabs through the rows, and a scroll view used to
        // bring whichever it landed on into view. Nothing does now, so the dial
        // follows the keyboard instead — without this, tabbing parks a focus ring
        // on a stop the window is masking to nothing.
        .onChange(of: keyboardFocus) { _, id in
            guard let id, id != focused else { return }
            withAnimation(Self.spin) { focused = id }
        }
    }

    /// Where the column sits so that the focused stop's centre lands on the
    /// window's, the live drag included.
    ///
    /// Measured from the column's own middle, which is the row at
    /// `(count - 1) / 2` — that is what a `VStack` centres in the frame around
    /// it, so every offset here is stated relative to it rather than to the
    /// first row.
    private var travel: CGFloat {
        (CGFloat(stops.count - 1) / 2 - CGFloat(focusedIndex)) * slot + given
    }

    /// How far the row at `index` is from the middle of the window, in slots, the
    /// live drag included. Zero is in focus and one is a neighbour.
    private func distance(to index: Int) -> Double {
        Double(index - focusedIndex) + Double(given / slot)
    }

    /// The drag as the dial will actually honour it: whole past the ends, damped
    /// beyond them.
    ///
    /// Both limits are the travel left in that direction — dragging down spins
    /// towards earlier stops, so what bounds it is how many stops sit above the
    /// focused one.
    private var given: CGFloat {
        let earlier = CGFloat(focusedIndex) * slot
        let later = CGFloat(max(stops.count - 1 - focusedIndex, 0)) * slot

        if drag > earlier {
            return earlier + (drag - earlier) * Self.resistance
        }
        if drag < -later {
            return -later + (drag + later) * Self.resistance
        }
        return drag
    }

    /// The stop the dial is nearest right now, drag included — what the haptics
    /// count and what a lifted finger will land on.
    private var nearest: Int {
        guard !stops.isEmpty else { return 0 }
        let raw = CGFloat(focusedIndex) - given / slot
        return min(max(Int(raw.rounded()), 0), stops.count - 1)
    }

    private var focusedIndex: Int {
        stops.firstIndex { $0.id == focused } ?? 0
    }

    /// Where a lifted finger leaves the dial.
    ///
    /// `predictedEndTranslation` is what carries the momentum: it is the drag
    /// plus where the flick was heading, so a quick flick crosses several
    /// detents and a slow drag crosses the one it was resting on. The dial then
    /// snaps to that detent rather than to wherever the finger stopped, which is
    /// what a scroll view's `viewAligned` behaviour was doing.
    private func settle(_ gesture: DragGesture.Value) {
        let detents = Int((-gesture.predictedEndTranslation.height / slot).rounded())
        let next = destination(detents)

        withAnimation(Self.spin) {
            drag = 0
            if let next {
                focused = next
            }
        }
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

    /// How far out of the window a stop at `distance` slots from the middle has
    /// got: zero while it is wholly inside, one once it is wholly outside.
    ///
    /// Flat across the window on purpose, which is the part of this that is a
    /// reproduction rather than a decision. `scrollTransition(.interactive)`
    /// reported nothing at all for a row fully inside the scroll view's visible
    /// region and only ramped as one crossed the edge, so under the scroll view
    /// every stop the dial actually showed was drawn at full strength and the
    /// window's look came from `DialRow`'s own ink and weight and from `window`'s
    /// gradient. Ramping across the whole window instead — the obvious reading,
    /// and what this first did — washed the neighbours out: measured against the
    /// build before it, a neighbour's ink went from 136 to 208 on a 255 ground.
    ///
    /// The two bounds are geometry. A row of one slot in a window of `slots` is
    /// wholly inside while its centre is within `(slots - 1) / 2` of the middle,
    /// and wholly outside from `(slots + 1) / 2` — one slot further on, which is
    /// what the ramp is divided by and why that division is not written.
    private func travelled(_ distance: Double) -> Double {
        min(max(abs(distance) - Double(Self.slots - 1) / 2, 0), 1)
    }

    /// Moves the focus by `offset` stops, stopping at either end.
    private func step(by offset: Int) {
        guard let next = destination(offset) else { return }
        withAnimation(Self.spin) { focused = next }
    }

    /// The stop `offset` detents from the focused one, or nil where there is no
    /// focus to count from.
    ///
    /// Clamped rather than wrapping. The dial has an order and the whole of it
    /// is that the recommendation sits at the top, so a step that carried from
    /// the last stop back to the first would throw that away — and leave nothing
    /// on screen saying where the beginning is.
    private func destination(_ offset: Int) -> DialStop.ID? {
        guard let focused, let index = stops.firstIndex(where: { $0.id == focused }) else {
            return nil
        }
        return stops[min(max(index + offset, 0), stops.count - 1)].id
    }

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var metaSize: CGFloat = 12
    /// One detent's share of the dial, and so the travel between two ticks. Tall
    /// enough to hold a title, its line of meta and two lines of sentence, which
    /// is what a stop is.
    @ScaledMetric(relativeTo: .body) private var slot: CGFloat = 108
}
