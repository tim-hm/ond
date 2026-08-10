import SwiftUI

public extension View {
    /// The one geometry every screen-concluding action wears, applied **inside**
    /// a button's label.
    ///
    /// Begin, Done, I understand, I agree, See önd Plus — the same control at
    /// the same size wherever it appears, whatever material fills it. What
    /// varies with the ground is the fill: the session cover's accent wash
    /// (`capsuleAction`), `.glassProminent` on glass and gradients,
    /// `.borderedProminent` on the plain palette. What does not vary is this —
    /// the width, the height and the type — because a person meets these
    /// buttons minutes apart and a control that changes size between screens
    /// reads as a different control.
    ///
    /// Inside the label rather than on the button, which is the whole point: a
    /// `frame` hung on the button itself draws a shape the button does not
    /// consider part of itself, and every tap that lands beside the word
    /// misses.
    ///
    /// It sets no material of its own, so it composes with any button style.
    /// Buttons that sit *inside* content — a card's action, a row's — are not
    /// this control and should not wear it; this is for the action a screen
    /// ends on.
    func primaryActionLabel() -> some View {
        font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.primaryActionHeight)
    }
}

/// The session flow's one primary control: a full-width capsule washed with the
/// accent, strong enough to read as the way forward without shouting over the
/// screen it concludes.
///
/// A `ButtonStyle` rather than a modifier hung on the button, so the capsule the
/// eye sees and the area the finger hits are the same rectangle, and so a press
/// has something to answer with.
///
/// One style rather than an inline recipe because the same control ends three
/// screens — the invitation's Begin, the summary's Done, a warning's I
/// understand — and a retune of its opacity or shape has to land on all of them
/// at once or the flow's one button quietly forks.
public struct CapsuleActionStyle: ButtonStyle {
    private let accent: Color

    public init(_ accent: Color) {
        self.accent = accent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .primaryActionLabel()
            .background(accent.opacity(configuration.isPressed ? 0.32 : 0.2), in: Capsule())
            .contentShape(Capsule())
    }
}

public extension ButtonStyle where Self == CapsuleActionStyle {
    /// The accent-washed capsule, for a button standing on the session cover's
    /// own wash — where a filled system button would shout over a screen built
    /// to be quiet.
    static func capsuleAction(_ accent: Color) -> CapsuleActionStyle {
        CapsuleActionStyle(accent)
    }
}
