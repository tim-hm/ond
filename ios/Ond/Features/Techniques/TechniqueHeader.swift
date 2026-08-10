import OndKit
import OndUI
import SwiftUI

/// How an exercise works, how you do it, and the way to ask for more — the
/// reading half of the detail screen, above the figure and the dials.
///
/// Three things in that order, and no fourth. A streamed model paragraph used to
/// sit between the summary and the figure explaining the physiology, and it is
/// gone: it cost a Bedrock call on every visit to put three paragraphs between a
/// person and the button they came for, and the coach door below answers the same
/// question better — on demand, in a conversation that can be asked a second
/// question.
///
/// What it works from is whoever wrote it: the catalogue's sentence, or the one
/// the author typed into the composer, in the same field and the same type.
///
/// The dialled technique, unlike the version this file first held: the how-to
/// line counts cycles and minutes, and a screen that printed the curated dose
/// above dials showing somebody's own would be lying in the calmest possible
/// voice.
///
/// Its own file rather than a private struct inside `TechniqueDetailView`,
/// because it stopped being only type: the coach door carries a conversation,
/// which means a store, a catalogue and a push — and the screen that owns the
/// session, the paywall and the dials has enough to hold.
struct TechniqueHeader: View {
    /// As it will actually be played, dials and all.
    let technique: Technique

    let assistant: any AssistantReading

    /// The three the coach door needs behind it: the conversation store to write
    /// into, the catalogue an offered exercise resolves against, and the recorder
    /// a session started from that offer reports to.
    let chats: any ConversationStoring
    let catalogue: TechniqueListModel
    let sessions: any SessionRecording

    /// The conversation this screen opened, if any. A fresh `Conversation` is
    /// in-memory only — the store refuses to persist an empty one — so a person
    /// who opens the coach and comes straight back leaves nothing behind.
    @State private var asking: Conversation?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            // What the exercise is for, in the person's own words rather than as
            // a category label. The uppercase capsule this replaced was the
            // loudest thing above the summary and named a taxonomy — and the
            // goal is still carried by colour on every accent on the screen.
            Text("For when you want to \(technique.goal.intentObject)")
                .font(.subheadline)
                .foregroundStyle(Theme.Ink.tertiary)

            if !technique.summary.isEmpty {
                Text(technique.summary)
                    .font(.body)
                    .foregroundStyle(Theme.Ink.secondary)
            }

            howTo

            if technique.origin == .catalogue {
                askButton
            }
        }
        .navigationDestination(item: $asking) { conversation in
            CoachChatView(
                conversation: conversation,
                chats: chats,
                assistant: assistant,
                catalogue: catalogue,
                sessions: sessions,
                opening: Self.opening(about: technique)
            )
        }
    }

    /// How you do it: where the air goes, how much of it there is, and which stage
    /// of a staged round is which.
    ///
    /// Deliberately **not** the counts. The figure below writes `in · 4` on the
    /// side of the square it belongs to, and the row of phase capsules that used to
    /// read `In 4s Hold 4s Out 4s Hold 4s` was deleted for putting the same four
    /// facts on one screen twice — this is not that row coming back. What the
    /// figure cannot carry is exactly what is here: the passage, which it marks
    /// with a letter for a nostril and with nothing at all for a mouth; the dose;
    /// and which stage you are looking at.
    private var howTo: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            if let passage = passageNote {
                Text(passage)
            }

            Text(dose)

            if technique.isStaged {
                ForEach(Array(technique.stages.enumerated()), id: \.offset) { index, stage in
                    Text(stage.title(at: index, staged: true))
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.Ink.secondary)
    }

    /// Where the air goes, or nil where saying so would only name what everybody
    /// is already doing.
    ///
    /// Nil for nose-in-nose-out on `Passage.hint`'s rule: it is what the
    /// foundations teach and what most of the catalogue does throughout, so a line
    /// repeating it on every exercise is the noise that stops the other ones being
    /// read.
    ///
    /// Nil too where either direction uses more than one passage, which is
    /// alternate-nostril breathing and nothing else. One sentence cannot say
    /// "alternating, and which hand closes which" without being wrong, and that
    /// exercise's summary already says it properly.
    private var passageNote: String? {
        let phases = technique.stages.flatMap(\.phases)
        let inhaled = Set(phases.filter { $0.breath.kind == .inhale }.compactMap(\.passage))
        let exhaled = Set(phases.filter { $0.breath.kind == .exhale }.compactMap(\.passage))

        guard inhaled.count == 1, exhaled.count == 1,
              let inhale = inhaled.first, let exhale = exhaled.first,
              inhale != .nose || exhale != .nose
        else {
            return nil
        }

        return "In through your \(inhale.title.lowercased()), "
            + "out through your \(exhale.title.lowercased())."
    }

    /// How much of the exercise there is, at the dials this person is actually on.
    ///
    /// The counts here are the *repetitions*, which the figure does not draw: it
    /// shows one cycle, or two of twenty-seven, and says so. An open-ended hold
    /// makes the total an estimate and the sentence says that rather than printing
    /// a number the clock will not keep.
    private var dose: String {
        // Wide and to one unit, unlike every other length in the app: this one is
        // read inside a sentence, where "2 min, 8 secs" is a readout rather than
        // prose and the eight seconds are noise against an "about".
        let length = technique.plannedDuration.formatted(
            .units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 1)
        )

        guard !technique.isStaged else {
            let rounds = technique.recommendedRounds == 1
                ? "One round" : "\(technique.recommendedRounds) rounds"
            return technique.hasOpenEndedStage
                ? "\(rounds), around \(length) depending on how long your holds run."
                : "\(rounds), about \(length)."
        }

        let cycles = technique.stages.first?.cycles ?? 1
        let count = cycles == 1 ? "One cycle" : "\(cycles) cycles"
        return "\(count), about \(length). However many you do is the practice."
    }

    /// The way from reading about an exercise to asking about it.
    ///
    /// The whole of what replaced the streamed explanation, and a better trade
    /// than it looks: three paragraphs nobody asked for, on every visit, at a model
    /// call each, become one line that spends nothing until somebody wants more —
    /// and what they get then is a conversation they can ask a second question in.
    ///
    /// It pushes onto this stack rather than sending anybody to the Coach tab, so
    /// Back is the exercise they were reading and not wherever that tab was left.
    ///
    /// Ungated. The server is what decides whether a model answers — a tier that
    /// does not buy one gets the rule-based reply, and the chat screen already says
    /// so in its own words — so a gate here would be a second opinion on that,
    /// free to disagree with it.
    ///
    /// Only for a catalogue exercise, which is the same rule the explanation
    /// keeps: the coach is briefed on the seeded techniques, and it has nothing
    /// to say about one somebody wrote this morning.
    private var askButton: some View {
        Button {
            asking = Conversation()
        } label: {
            Label("Ask the coach about this", systemImage: "signpost.right")
                .font(.subheadline.weight(.semibold))
        }
        // Plain and tinted rather than bordered: Begin is the button on this
        // screen, and a second filled control in the reading half would argue
        // with it.
        .buttonStyle(.plain)
        .foregroundStyle(technique.goal.accent)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    /// The question the conversation opens on, sent as the person's own first
    /// message.
    ///
    /// Phrased as somebody would type it, because that is where it appears — in
    /// the trailing bubble, attributed to them. Naming the exercise rather than
    /// relying on context is what lets the transcript stand on its own when they
    /// come back to it in the Coach tab a week later.
    private static func opening(about technique: Technique) -> String {
        "Tell me about \(technique.name) — how does it work, and when should I use it?"
    }
}
