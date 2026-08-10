import AuthenticationServices
import OndKit
import OndUI
import SwiftUI

/// What this install is, what it is on, the two ways to change either, and the
/// way out.
///
/// One section rather than three. Identity, subscription and deletion were
/// separate cards for a while, and they read as three unrelated things that
/// happened to be adjacent — when in fact they are one subject seen from three
/// sides: who this device is to us, what that identity is entitled to, and the
/// button that ends both. The deletion's own confirmation is the proof they
/// belong together, because it is the one place all three have to be spoken
/// about in a single sentence.
///
/// Signing in is not a gate and never becomes one, so it sits in Settings rather
/// than in front of the app. Local-only is named on the row for the same reason
/// — it is the state most people will stay in, and a row that only offered a
/// button would read as something unfinished rather than as a choice already
/// made.
///
/// The anonymous id sits below all of it, because it is the thing the rest is
/// true *of*: the state row names what this install is, the buttons change it,
/// the plan says what it is entitled to, and the id is what all of that is
/// attached to either way.
///
/// The deletion is the promise the privacy policy makes, and what Guideline
/// 5.1.1(v) requires of an app that offers account creation. Its confirmation
/// has to say what goes *and* what does not, because the one thing it cannot
/// touch is the subscription — a person who deletes their account believing the
/// billing stops has been misled by omission.
///
/// `AuthenticationServices` reaches no further than this file and
/// `AppleIdentityRequest` beside it. Everything either sheet produces is reduced
/// here to the one string the server acts on, which is what leaves
/// `AccountModel` drivable by a test on the host with no Apple sheet anywhere in
/// it.
struct AccountSection: View {
    let account: AccountModel

    /// What this identity is entitled to. Here rather than in a section of its
    /// own, because "which plan am I on" is a question about the account and
    /// nobody has ever gone looking for it anywhere else.
    ///
    /// Stated, never restored. This section carried a Restore purchases button
    /// for a while, on StoreKit 1's assumption that an app cannot see what
    /// somebody owns until it asks. `SubscriptionStore.watch()` disproves it on
    /// every launch: it reads `Transaction.currentEntitlements` and re-submits
    /// them, so the one case a restore was for — a paid subscriber whose receipt
    /// has not reached our server — resolves itself the next time the app opens.
    /// The button bought that person an Apple ID password prompt and a few hours.
    /// The paywall keeps its own, at the foot of the sheet where Apple expects a
    /// restore and where people recognise one.
    let plus: SubscriptionStore

    /// Opens the paywall on the plan row, which `SettingsView` presents. Only
    /// ever reached by a subscriber: there is nothing on sale, so for everybody
    /// else the row states the tier and stays put.
    @Binding var isShowingPaywall: Bool

    /// Opens the system's own subscription sheet, which `SettingsView` presents.
    /// A binding rather than a sheet of this section's own, because the
    /// confirmation below has to point somewhere real when it says that only
    /// Apple can cancel a subscription — and there is no second place to point.
    @Binding var isManagingSubscription: Bool

    /// The button draws its own chrome and has to be legible against both
    /// palettes, which is a decision the system will not make for it.
    @Environment(\.colorScheme) private var colorScheme

    @State private var isConfirmingDeletion = false

    var body: some View {
        Section {
            LabeledContent("This device") {
                Text(account.state.title)
            }

            switch account.state {
            case .localOnly:
                SignInWithAppleButton(.signIn) { request in
                    // Nothing. The server reads the token's `sub` and files the
                    // history under it; a name and an email would be two more
                    // things held about somebody for no use at all.
                    request.requestedScopes = []
                } onCompletion: { result in
                    signIn(with: result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 44)
                .disabled(account.isWorking)

            case .signedIn:
                Button("Sign out") {
                    Task { await account.signOut() }
                }
                .tint(Theme.Accent.brand)
                .disabled(account.isWorking)
            }

            planRow

            if plus.tier > .free {
                Button("Manage subscription") {
                    isManagingSubscription = true
                }
                .tint(Theme.Accent.brand)
            }

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
            // Only ever a failure. The prose that used to live here explained
            // what signing in was for; the section's rows say it well enough,
            // and a paragraph under every screen was the thing this settings
            // pass set out to be rid of. A refused sign-in or deletion still
            // has to land somewhere, and this is the only place attached to
            // the buttons that caused it.
            if let failure = account.failure {
                Text(failure)
                    .foregroundStyle(Theme.Accent.caution)
            }
        }
        .listRowBackground(Theme.Surface.raised)
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
    }

    /// Which tier this identity holds, and — for a subscriber only — a way back
    /// into the sheet that explains it.
    ///
    /// Shown at every tier, including free. It used to appear only above it,
    /// which left the one question people actually come to Settings with —
    /// what am I paying for — answered by silence for the people least sure of
    /// the answer.
    @ViewBuilder
    private var planRow: some View {
        if plus.tier > .free {
            Button {
                isShowingPaywall = true
            } label: {
                LabeledContent("Plan") {
                    Text(plus.tier.title)
                }
            }
            // Plain, so the row reads like its neighbours: its first job is to
            // answer "which tier", and only then to open the sheet for whoever
            // asks more of it.
            .buttonStyle(.plain)
        } else {
            LabeledContent("Plan") {
                Text(plus.tier.title)
            }
        }
    }

    /// What goes, what stays, and — where the account is signed in — what will be
    /// asked for next.
    ///
    /// The subscription sentence is the one the confirmation cannot do without:
    /// a person who deletes their account believing the billing stops has been
    /// misled by omission. The Apple sentence is there so the sheet that follows
    /// reads as the confirmation it is rather than as a sign-in prompt somebody
    /// did not ask for.
    private var deletionMessage: String {
        let confirmation = willAskApple
            ? "You will be asked to confirm with Apple.\n\n"
            : ""

        return "Your profile, your sessions and your breath-hold history are "
            + "erased from this iPhone, from a paired Apple Watch, and from "
            + "our servers. It cannot be undone.\n\n"
            + confirmation
            + "Deleting your account does not cancel your subscription — "
            + "only Apple can do that, under Manage Subscription."
    }

    /// Erases the account, asking Apple to confirm first where the account is
    /// bound to an Apple ID.
    ///
    /// The credential is asked for *after* the confirmation rather than instead
    /// of it: the server requires it because this is the one irreversible
    /// operation in the API and the anonymous id alone is not a claim it will
    /// act on, but a sheet appearing before the person has said what they want
    /// would read as a sign-in prompt rather than as a confirmation.
    ///
    /// A local-only install sends nothing and the server asks for nothing. If
    /// this install is wrong about that — a reinstall reads `state` back as
    /// local-only while the surviving Keychain identity is still bound — the
    /// refusal arrives as a message in the footer, which is the honest outcome
    /// and the one that names the way out.
    private func delete() async {
        guard willAskApple else {
            await account.deleteAccount(identityToken: nil)
            return
        }

        do {
            let identityToken = try await AppleIdentityRequest().freshIdentityToken()
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

    /// Surfaces a failure from either Apple sheet, and stays quiet about the one
    /// that is not a failure.
    ///
    /// Cancelling is a decision, and a message about it would be the app arguing
    /// with one just made — true of backing out of a sign-in and of backing out
    /// of a deletion alike.
    private func report(_ error: any Error) {
        guard (error as? ASAuthorizationError)?.code != .canceled else { return }

        account.reportSignInFailure(error.localizedDescription)
    }

    /// Reduces whatever the system sheet produced to the one thing the server
    /// takes: the identity token, verbatim.
    ///
    /// The reduction itself is `AppleIdentityRequest.identityToken(from:)`,
    /// shared with the deletion above — which reaches the same credential
    /// through a controller of its own rather than through this button.
    private func signIn(with result: Result<ASAuthorization, any Error>) {
        do {
            let identityToken = try AppleIdentityRequest.identityToken(from: result.get())
            Task { await account.signIn(identityToken: identityToken) }
        } catch {
            report(error)
        }
    }
}
