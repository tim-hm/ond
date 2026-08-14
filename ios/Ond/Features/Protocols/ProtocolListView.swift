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
/// Routes have no bundled content — unlike the catalogue, nothing here can be
/// breathed without having reached the server once — so a first launch offline
/// lands on the empty state by design. The local `.none` answer draws that state
/// immediately while a refresh continues, and its retry offers the same request
/// without requiring a relaunch.
struct ProtocolListView: View {
    let catalogue: TechniqueListModel
    let routes: RoutesModel
    let sessions: any SessionRecording

    @Environment(SessionSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var plus

    /// Which goal the list is narrowed to, or nil for every protocol. Not
    /// persisted, on `TechniqueListView`'s reasoning.
    @State private var goal: TechniqueGoal?

    /// The join, held rather than rebuilt per pass.
    ///
    /// As a computed property it re-resolved every route against the whole
    /// catalogue on each body evaluation — including every pill tap, which
    /// changes only which rows are drawn — and reading `settings` inside it
    /// subscribed this tab to every preference in the app. Nil until the
    /// catalogue lands, so "not loaded" and "no protocols" stay different
    /// screens.
    @State private var board: ProtocolsBoard?

    @State private var launcher: StopLauncher

    init(catalogue: TechniqueListModel, routes: RoutesModel, sessions: any SessionRecording) {
        self.catalogue = catalogue
        self.routes = routes
        self.sessions = sessions
        _launcher = State(wrappedValue: StopLauncher(sessions: sessions))
    }

    var body: some View {
        NavigationStack {
            content
                .safeAreaInset(edge: .top, spacing: 0) { filters }
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
        .onChange(of: loaded.map(\.id), initial: true) { _, _ in rejoin() }
        .onChange(of: routes.available) { _, _ in rejoin() }
        // A length stated is a length the tap owes, and an exercise is re-dialled
        // on another tab.
        .onChange(of: settings.overridesBySlug) { _, _ in rejoin() }
    }

    @ViewBuilder
    private var content: some View {
        if let board, !board.isEmpty {
            list(board)
        } else if catalogue.hasSettled, routes.hasSettled {
            ContentUnavailableView {
                Label("No protocols yet", systemImage: "checklist")
            } description: {
                Text("They arrive with the catalogue, the first time this phone can reach it.")
            } actions: {
                Button("Try again") {
                    Task {
                        async let routed: Void = routes.refresh()
                        await catalogue.refresh()
                        await routed
                    }
                }
            }
        } else {
            ProgressView()
        }
    }

    /// The pills, pinned under the title rather than scrolled with the list.
    ///
    /// The same treatment as the Exercises tab and for its reason: a filter that
    /// scrolls away is one somebody has to go back up to turn it off, and the
    /// list under an active pill is short by definition — the row would be off
    /// screen exactly when it is most needed.
    ///
    /// Drawn from the *unfiltered* board on purpose: a row that offered only the
    /// goal already chosen would be a control that could deselect and never
    /// select, and the pill somebody wants next is the one an active filter has
    /// hidden.
    @ViewBuilder
    private var filters: some View {
        if let board, !board.isEmpty {
            GoalFilterRow(goals: board.goals, selection: $goal)
        }
    }

    /// The protocol rows, narrowed to whatever the pills say.
    private func list(_ board: ProtocolsBoard) -> some View {
        let stops = board.filtered(by: goal)

        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                ForEach(stops) { stop in
                    StopRow(stop: stop, tier: plus.tier, showsSummary: true) {
                        launcher.begin(stop)
                    }
                }

                if stops.isEmpty {
                    Text("Nothing here is for that yet.")
                        .font(.callout)
                        .foregroundStyle(Theme.Ink.secondary)
                }
            }
            .padding(Theme.Spacing.standard)
        }
    }

    /// The catalogue, or nothing until it lands.
    private var loaded: [Technique] {
        guard case let .loaded(techniques) = catalogue.state else { return [] }
        return techniques
    }

    private func rejoin() {
        let techniques = loaded
        guard !techniques.isEmpty else { return }

        board = ProtocolsBoard(
            techniques: techniques,
            routes: routes.available,
            dialled: settings.overrides(forSlugsOf: techniques)
        )
    }
}
