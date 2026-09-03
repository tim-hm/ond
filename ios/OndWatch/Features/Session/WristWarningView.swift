import OndKit
import OndUI
import SwiftUI

/// One exercise's own caution, standing between the play button and the first
/// breath. The phone's `TechniqueWarningView` in the wrist's column: the same
/// words, and the tick folded into a second button rather than a checkbox
/// beside the first, for the reason `WristConsentView` states — this screen has
/// room for one control at a time.
struct WristWarningView: View {
    let warning: SessionWarning
    /// Called with whether this note should stay away until its wording
    /// changes. Recording it is the caller's, as on the phone.
    let onAccepted: (_ silenced: Bool) -> Void
    /// Called for "Not now", which declines the session, not just the warning.
    let onDeclined: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                header
                actions
            }
            .padding(.bottom, Theme.Spacing.close)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            CautionRule().padding(.bottom, 2)

            Text(warning.heading)
                .displaySerif(size: Theme.Metrics.wristDisplaySize)
                .foregroundStyle(Theme.Ink.primary)

            Text(warning.text)
                .font(.caption2)
                .foregroundStyle(Theme.Ink.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Three answers. The silence is a button rather than the phone's tick,
    /// because a checkbox this size can be taken without being read — so it
    /// says what it does, which is start the session and not ask again. The
    /// plain acceptance leads: it is the one that gives up nothing.
    private var actions: some View {
        VStack(spacing: Theme.Spacing.close) {
            Button(SessionWarning.acceptance) {
                onAccepted(false)
            }
            .buttonStyle(.inkAction)

            Button("Begin, and don't ask again") {
                onAccepted(true)
            }
            .font(.caption2)

            Button(SessionWarning.refusal, action: onDeclined)
                .font(.caption2)
        }
    }
}
