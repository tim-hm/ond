import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One thing you can breathe, as a row: what it is called, and what it will
/// cost in minutes.
///
/// Home's row. The Protocols list drew this one too until the refresh gave a
/// moment its own card — `ProtocolCard`, titled by the occasion and carrying
/// what a card has room for — so the two now differ in what they say and share
/// `StartableStopCard`, which is everything else about them.
///
/// The card is neutral glass, and the goal's colour lives in the dot beside
/// the facts — at full strength, where two neighbouring accents can actually
/// be told apart. The wash it replaced tinted the whole card at 0.12, which
/// is past reliable distinction for the goals beside each other on the wheel
/// and read as assorted pastels rather than as information.
struct StopRow: View {
    let stop: DialStop
    let tier: SubscriptionTier

    let start: () -> Void

    var body: some View {
        StartableStopCard(stop: stop, tier: tier, start: start) {
            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                Text(stop.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Ink.primary)

                HStack(spacing: Theme.Spacing.close) {
                    StopFactsLine(stop: stop, tier: tier)

                    // Home's rows carry it and the continue card does not: the
                    // card is the one thing on the screen somebody is being
                    // asked to start, and how well trialled it is belongs where
                    // exercises are being compared with each other.
                    if let grade = stop.technique.evidenceGrade {
                        EvidenceChip(grade: grade)
                    }
                }
            }
        }
    }
}
