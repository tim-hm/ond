import OndKit
import OndUI
import SwiftUI

/// The Moments tab: the situations this app has a considered answer for. The
/// interface says Moments; the wire, records, star keyspace and seed all still
/// say occasion — the rename is copy only. A first launch offline draws the
/// bundled occasions. The empty state is for a build whose bundled export
/// could not be read; it draws at once and its retry needs no relaunch.
struct MomentListView: View {
    let catalogue: TechniqueListModel
    let occasions: OccasionCatalogueModel
    let sessions: any SessionRecording

    @Environment(SessionSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var plus

    /// Which goal the list is narrowed to, or nil for every moment. Not
    /// persisted, on `TechniqueListView`'s reasoning.
    @State private var goal: TechniqueGoal?

    /// The join, held rather than recomputed: a computed property re-resolved
    /// every route on each body pass and, by reading `settings`, subscribed
    /// this tab to every preference in the app. Nil until the catalogue lands,
    /// so "not loaded" and "no moments" stay different screens.
    @State private var board: MomentsBoard?

    @State private var launcher: StopLauncher

    init(
        catalogue: TechniqueListModel,
        occasions: OccasionCatalogueModel,
        sessions: any SessionRecording
    ) {
        self.catalogue = catalogue
        self.occasions = occasions
        self.sessions = sessions
        _launcher = State(wrappedValue: StopLauncher(sessions: sessions))
    }

    var body: some View {
        NavigationStack {
            content
                .paletteGround()
                .navigationTitle("Moments")
                .stopLauncher(launcher)
        }
        // Both loads together, because neither depends on the other and the
        // screen is not drawable until both have answered.
        .task {
            async let occasionsLoaded: Void = occasions.loadIfNeeded()
            await catalogue.loadIfNeeded()
            await occasionsLoaded
        }
        .onChange(of: loaded.map(\.id), initial: true) { _, _ in rejoin() }
        .onChange(of: occasions.available) { _, _ in rejoin() }
        // A length stated is a length the tap owes, and an exercise is re-dialled
        // on another tab.
        .onChange(of: settings.overridesBySlug) { _, _ in rejoin() }
    }

    @ViewBuilder
    private var content: some View {
        if let board, !board.isEmpty {
            list(board)
        } else if catalogue.hasSettled, occasions.hasSettled {
            ContentUnavailableView {
                Label("No moments yet", systemImage: "checklist")
            } description: {
                Text("They download with the catalogue, the first time this phone can reach it.")
            } actions: {
                Button("Try again") {
                    Task {
                        async let occasionsLoaded: Void = occasions.refresh()
                        await catalogue.refresh()
                        await occasionsLoaded
                    }
                }
            }
        } else {
            ReferenceLoadingView(.titled)
        }
    }

    /// The goal pills, pinned under the title: a filter that scrolls away must
    /// be scrolled back to to turn off, and the list under an active pill is
    /// short by definition. Drawn from the *unfiltered* board on purpose — a
    /// row offering only the chosen goal could deselect and never select.
    @ViewBuilder
    private var filters: some View {
        if let board, !board.isEmpty {
            GoalFilterRow(goals: board.goals, selection: $goal)
        }
    }

    /// The moment rows, narrowed to whatever the pills say.
    private func list(_ board: MomentsBoard) -> some View {
        let stops = board.filtered(by: goal)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ScreenSubtitle("Choose by what is happening right now.")

                Section {
                    VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                        ForEach(stops) { stop in
                            MomentCard(stop: stop, tier: plus.tier) {
                                launcher.begin(stop)
                            }
                        }

                        if stops.isEmpty {
                            Text("No moments match that yet.")
                                .font(.callout)
                                .foregroundStyle(Theme.Ink.secondary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.vertical, Theme.Spacing.standard)
                } header: {
                    filters
                }
            }
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

        board = MomentsBoard(
            techniques: techniques,
            occasions: occasions.available,
            dialled: settings.overrides(forSlugsOf: techniques)
        )
    }
}
