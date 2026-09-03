import Foundation

public extension [Technique] {
    /// What a wrist may offer at `tier`. Dropped rather than marked, because
    /// the watch has no paywall to send anybody to, so an exercise it cannot
    /// start is a row with nowhere to go. One helper and not a filter at each
    /// screen: the front door, the carousel and the moments list each resolve
    /// their own list, and the third was already missed once.
    func unlocked(for tier: SubscriptionTier) -> [Technique] {
        filter { $0.isUnlocked(for: tier) }
    }
}
