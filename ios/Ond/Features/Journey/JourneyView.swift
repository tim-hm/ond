import OndKit
import OndUI
import SwiftUI

/// Everything a person has done, and where it has got them.
///
/// The numbers, the streak, the history, and the pause test all come from this
/// device, so the whole screen is there instantly and stays there in airplane
/// mode. The sync runs behind it and the leaderboards are a room you step into.
///
/// The copy rule holds throughout: celebrate consistency, never pressure. A
/// streak that has lapsed has *paused*; nobody has failed anything.
struct JourneyView: View {
    let model: JourneyModel
    let profiles: ProfileStore
    /// For resolving a record's slug to its display name. A session can outlive
    /// the exercise it recorded; the slug then stands in rather than hiding the
    /// row.
    let catalogue: TechniqueListModel

    /// The row awaiting the person's confirmation before it goes — deletion
    /// takes the stats with it, so it is asked about, not swiped away.
    @State private var toDelete: SessionRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                    StreakCard(stats: model.stats)
                    totals
                    boltCard
                    leaderboardCard
                    history
                }
                .padding(Theme.Spacing.standard)
            }
            .paletteGround()
            .navigationTitle("Journey")
            // The gear lives here because a tab bar is for content sections and
            // this is the screen about the person the settings belong to.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(catalogue: catalogue, profiles: profiles)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
        // Local read first, so the screen is complete before anything touches
        // the network; the sync then runs behind what is already drawn.
        .task {
            await model.refresh()
            await model.sync()
        }
    }

    private var totals: some View {
        HStack(spacing: Theme.Spacing.standard) {
            StatTile(value: model.stats.sessions, label: "sessions")
            StatTile(value: model.stats.minutes, label: "minutes")
            StatTile(value: model.stats.breaths, label: "breaths")
        }
    }

    /// The way into the controlled-pause test, carrying the best result so far.
    private var boltCard: some View {
        DoorCard(
            title: "Comfortable pause",
            caption: model.personalBest == nil
                ? "A two-minute check-in on your breathing."
                : "Your best so far. Take it again whenever.",
            value: model.personalBest.map { "\($0)s" }
        ) {
            BoltTestView(model: model)
        }
    }

    private var leaderboardCard: some View {
        DoorCard(
            title: "Leaderboards",
            caption: profiles.profile.displayName.isEmpty
                ? "Optional, and off until you pick a name."
                : "You're listed as \(profiles.profile.displayName)."
        ) {
            LeaderboardView(model: model, profiles: profiles)
        }
    }

    private var history: some View {
        // Once per redraw rather than once per row: the strip resolves a slug
        // to a name for every row it draws, and a linear scan each time turned
        // a bounded list back into work proportional to the catalogue times it.
        let names = techniqueNames

        return VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Text("Sessions")
                .font(.headline)

            if model.history.isEmpty {
                Text("Every session you breathe lands here.")
                    .font(.callout)
                    .foregroundStyle(Theme.Ink.secondary)
            } else {
                // Lazy over a bounded slice, because this grows for the life of
                // the install: an eager stack builds every row to show the four
                // on screen, and a lazy one over the whole history still holds
                // every row it has ever built. A page at a time keeps both the
                // diff and the live view count flat.
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleHistory) { record in
                        SessionHistoryRow(
                            record: record,
                            name: names[record.techniqueSlug] ?? record.techniqueSlug
                        )
                        // A context menu rather than a swipe: these rows
                        // live in a ScrollView, where swipe actions do not
                        // exist, and a visible affordance per row would
                        // put a delete button beside every breath taken.
                        .contextMenu {
                            Button("Delete session", systemImage: "trash", role: .destructive) {
                                toDelete = record
                            }
                        }
                        Divider().overlay(Theme.Surface.line)
                    }
                }

                if model.hasEarlierSessions {
                    Button("Show earlier sessions") {
                        model.revealEarlierSessions()
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Theme.Spacing.tight)
                }
            }
        }
        .confirmationDialog(
            "Delete this session?",
            isPresented: Binding(
                get: { toDelete != nil },
                set: {
                    if !$0 {
                        toDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let record = toDelete else { return }
                toDelete = nil
                Task { await model.delete(record) }
            }
        } message: {
            Text("It comes out of your totals and streak too.")
        }
    }

    /// Display names by slug. A session can outlive the exercise it recorded,
    /// and a slug with no entry here stands in for its name rather than hiding
    /// the row.
    private var techniqueNames: [String: String] {
        guard case let .loaded(techniques) = catalogue.state else { return [:] }
        return Dictionary(techniques.map { ($0.slug, $0.name) }) { _, latest in latest }
    }
}

private struct StreakCard: View {
    let stats: JourneyStats

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            // Above the streak, so a paused one still has something standing
            // over it.
            if let stage = stats.stage {
                Text(stage.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Ink.secondary)
            }

            Text(stats.streakHeadline)
                .font(.title2.weight(.semibold))

            Text(stats.streakDetail)
                .font(.callout)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.loose)
        .background(
            Theme.Accent.brand.opacity(0.12),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct StatTile: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: Theme.Spacing.tight) {
            Text(value, format: .number)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.standard)
        .background(Theme.Surface.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}
