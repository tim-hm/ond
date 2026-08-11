import OndKit

extension Stage {
    /// What to call this stage on screen — "Stage 1 — 30 cycles".
    ///
    /// One spelling, because three parts of the detail view name the same stage:
    /// the figures, the steps under them, and the dials under Customise. They sat
    /// a hundred lines apart with a copy each, which is how the same stage ends up
    /// called two things.
    ///
    /// An open-ended stage takes no suffix at all. The title used to append "you
    /// end this one", but the fact is already stated twice within a glance — the
    /// dashed figure and the "you decide" line in the steps — and a title carrying
    /// it too read as a warning rather than a name.
    ///
    /// Only ever asked of a technique that has stages to tell apart. Every caller
    /// draws these inside its own `isStaged` guard, because a technique that is one
    /// pattern repeated has no stage to number and "Stage 1 of 1" is a label that
    /// only raises the question. This used to take that answer as a parameter and
    /// spell the unstaged case; no caller ever passed it.
    ///
    /// - Parameter index: position in the technique's stages, numbered from one for
    ///   the reader.
    func title(at index: Int) -> String {
        let position = "Stage \(index + 1)"
        return cycles == 1 ? position : "\(position) — \(cycles) cycles"
    }
}
