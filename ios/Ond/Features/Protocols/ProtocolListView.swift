import OndKit
import OndUI
import SwiftUI

/// Protocols: the moments this app has a considered answer for.
///
/// A tab of its own rather than a band on Home, which is what it was. A moment
/// — before a presentation, through this meeting, winding down — carries a
/// technique, a length, a register and a surface, and that is a different kind
/// of offer from an exercise standing for itself. Mixed into one scroll with the
/// catalogue it read as a second, oddly-worded copy of the Exercises tab; on its
/// own it reads as what it is.
///
/// Named Protocols throughout the interface and `Occasion` throughout the
/// domain. The rename is copy: the wire, the records, the star keyspace and the
/// seed all still say occasion, and one day somebody reading this file will have
/// to be told that on purpose rather than discover it.
///
/// Routes have no bundled seed — unlike the catalogue, nothing here can be
/// breathed without having reached the server once — so a first launch offline
/// lands on the empty state by design rather than by failure. That is why the
/// spinner waits on *both* loads: an empty board drawn while the routes are
/// still in flight would say "no protocols yet" to somebody who has plenty.
struct ProtocolListView: View {
    let catalogue: TechniqueListModel
    let routes: RoutesModel
    let sessions: any SessionRecording

    @Environment(SessionSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var plus

    /// The stars, in the environment beside the other install-scoped stores: a
    /// star set here is the same star Home reads, and the deletion list in
    /// `OndApp` is what has to reach it.
    @Environment(StarredStopStore.self) private var stars

    /// Which goal the list is narrowed to, or nil for every protocol. Not
    /// persisted, on `TechniqueListView`'s reasoning.
    @State private var goal: TechniqueGoal?

    @State private var launcher: StopLauncher

    init(
        catalogue: TechniqueListModel,
        routes: RoutesModel,
        sessions: any SessionRecording,
        settings: SessionSettings,
        plus: SubscriptionStore,
        wrist: WristLaunchModel
    ) {
        self.catalogue = catalogue
        self.routes = routes
        self.sessions = sessions
        _launcher = State(wrappedValue: StopLauncher(
            sessions: sessions,
            settings: settings,
            plus: plus,
            wrist: wrist
        ))
    }

    var body: some View {
        NavigationStack {
            content
                .paletteGround()
                .navigationTitle("Protocols")
                .stopLauncher(launcher)
        }
        // Both loads together, because neither depends on the other and the
        // screen is not drawable until both have answered.
        .task {
            async let routed: Void = routes.loadIfNeeded()
            await catalogue.loadIfNeeded()
            await routed
        }
    }

    @ViewBuilder
    private var content: some View {
        let board = board

        if !hasSettled {
            ProgressView()
        } else if board.isEmpty {
            ContentUnavailableView {
                Label("No protocols yet", systemImage: "checklist")
            } description: {
                Text("They arrive with the catalogue, the first time this phone can reach it.")
            }
        } else {
            list(board)
        }
    }

    /// Whether both loads have answered, either way.
    ///
    /// A failure settles too: the routes are a layer over the catalogue, and an
    /// error banner here would report a degradation whose only remedy — try
    /// again later — is what the empty state already says.
    private var hasSettled: Bool {
        if case .loading = catalogue.state {
            return false
        }
        if case .loading = routes.state {
            return false
        }
        return true
    }

    /// The whole board, before the pills narrow it.
    ///
    /// Rebuilt per body pass rather than held, unlike Home's shelf: the join is
    /// two `compactMap`s over a few dozen routes and reads no clock, so there is
    /// nothing here that could answer differently between two layout passes.
    private var board: ProtocolsBoard {
        guard case let .loaded(techniques) = catalogue.state else {
            return ProtocolsBoard(techniques: [], routes: .none)
        }

        return ProtocolsBoard(
            techniques: techniques,
            routes: routes.available,
            dialled: techniques.reduce(into: [:]) { dialled, technique in
                dialled[technique.slug] = settings.overrides(for: technique)
            }
        )
    }

    /// The pills over the whole board, then the rungs, then the moments — all
    /// narrowed to whatever the pills say.
    ///
    /// The pills are drawn from the *unfiltered* board on purpose: a row that
    /// offered only the goal already chosen would be a control that could
    /// deselect and never select, and the pill somebody wants next is the one an
    /// active filter has hidden.
    ///
    /// Start here leads because it is the answer for somebody who has not chosen
    /// anything, and this list is where somebody who has not chosen anything
    /// arrives. It is short — four rungs — so it costs the moments below it one
    /// flick.
    private func list(_ board: ProtocolsBoard) -> some View {
        let filtered = board.filtered(by: goal)

        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
                GoalFilterRow(goals: board.goals, selection: $goal)
                    // The row states its own horizontal inset, so the stack's
                    // padding would inset it twice and stop it scrolling
                    // edge to edge.
                    .padding(.horizontal, -Theme.Spacing.standard)

                if !filtered.startHere.isEmpty {
                    section("Start here", of: filtered.startHere)
                }

                if !filtered.protocols.isEmpty {
                    section("Protocols", of: filtered.protocols)
                }

                if filtered.isEmpty {
                    Text("Nothing here is for that yet.")
                        .font(.callout)
                        .foregroundStyle(Theme.Ink.secondary)
                }
            }
            .padding(Theme.Spacing.standard)
        }
    }

    private func section(_ title: String, of stops: [DialStop]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            Text(title)
                .font(.title3.weight(.semibold))

            ForEach(stops) { stop in
                ProtocolRow(
                    stop: stop,
                    tier: plus.tier,
                    isStarred: stars.starred.contains(stop.id),
                    star: { stars.toggle(stop.id) },
                    start: { launcher.begin(stop) }
                )
            }
        }
    }
}
