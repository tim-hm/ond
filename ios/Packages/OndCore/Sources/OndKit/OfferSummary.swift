import Foundation

/// One line of what a proposed session is: how many rounds, then the single
/// stage's cycles and breath rhythm, or the stage count for a staged protocol.
/// Shared, because the coach can put two of them under one reply, and a
/// separator or plural that differed between them would read as two different
/// exercises.
private func summaryLine(rounds: Int, _ parts: [String]) -> String {
    let unit = rounds == 1 ? "round" : "rounds"
    return (["\(rounds) \(unit)"] + parts).joined(separator: " · ")
}

public extension Technique {
    /// The catalogue exercise as an offer card summarises it — of the technique
    /// *as dialled*, since an offer carries its own pacing and a card describing
    /// the catalogue defaults would promise one session and start another.
    var offerSummary: String {
        guard stages.count == 1, let stage = stages.first else {
            return summaryLine(rounds: recommendedRounds, ["\(stages.count) stages"])
        }
        return summaryLine(rounds: recommendedRounds, [
            stage.openEnded ? "open-ended" : "\(stage.cycles) cycles",
            stage.phases.map(\.duration.inSeconds).joined(separator: "-"),
        ])
    }
}

public extension TechniqueDraft {
    /// The same line for a pattern nobody has stored yet.
    ///
    /// No open-ended branch, unlike ``Technique/offerSummary``: a hold the
    /// person ends belongs to the curated protocols, and the contract has no way
    /// to author one — see ``DraftStage``.
    var offerSummary: String {
        guard stages.count == 1, let stage = stages.first else {
            return summaryLine(rounds: rounds, ["\(stages.count) stages"])
        }
        return summaryLine(rounds: rounds, [
            "\(stage.cycles) cycles",
            stage.phases.map(\.duration.inSeconds).joined(separator: "-"),
        ])
    }
}
