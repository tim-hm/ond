import Foundation

public extension Duration {
    /// Seconds as a `Double`, for the frameworks that measure time that way.
    /// Never for deciding which phase is current: that stays on the integer
    /// milliseconds below, where a boundary cannot land on the wrong side of
    /// itself by a float's breadth.
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }

    /// A phase's length as somebody reads it — `4`, or `1.5`. One decimal at
    /// most, none where the number is whole. Here rather than at each call
    /// site: the same duration is written in three places, and a precision
    /// that differed between them would read as three different exercises.
    var inSeconds: String {
        seconds.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    /// A phase's length with its unit, as a count set against an instruction —
    /// "4s", "1.5s". On `inSeconds`' argument: the steps under the figure and
    /// the dials one tap away print the same phase, and a change of unit
    /// policy must not retune one of the two.
    var counted: String {
        "\(inSeconds)s"
    }

    /// A whole session's length at a glance — "2 min", "22 secs". One unit,
    /// never two: read beside a name, "2 min, 8 secs" is a readout rather
    /// than a length, and the seconds are noise against the "about" that
    /// always precedes it. Here rather than at each call site, so a change of
    /// unit policy retunes every layout at once.
    var glanceable: String {
        formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
    }

    /// The same length inside a sentence — "2 minutes", "22 seconds". Beside
    /// `glanceable` because the two must agree on precision while disagreeing
    /// on width: the card and the paragraph describe the very same session,
    /// and a reader who noticed them rounding differently would distrust both.
    var spelled: String {
        formatted(.units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 1))
    }

    /// One bound of a band — "30s", "2m" — one unit, narrow.
    ///
    /// Unlike `counted`, this keeps Foundation's own unit symbols and may print
    /// minutes: a band exists to bracket a hold that crosses into them, where a
    /// bare `120` beside the bare-seconds counts elsewhere would read as one.
    var banded: String {
        formatted(.units(allowed: [.minutes, .seconds], width: .narrow, maximumUnitCount: 1))
    }

    /// The same length as a screen reader should say it — "4 seconds", "1.5
    /// seconds". `Measurement`'s formatter rather than a hand-rolled plural:
    /// it already knows a fractional value takes the plural, and a localised
    /// build will not agree with English about any of this.
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

public extension ClosedRange<Duration> {
    /// The range as a label prints it — "30s–2m" — or nil for a single point,
    /// which is no band at all. What the figure and the steps show for a hold
    /// the person ends: an example of where one typically lands, not a length
    /// the clock keeps.
    var band: String? {
        guard lowerBound < upperBound else { return nil }
        return "\(lowerBound.banded)–\(upperBound.banded)"
    }

    /// The same band as a sentence says it — "30 seconds to 2 minutes" — for
    /// the screen-reader description that stands in for the figure.
    var spokenBand: String? {
        guard lowerBound < upperBound else { return nil }
        return "\(lowerBound.spelled) to \(upperBound.spelled)"
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
