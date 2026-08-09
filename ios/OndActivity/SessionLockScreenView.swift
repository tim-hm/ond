import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The session as it appears on the lock screen and as a banner on an older
/// phone: the cue, what it is, and the controls.
///
/// One row, because a lock screen glanced at mid-breath has room for one row.
/// Everything that would make it two — the round, the cycle, how far through the
/// session is — is in the app, where somebody is looking rather than glancing.
struct SessionLockScreenView: View {
    let attributes: SessionActivityAttributes
    let presence: SessionPresence

    var body: some View {
        HStack(spacing: Theme.Spacing.standard) {
            BreathCue(presence: presence, accent: attributes.goal.accent, diameter: 46)
            SessionCueLabel(attributes: attributes, presence: presence)
            Spacer(minLength: Theme.Spacing.close)
            SessionControls(presence: presence, accent: attributes.goal.accent)
        }
        .padding(Theme.Spacing.standard)
    }
}
