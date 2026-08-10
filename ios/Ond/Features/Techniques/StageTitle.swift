import OndKit

extension Stage {
    /// What to call this stage on screen — "Stage 2 — you end this one".
    ///
    /// One spelling, because two screens' worth of the detail view name the same
    /// stage: the how-to above the figure, and the dials under Customise. They sat
    /// a hundred lines apart with a copy each, which is how the same stage ends up
    /// called two things.
    ///
    /// - Parameters:
    ///   - index: position in the technique's stages, numbered from one for the
    ///     reader.
    ///   - staged: whether the technique has stages at all. A technique that is
    ///     one pattern repeated has no stage to number, and "Stage 1 of 1" is a
    ///     label that only raises the question.
    func title(at index: Int, staged: Bool) -> String {
        guard staged else { return "One cycle" }

        let position = "Stage \(index + 1)"
        if openEnded {
            return "\(position) — you end this one"
        }
        return cycles == 1 ? position : "\(position) — \(cycles) cycles"
    }
}
