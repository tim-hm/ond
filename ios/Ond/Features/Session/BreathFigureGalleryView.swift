import OndKit
import OndStyle
import OndUI
import SwiftUI

/// A prototype of the breath figure, to look at and argue with.
///
/// A debug screen rather than a shipped one: it lands beside the session orb
/// instead of replacing it, and nothing outside `#if DEBUG` links to it. What it
/// is for is the comparison — every choice below is one that could reasonably
/// have gone the other way, so they are knobs here and would be a decision in
/// whatever ships.
///
/// One clock drives every figure on screen. `paused` is not an affordance for
/// its own sake: it is the resting-cost claim made visible, because with the
/// timeline stopped no pose changes, no path is rebuilt, and the whole board
/// costs what a static image costs.
struct BreathFigureGalleryView: View {
    @State private var board: BreathFigureBoard = .phases
    @State private var settings = BreathFigureSettings()
    @State private var isPlaying = true
    @State private var startedAt = Date()
    /// When the clock was stopped, so resuming picks the breath up where it was
    /// left rather than wherever the wall clock has got to. `paused` stops the
    /// redrawing and nothing else, so without this a pause long enough to study a
    /// frame is a pause long enough to lose the phase it was studying.
    @State private var pausedAt: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.loose) {
                Picker("Board", selection: $board) {
                    ForEach(BreathFigureBoard.allCases) { board in
                        Text(board.title).tag(board)
                    }
                }
                .pickerStyle(.segmented)

                // 30 Hz rather than the display's own rate, matching the cap the
                // home screen's orb settled on: a breath moves slowly enough that
                // nothing above it is visible, and four boards' worth of figures
                // is where that stops being a rounding error.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { context in
                    let now = pausedAt ?? context.date
                    let elapsed = Duration.seconds(max(now.timeIntervalSince(startedAt), 0))

                    switch board {
                    case .phases: PhasesBoard(elapsed: elapsed, settings: settings)
                    case .forms: FormsBoard(elapsed: elapsed, settings: settings)
                    case .nostrils: NostrilsBoard(elapsed: elapsed, settings: settings)
                    case .scales: ScalesBoard(elapsed: elapsed, settings: settings)
                    case .appearance: AppearanceBoard(elapsed: elapsed, settings: settings)
                    }
                }
                .frame(maxWidth: .infinity)

                BreathFigureControls(settings: $settings, isPlaying: $isPlaying)
            }
            .padding(Theme.Spacing.standard)
        }
        .paletteGround()
        .navigationTitle("Breath figure")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isPlaying) { _, playing in
            guard playing else { return pausedAt = Date() }
            guard let pausedAt else { return }

            startedAt += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
    }
}

/// The knobs, and only the ones where a real choice was made.
///
/// Split from the gallery because the boards above and the dials below change for
/// entirely different reasons — a new question to ask is a new board, a new thing
/// to try is a new dial.
struct BreathFigureControls: View {
    @Binding var settings: BreathFigureSettings
    @Binding var isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            Toggle("Playing", isOn: $isPlaying)

            choice("Form", $settings.configuration.form)
            choice("Closure", $settings.configuration.closure)
            choice("Cadence", $settings.configuration.cadence)
            choice("Bias", $settings.configuration.bias)
            choice("Side follows", $settings.sideReading)

            Picker("Goal", selection: $settings.goal) {
                ForEach(TechniqueGoal.allCases, id: \.self) { goal in
                    Text(goal.rawValue.capitalized).tag(goal)
                }
            }

            // From three, because two places make a line rather than an aperture
            // — the shape falls back to a plain rim below that, which is a
            // different figure rather than a coarser one.
            Stepper(
                "Places: \(settings.configuration.ringCount)",
                value: $settings.configuration.ringCount,
                in: 3 ... 8
            )

            Toggle("Reduce Motion", isOn: $settings.isStilled)
            Toggle("No colour", isOn: $settings.isMonochrome)
        }
        .font(.subheadline)
        .foregroundStyle(Theme.Ink.primary)
        .tint(Theme.Accent.brand)
        .padding(Theme.Spacing.standard)
        .background(Theme.Surface.raised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    /// One segmented picker over any of the treatments.
    private func choice<Option: FigureTreatment>(
        _ title: String,
        _ selection: Binding<Option>
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.Ink.secondary)
            Picker(title, selection: selection) {
                ForEach(Array(Option.allCases), id: \.self) { option in
                    Text(option.rawValue.capitalized).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// A knob on the figure: a small enum whose raw value is already the word for
/// it, so one generic picker row serves all of them rather than four
/// hand-written ones that would drift apart.
protocol FigureTreatment: CaseIterable, Hashable, RawRepresentable where RawValue == String {}

extension BreathFigure.Form: FigureTreatment {}
extension BreathFigure.Closure: FigureTreatment {}
extension BreathFigure.Cadence: FigureTreatment {}
extension BreathFigure.Bias: FigureTreatment {}
extension BreathLoop.SideReading: FigureTreatment {}

#Preview("Phases") {
    NavigationStack {
        BreathFigureGalleryView()
    }
}

#Preview("Phases, no colour") {
    PhasesBoard(
        elapsed: .seconds(1.4),
        settings: BreathFigureSettings(isMonochrome: true)
    )
    .padding()
    .paletteGround()
}

#Preview("Nostrils") {
    NostrilsBoard(elapsed: .seconds(1.4), settings: BreathFigureSettings())
        .padding()
        .paletteGround()
}

#Preview("Scales") {
    ScalesBoard(elapsed: .seconds(1.4), settings: BreathFigureSettings())
        .padding()
        .paletteGround()
}

#Preview("Light and dark") {
    AppearanceBoard(elapsed: .seconds(9.4), settings: BreathFigureSettings())
        .padding()
        .paletteGround()
}

#Preview("Reduce Motion") {
    PhasesBoard(
        elapsed: .seconds(1.4),
        settings: BreathFigureSettings(isStilled: true)
    )
    .padding()
    .paletteGround()
}
