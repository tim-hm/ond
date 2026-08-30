import SwiftUI

public extension View {
    /// The one geometry every screen-concluding action wears, applied **inside**
    /// a button's label: a `frame` hung on the button itself draws a shape the
    /// button does not consider part of itself, so taps beside the word miss.
    /// Sets the type and the width, deliberately not the height — that comes
    /// from `.controlSize(.large)`, which `CapsuleActionStyle` redraws by hand.
    func primaryActionLabel() -> some View {
        font(.headline)
            .frame(maxWidth: .infinity)
    }

    /// The type, width and colour of a label inside that capsule.
    /// `Action.brandLabel` over `Accent/Brand` is the pairing the palette
    /// measures — 7.43:1, against 2.49:1 for the white label the system would
    /// otherwise write there.
    func brandActionLabel() -> some View {
        primaryActionLabel()
            .foregroundStyle(Theme.Action.brandLabel)
    }

    // `View+Glass` is guarded for the same reason: the package's macOS floor is
    // low enough to build the tests on a host, and the glass button style
    // arrived in macOS 26. Nothing outside the phone asks for this control.
    #if os(iOS)
        /// The glass fill of that same control, applied **to** the button. A
        /// recipe rather than a `ButtonStyle`, because the material is
        /// `.glassProminent`'s. The label wears `brandActionLabel()`, which
        /// carries the colour: a foreground set out here holds only while the
        /// system declines to write its own — white over `Accent/Brand` at 2.49:1.
        func brandAction() -> some View {
            buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .tint(Theme.Accent.brand)
        }
    #endif
}

private extension View {
    /// What a style drawing its own capsule stands around its label. The side
    /// inset is invisible at full width, where the label has already taken the
    /// row: it is the only padding a capsule gets where the container offers
    /// the label its own width instead — `ContentUnavailableView`'s action
    /// column, where the text otherwise meets the capsule's edge.
    func capsuleInset() -> some View {
        padding(.vertical, Theme.Metrics.primaryActionInset)
            .padding(.horizontal, Theme.Spacing.loose)
    }
}

/// The session flow's one primary control: a full-width capsule washed with the
/// accent. A `ButtonStyle` rather than a modifier, so the capsule the eye sees
/// and the area the finger hits are the same rectangle. One style because the
/// same control opens a session from both screens that can, and a retune has to
/// land on both at once or the flow's one button quietly forks.
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
            .capsuleInset()
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
/// with the ground itself as its label. Exists because `.borderedProminent`
/// does not clear — the system writes white over `Accent/Brand`'s dark value
/// at 2.49:1, a defect token-pair tests cannot see. Deepening the tint cannot
/// fix it, so the fill stops being the accent; the ink is the same on every ground.
public struct InkActionStyle: ButtonStyle {
    /// The least the capsule stands, or nil for the control size's own.
    private let minHeight: CGFloat?

    /// - Parameter minHeight: how tall the capsule is at least — for the one
    ///   action a screen is built around, which the spec draws taller than
    ///   the large control size. Nil everywhere else.
    public init(minHeight: CGFloat? = nil) {
        self.minHeight = minHeight
    }

    public func makeBody(configuration: Configuration) -> some View {
        Capsuled(configuration: configuration, minHeight: minHeight)
    }

    /// A nested `View` rather than the body of `makeBody`: `isEnabled` read
    /// inside `makeBody` resolves against whatever environment built the style,
    /// not the button's, so a disabled button would draw as live and swallow
    /// the tap. Not named `Body` — that is `ButtonStyle`'s own associated type,
    /// and a nested type of that name breaks the conformance cryptically.
    private struct Capsuled: View {
        let configuration: ButtonStyleConfiguration
        let minHeight: CGFloat?
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .primaryActionLabel()
                .foregroundStyle(Theme.Surface.ground)
                // On the label and under the inset, so the capsule and its
                // hit shape grow with it rather than leaving a band of
                // nothing around a short pill.
                .frame(minHeight: minHeight.map { $0 - 2 * Theme.Metrics.primaryActionInset })
                // By hand for the same reason `CapsuleActionStyle` does it: this
                // style draws its own material, so nothing inserts the control
                // size's inset on its behalf.
                .capsuleInset()
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

    /// The ink capsule standing at least `minHeight` — the lead action Home
    /// is built around.
    static func inkAction(minHeight: CGFloat) -> InkActionStyle {
        InkActionStyle(minHeight: minHeight)
    }
}
