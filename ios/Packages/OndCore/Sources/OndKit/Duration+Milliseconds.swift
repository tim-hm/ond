import Foundation

public extension Duration {
    /// Seconds as a `Double`, for the frameworks that measure time that way —
    /// CoreHaptics pattern events, SwiftUI geometry.
    ///
    /// Never for deciding which phase is current: that stays on the integer
    /// milliseconds below, where a boundary cannot land on the wrong side of
    /// itself by a float's breadth.
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }

    /// A phase's length as somebody reads it — `4`, or `1.5` for the
    /// physiological sigh's sip of air.
    ///
    /// One decimal at most, and none where the number is whole. Here rather than
    /// at each call site because the same duration is now written in three
    /// places — the Customise dials, the labels on the figure, and the sentence
    /// a screen reader hears — and a precision that differed between them would
    /// read as three different exercises.
    var inSeconds: String {
        seconds.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    /// A phase's length with its unit, as a count set against an instruction —
    /// "4s", "1.5s".
    ///
    /// On `inSeconds`' argument, one step further along: the steps under the figure
    /// and the dials one tap away print the same phase, and the suffix was the half
    /// left outside. A change of unit policy would otherwise retune one of the two.
    var counted: String {
        "\(inSeconds)s"
    }

    /// A whole session's length at a glance — "2 min", "22 secs".
    ///
    /// One unit, never two: this is read beside a name, where "2 min, 8 secs" is a
    /// readout rather than a length and the eight seconds are noise against the
    /// "about" that always precedes it.
    ///
    /// Here rather than at each call site on `inSeconds`' argument, and it earned
    /// it the way that one did: the deleted dial row carried this format once, and
    /// the layouts that replaced it wrote the same `.units(...)` literal twice more
    /// — so a change of unit policy would have retuned the board and not the strip.
    var glanceable: String {
        formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
    }

    /// The same length inside a sentence — "2 minutes", "22 seconds".
    ///
    /// Beside `glanceable` because the two must agree on precision even though they
    /// disagree on width: the card says "2 min" and the paragraph under the figure
    /// says "about 2 minutes" about the very same session, and a reader who noticed
    /// them rounding differently would be right to distrust both.
    var spelled: String {
        formatted(.units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 1))
    }

    /// The same length as a screen reader should say it — "4 seconds", "1
    /// second", "1.5 seconds".
    ///
    /// `Measurement`'s formatter rather than a hand-rolled plural, because it is
    /// the one that already knows a fractional value takes the plural and that a
    /// localised build will not agree with English about any of this.
    var spokenLength: String {
        Measurement(value: seconds, unit: UnitDuration.seconds)
            .formatted(
                .measurement(
                    width: .wide,
                    numberFormatStyle: .number
                        .precision(.fractionLength(0 ... 1))
                )
            )
    }
}

extension Duration {
    /// Whole milliseconds, truncating.
    ///
    /// Every duration in the catalogue is authored in milliseconds, so integer
    /// arithmetic here is exact where seconds-as-`Double` would land a cycle
    /// boundary a float's breadth on the wrong side of itself.
    var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
