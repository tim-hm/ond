import SwiftUI

public extension View {
    /// The one geometry every screen-concluding action wears, applied **inside**
    /// a button's label.
    ///
    /// Begin, Done, I understand, I agree, See önd+ — the same control at
    /// the same size wherever it appears, whatever material fills it. What
    /// varies with the ground is the fill: the session cover's accent wash
    /// (`capsuleAction`), `.glassProminent` on glass and gradients, and the ink
    /// capsule on the plain palette (`inkAction`). What does not
    /// vary is this —
    /// the width, the height and the type — because a person meets these
    /// buttons minutes apart and a control that changes size between screens
    /// reads as a different control.
    ///
    /// Inside the label rather than on the button, which is the whole point: a
    /// `frame` hung on the button itself draws a shape the button does not
    /// consider part of itself, and every tap that lands beside the word
    /// misses.
    ///
    /// It sets the type and the width, and deliberately not the height: a
    /// system button is its label plus its own control-size inset, so a label
    /// with a height of its own comes out taller than the platform's. The
    /// height comes from `.controlSize(.large)`, which every one of these
    /// carries — `CapsuleActionStyle` reproduces it by hand because it draws
    /// its own material.
    ///
    /// Buttons that sit *inside* content — a card's action, a row's — are not
    /// this control and should not wear it; this is for the action a screen
    /// ends on.
    func primaryActionLabel() -> some View {
        font(.headline)
            .frame(maxWidth: .infinity)
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
            // By hand, because this style draws its own material: a system
            // button at `.large` stands its label plus this much, and a capsule
            // without it would be the one short button in the set.
            .padding(.vertical, Theme.Metrics.primaryActionInset)
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

/// The concluding action on a plain palette ground: a full-width ink capsule
/// with the ground itself as its label.
///
/// It exists because `.borderedProminent` does not clear. The system fills that
/// button with the tint and writes a white label over it, and over
/// `Accent/Brand`'s dark value that measures 2.49:1 — a defect the palette's own
/// tests cannot see, because they measure named token pairs and never resolve a
/// system control's tint. `Surface.ground` over `Ink.primary` is the pairing the
/// whole catalogue is measured around, in both appearances.
///
/// Deepening the tint cannot fix it: `Accent.brandText` shares `Accent.brand`'s
/// dark value, because the dark appearance never had the light one's problem.
/// The fill has to stop being the accent.
///
/// Takes no accent, unlike `capsuleAction`. That is the point — the ink is the
/// same on every ground, and a control that concludes a screen is not where the
/// exercise's colour belongs.
public struct InkActionStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Capsuled(configuration: configuration)
    }

    /// A nested `View` rather than the body of `makeBody`, because a
    /// `ButtonStyle` is handed `isPressed` and nothing else. `isEnabled` is an
    /// environment value, and reading it inside `makeBody` resolves it against
    /// whatever environment built the style — not the button's. Without this
    /// hop a disabled button draws itself exactly as a live one and swallows
    /// the tap that follows.
    ///
    /// Not named `Body`: that is `ButtonStyle`'s own associated type, and a
    /// nested type of that name satisfies it instead of being inferred from
    /// `makeBody`'s return, which fails to conform in a way the error does not
    /// name.
    private struct Capsuled: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .primaryActionLabel()
                .foregroundStyle(Theme.Surface.ground)
                // By hand for the same reason `CapsuleActionStyle` does it: this
                // style draws its own material, so nothing inserts the control
                // size's inset on its behalf.
                .padding(.vertical, Theme.Metrics.primaryActionInset)
                .background(Theme.Ink.primary, in: Capsule())
                .contentShape(Capsule())
                .opacity(dimming)
        }

        private var dimming: Double {
            guard isEnabled else { return 0.4 }
            return configuration.isPressed ? 0.8 : 1
        }
    }
}

public extension ButtonStyle where Self == InkActionStyle {
    /// The ink capsule, for the action a screen ends on where the ground is the
    /// plain palette rather than the session's wash.
    static var inkAction: InkActionStyle {
        InkActionStyle()
    }
}
