import OndKit

extension Stage {
    /// What to call the stage at zero-based `index` on screen — "Stage 1 — 30
    /// cycles". One spelling: the figures, the steps and the Customise dials
    /// all name the same stage. An open-ended stage takes no suffix — the
    /// dashed figure and the steps already state that fact. Only asked inside
    /// an `isStaged` guard; "Stage 1 of 1" is a label that raises the question.
    func title(at index: Int) -> String {
        let position = "Stage \(index + 1)"
        return cycles == 1 ? position : "\(position) — \(cycles) cycles"
    }
}
