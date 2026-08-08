import AuthenticationServices
import OndKit
import OndUI
import SwiftUI

/// What this install is, the two ways to change it, and the way out.
///
/// A section rather than a screen: signing in is not a gate and never becomes
/// one, so it sits in Settings beside the subscription rather than in front of
/// the app. Local-only is named on the row for the same reason — it is the state
/// most people will stay in, and a row that only offered a button would read as
/// something unfinished rather than as a choice already made.
///
/// The anonymous id sits at the foot of the same section, because it is the
/// thing all of that is true *of*: the account row names the state, the buttons
/// change it, and the id is what the state is attached to either way.
///
/// The deletion below it is the promise the privacy policy makes, and what
/// Guideline 5.1.1(v) requires of an app that offers account creation. Its
/// confirmation has to say what goes *and* what does not, because the one thing
/// it cannot touch is the subscription — a person who deletes their account
/// believing the billing stops has been misled by omission.
///
/// `AuthenticationServices` reaches no further than this file and
/// `AppleIdentityRequest` beside it. Everything either sheet produces is reduced
/// here to the one string the server acts on, which is what leaves
/// `AccountModel` drivable by a test on the host with no Apple sheet anywhere in
/// it.
struct AccountSection: View {
    let account: AccountModel

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
            LabeledContent("Account") {
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

            // Outside the switch on purpose. Signing in binds an Apple account
            // *to* this id rather than replacing it, so the id answers "which
            // record is mine" in either state, and folding this row into the
            // local-only branch would hide it from the people who can still be
            // asked for it. Absent only where the Keychain could not be read.
            if let reference = account.supportReference {
                SupportIdentifierRow(reference: reference)
            }
        } footer: {
            Text(footer)
        }
        .listRowBackground(Theme.Surface.raised)

        // Its own section, and offered in both states. Signing in was never what
        // created anything: an anonymous identity has a row, a journey and
        // possibly a subscription from its first request, so an erasure that
        // only appeared to signed-in people would be one most people could not
        // reach.
        Section {
            Button("Delete account", role: .destructive) {
                isConfirmingDeletion = true
            }
            .disabled(account.isWorking)
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

    /// The failure, when there is one, and otherwise what each state means.
    ///
    /// One footer rather than a banner: the two sentences a person needs are
    /// about what happens to their practice, and they are needed exactly where
    /// the button is.
    private var footer: String {
        if let failure = account.failure {
            return failure
        }

        return switch account.state {
        case .localOnly:
            "Everything stays on this device. Signing in with Apple attaches "
                + "your practice to your Apple ID, so a new phone — or this one, "
                + "restored — picks up where you left off. You never have to."
        case .signedIn:
            "Signing out returns this device to local only, under a new "
                + "anonymous identity. What you have practised stays on this "
                + "device, and stays attached to your Apple ID for next time."
        }
    }

    /// Reduces whatever the system sheet produced to the one thing the server
    /// takes: the identity token, verbatim.
    ///
    /// The reduction itself is `AppleIdentityRequest.identityToken(from:)`,
    /// shared with the deletion below — which reaches the same credential
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
