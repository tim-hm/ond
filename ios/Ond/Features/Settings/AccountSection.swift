import AuthenticationServices
import Foundation
import OndKit
import OndUI
import SwiftUI

/// Identity, subscription and deletion as one Settings section. Signing in is
/// optional and never gates the app. Deletion satisfies Guideline 5.1.1(v);
/// its confirmation must also say the subscription survives — only Apple can
/// cancel it. `AuthenticationServices` reaches no further than this file and
/// `AppleIdentityRequest`, which keeps `AccountModel` testable on the host.
struct AccountSection: View {
    let account: AccountModel

    /// What this identity is entitled to. No Restore button here:
    /// `SubscriptionStore.watch()` reads `Transaction.currentEntitlements` on
    /// every launch and re-submits them, so an unsynced purchase heals itself.
    /// The paywall keeps its own restore, at the foot of the sheet where Apple
    /// expects one.
    let plus: SubscriptionStore

    /// Opens the paywall when somebody selects the trailing subscription value.
    @Binding var isShowingPaywall: Bool

    /// Opens the system's own subscription sheet, which `SettingsView` presents.
    /// The trailing tier uses it for subscribers, and the deletion confirmation
    /// uses the same route when it explains that only Apple can cancel.
    @Binding var isManagingSubscription: Bool

    /// The button draws its own chrome and has to be legible against both
    /// palettes, which is a decision the system will not make for it.
    @Environment(\.colorScheme) private var colorScheme

    @State private var isConfirmingDeletion = false
    @State private var signInChallenge: AppleAuthorizationChallenge?

    var body: some View {
        Section {
            LabeledContent("This device") {
                Text(account.state.title)
            }

            switch account.state {
            case .localOnly:
                SignInWithAppleButton(.signIn) { request in
                    if let signInChallenge, signInChallenge.isValid() {
                        AppleIdentityRequest.authorize(request, challenge: signInChallenge)
                    }
                } onCompletion: { result in
                    signInChallenge = nil
                    Task { await signIn(with: result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 44)
                .disabled(account.isWorking || signInChallenge?.isValid() != true)

            case .signedIn:
                Button("Sign out") {
                    Task { await account.signOut() }
                }
                .tint(Theme.Accent.brand)
                .disabled(account.isWorking)
            }

            subscriptionRow

            // Outside the switch on purpose. Signing in binds an Apple account
            // *to* this id rather than replacing it, so the id answers "which
            // record is mine" in either state, and folding this row into the
            // local-only branch would hide it from the people who can still be
            // asked for it. Absent only where the Keychain could not be read.
            if let reference = account.supportReference {
                SupportIdentifierRow(reference: reference)
            }

            // Last, and offered in both states. Signing in was never what
            // created anything: an anonymous identity has a row, a journey and
            // possibly a subscription from its first request, so an erasure
            // that only appeared to signed-in people would be one most people
            // could not reach.
            Button("Delete account", role: .destructive) {
                isConfirmingDeletion = true
            }
            .disabled(account.isWorking)
        } header: {
            Text("Account")
        } footer: {
            // Only ever a failure a button caused: the speculative challenge
            // prefetch logs instead, so nothing appears here unasked.
            if let failure = account.failure {
                Text(failure)
                    .foregroundStyle(Theme.Accent.caution)
            }
        }
        .listRowBackground(Theme.Surface.raised)
        .task(id: account.state) {
            await maintainSignInChallenge()
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                Task { await delete() }
            }
            // Beside the deletion rather than only named in the message,
            // because "only Apple can cancel it" is no use to somebody who
            // then has to go and find where.
            Button("Manage subscription") {
                isManagingSubscription = true
            }
        } message: {
            Text(deletionMessage)
        }
        .onChange(of: isManagingSubscription) { wasPresented, isPresented in
            guard wasPresented, !isPresented else { return }
            Task { await plus.refresh() }
        }
    }

    /// The current tier, with one trailing action that opens the relevant
    /// destination: the offer when free, or Apple's management sheet while the
    /// subscription remains entitled.
    private var subscriptionRow: some View {
        LabeledContent("Subscription") {
            Button {
                if plus.tier > .free {
                    isManagingSubscription = true
                } else {
                    isShowingPaywall = true
                }
            } label: {
                VStack(alignment: .trailing, spacing: Theme.Spacing.tight) {
                    Text(plus.tier.title)

                    if let expirationDate = plus.nonRenewingExpirationDate {
                        Text(
                            "Ends \(expirationDate, format: .dateTime.day().month(.abbreviated).year())"
                        )
                        .font(.caption)
                        .foregroundStyle(Theme.Ink.tertiary)
                    }
                }
                .multilineTextAlignment(.trailing)
            }
            .tint(Theme.Accent.brand)
            .accessibilityIdentifier("settings-account-subscription")
            .accessibilityLabel("Subscription")
            .accessibilityValue(subscriptionAccessibilityValue)
            .accessibilityHint(subscriptionAccessibilityHint)
        }
    }

    /// The tier and, where known, the date its cancelled renewal stops access.
    /// The long date is for speech; the row keeps its shorter visual form.
    private var subscriptionAccessibilityValue: String {
        guard let expirationDate = plus.nonRenewingExpirationDate else {
            return plus.tier.title
        }

        let date = expirationDate.formatted(date: .long, time: .omitted)
        return "\(plus.tier.title), ends \(date)"
    }

    /// Names the destination because the same row opens two different sheets.
    private var subscriptionAccessibilityHint: String {
        plus.tier > .free
            ? "Opens Apple's subscription management"
            : "Opens the önd+ offer"
    }

    /// The deletion confirmation text. It must say the subscription survives —
    /// omitting that misleads a person into thinking the billing stops. It
    /// announces the Apple sheet so that reads as a confirmation rather than
    /// an unasked sign-in prompt.
    private var deletionMessage: String {
        let confirmation = willAskApple
            ? "You will be asked to confirm with Apple.\n\n"
            : ""

        return "Your profile, your sessions and your comfortable-pause history are "
            + "erased from this iPhone, from a paired Apple Watch, and from "
            + "our servers. It cannot be undone.\n\n"
            + confirmation
            + "Deleting your account does not cancel your subscription — "
            + "only Apple can do that, under Manage Subscription."
    }

    /// Erases the account, confirming with Apple first where it is bound to an
    /// Apple ID. The server requires the credential for this one irreversible
    /// call; it is asked for after the confirmation so the sheet reads as a
    /// confirmation, not a sign-in prompt. If a reinstall wrongly reads
    /// local-only, the server's refusal arrives in the footer.
    private func delete() async {
        guard willAskApple else {
            await account.deleteAccount(identityToken: nil)
            return
        }

        do {
            let challenge = try await account.beginAppleAuthorization(for: .deleteAccount)
            let identityToken = try await AppleIdentityRequest()
                .freshIdentityToken(challenge: challenge)
            await account.deleteAccount(identityToken: identityToken)
        } catch {
            report(error)
        }
    }

    /// Whether a deletion from here will have to prove the Apple account.
    ///
    /// Read by both the message and the deletion, so the sheet cannot promise a
    /// confirmation that never comes, or arrive unannounced.
    private var willAskApple: Bool {
        account.state == .signedIn
    }

    /// Surfaces a failure from either Apple sheet. A cancel is a decision, not
    /// a failure, so it stays silent.
    private func report(_ error: any Error) {
        guard (error as? ASAuthorizationError)?.code != .canceled else { return }

        account.reportSignInFailure(error.localizedDescription)
    }

    /// Reduces the sheet's result to the identity token the server takes, via
    /// `AppleIdentityRequest.identityToken(from:)`, shared with the deletion.
    private func signIn(with result: Result<ASAuthorization, any Error>) async {
        do {
            let identityToken = try AppleIdentityRequest.identityToken(from: result.get())
            await account.signIn(identityToken: identityToken)
        } catch {
            report(error)
        }

        await prefetchSignInChallenge()
    }

    /// Keeps one short-lived sign-in challenge ready before the system button
    /// enables; every completion replaces it, so a failed sheet never reuses a
    /// nonce. Silent on failure: this runs unasked from `.task`, and an
    /// offline launch once printed a transport error beside no action that
    /// caused it. Tapping Sign in with Apple fetches a challenge of its own.
    private func prefetchSignInChallenge() async {
        guard account.state == .localOnly, signInChallenge == nil else { return }

        do {
            signInChallenge = try await account.beginAppleAuthorization(for: .signIn)
        } catch {
            account.noteUnaskedFailure(error.diagnostic)
        }
    }

    /// Refreshes a prefetched challenge at its server-issued expiry while this
    /// screen remains in local-only mode.
    private func maintainSignInChallenge() async {
        while account.state == .localOnly, !Task.isCancelled {
            await prefetchSignInChallenge()
            guard let current = signInChallenge else { return }

            let remaining = max(0, current.expiresAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }

            if signInChallenge == current {
                signInChallenge = nil
            }
        }
    }
}
