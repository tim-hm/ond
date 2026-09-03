import OndKit
import OndUI
import SwiftUI

/// The safety terms on their own, for somebody who onboarded before they
/// existed. An install that predates the screen must not count as agreed: no
/// record means not asked, and not asked means ask. Lifted out of the flow —
/// reopening it would re-ask five answered questions — with the flow's own
/// chrome. Agreeing writes the record, and there is no other way off the screen.
struct SafetyConsentView: View {
    let store: SafetyConsentStore
    let onAgreed: () -> Void

    var body: some View {
        ScrollView {
            SafetyConsentStepView(terms: store.terms)
                .padding(.horizontal, SafetyConsentStepView.margin)
                .padding(.vertical, Theme.Spacing.loose)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                store.record()
                onAgreed()
            } label: {
                Text(store.terms.agreement)
            }
            .buttonStyle(.inkAction(minHeight: Theme.Metrics.leadActionHeight))
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.close)
        }
        .paletteGround(lit: true)
        // The same reason `OnboardingView` sets it: a cover otherwise keeps the
        // system's backdrop in the status bar and home indicator margins, and
        // that is white by day and pure black at night — neither of them this
        // palette.
        .presentationBackground(Theme.Surface.ground)
    }
}
