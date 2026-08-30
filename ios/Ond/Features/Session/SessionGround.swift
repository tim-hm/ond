import OndUI
import SwiftUI

/// The session's room: the one ground darker than the app, with the slow field
/// drifting on it. The running session and the summary it hands over to share
/// this, so the end of the breathing is not the end of the room.
struct SessionGround: ViewModifier {
    /// Whether the field holds still. A paused session freezes with the breath
    /// it sits behind; a summary has nothing left to freeze with.
    let stilled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A local constant rather than a catalogue token: a live session is this
    /// colour in both appearances, because the spec defines no light variant,
    /// and a token would oblige the integrity tests to invent one.
    private static let deep = Color(red: 0x05 / 255, green: 0x09 / 255, blue: 0x0B / 255)

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    Self.deep.ignoresSafeArea()
                    field.ignoresSafeArea()
                }
            }
            // The ground above is this colour in both appearances, but every
            // ink and material on it still adapts — in the light appearance
            // that is near-black words on near-black air, a screen with no
            // visible text. Forcing the subtree dark keeps the tokens on the
            // variants the deep ground was measured against.
            .environment(\.colorScheme, .dark)
    }

    /// The drifting light. On the restful cap — the ambience is not the breath
    /// — and handed one unmoving instant under Reduce Motion.
    @ViewBuilder
    private var field: some View {
        if reduceMotion {
            // The reference instant, not `.distantPast`: the phase comes off
            // a truncating remainder, which keeps a negative dividend's sign
            // and would hold the field at an arbitrary pose outside its own
            // swell band. Zero is the pose the field was tuned at.
            AmbientField(date: Date(timeIntervalSinceReferenceDate: 0))
        } else {
            TimelineView(.animation(
                minimumInterval: AmbientField.frameInterval,
                paused: stilled
            )) { context in
                AmbientField(date: context.date)
            }
        }
    }
}

extension View {
    /// Grounds a screen in the session's room — see `SessionGround`.
    func sessionGround(stilled: Bool = false) -> some View {
        modifier(SessionGround(stilled: stilled))
    }
}
