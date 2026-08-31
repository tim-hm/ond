import Foundation

/// Splitting a whole between parts in proportion to their weights, with a
/// floor under every part, because a part that renders sub-pixel tells the
/// reader nothing. The floor is applied by repeated passes: lifting the
/// smallest parts can push a mid-sized part below the floor. Each pass floors
/// at least one more part, so the loop is bounded by the part count.
enum ProportionalShares {
    /// Shares summing to one, each at least `floor`, in proportion to `weights`
    /// otherwise.
    ///
    /// The floor is itself capped at an equal split, or the floors alone would
    /// overflow the whole once there are more parts than `1 / floor`.
    static func of(_ weights: [Double], floor requested: Double) -> [Double] {
        guard weights.count > 1 else { return weights.isEmpty ? [] : [1] }

        let total = weights.reduce(0, +)
        guard total > 0 else {
            return Array(repeating: 1 / Double(weights.count), count: weights.count)
        }

        let floor = min(requested, 1 / Double(weights.count))
        var isFloored = [Bool](repeating: false, count: weights.count)
        var shares = weights.map { $0 / total }

        while true {
            let newlyFloored = shares.indices.filter { !isFloored[$0] && shares[$0] < floor }
            if newlyFloored.isEmpty {
                return shares
            }
            for index in newlyFloored {
                isFloored[index] = true
            }

            let remaining = 1 - floor * Double(isFloored.filter(\.self).count)
            let unflooredTotal = weights.indices
                .reduce(0.0) { isFloored[$1] ? $0 : $0 + weights[$1] }
            shares = weights.indices.map { index in
                isFloored[index] ? floor : weights[index] / unflooredTotal * remaining
            }
        }
    }
}
